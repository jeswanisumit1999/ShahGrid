import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/payment_model.dart';
import '../../../data/models/retailer_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/payments_repository.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/format_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/retailer_search_dialog.dart';
import '../../widgets/common/pagination_list_view.dart';

final _paymentsProvider = StateNotifierProvider.autoDispose<_PaymentsNotifier,
    AsyncValue<PaginatedResult<PaymentModel>>>((ref) {
  return _PaymentsNotifier(ref.read(paymentsRepositoryProvider));
});

class _PaymentsNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<PaymentModel>>> {
  _PaymentsNotifier(this._repo) : super(const AsyncValue.loading()) { load(); }
  final PaymentsRepository _repo;
  String? _cursor;
  String? _search;
  final List<PaymentModel> _items = [];

  Future<void> load({bool refresh = false}) async {
    if (refresh) { _cursor = null; _items.clear(); }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final r = await _repo.list(cursor: _cursor, search: _search);
      _items.addAll(r.items);
      _cursor = r.nextCursor;
      state = AsyncValue.data(
          PaginatedResult(items: List.unmodifiable(_items), hasMore: r.hasMore));
    } catch (e, st) { state = AsyncValue.error(e, st); }
  }

  void search(String query) {
    _search = query.trim().isEmpty ? null : query.trim();
    load(refresh: true);
  }

  Future<void> loadMore() async { if (state.valueOrNull?.hasMore ?? false) await load(); }
}

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String? _methodFilter;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(_paymentsProvider.notifier).search(value);
    });
  }

  void _showRecordDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _RecordPaymentSheet(
        onSaved: () => ref.read(_paymentsProvider.notifier).load(refresh: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_paymentsProvider);
    final notifier = ref.read(_paymentsProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;
    final canRecord = user?.hasPermission('payments', 'record') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      floatingActionButton: canRecord
          ? FloatingActionButton.extended(
              onPressed: _showRecordDialog,
              icon: const Icon(Icons.add),
              label: const Text('Record Payment'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by retailer or reference no.',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // Method filter chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final method in ['All', ...PaymentModel.methods])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(method == 'All' ? 'All' : method.toUpperCase()),
                      selected: method == 'All' ? _methodFilter == null : _methodFilter == method,
                      onSelected: (_) => setState(() {
                        _methodFilter = method == 'All' ? null : method;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
              data: (result) {
                final visible = _methodFilter == null
                    ? result.items
                    : result.items.where((p) => p.method == _methodFilter).toList();
                final total = visible.fold(0.0, (sum, p) => sum + p.amount);
                return Column(
                  children: [
                    // Summary bar
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${visible.length} payment${visible.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(formatCurrency(total),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PaginationListView(
                        items: visible,
                        hasMore: _methodFilter == null ? result.hasMore : false,
                        onLoadMore: notifier.loadMore,
                        onRefresh: () => notifier.load(refresh: true),
                        itemBuilder: (ctx, payment) {
                          final extraLines = [
                            if (payment.companyName != null) payment.companyName!,
                            if (payment.referenceNo != null) 'Ref: ${payment.referenceNo}',
                          ];
                          final subtitle =
                              '${payment.method.toUpperCase()}  •  ${formatDate(payment.paymentDate)}'
                              '${extraLines.isNotEmpty ? '\n${extraLines.join('  •  ')}' : ''}';
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.payments)),
                            title: Text(payment.retailerName ?? payment.retailerId),
                            subtitle: Text(subtitle),
                            isThreeLine: extraLines.isNotEmpty,
                            trailing: Text(formatCurrency(payment.amount),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  RetailerModel? _selectedRetailer;
  CompanyBalance? _selectedCompany;
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRetailer() async {
    try {
      final result = await ref.read(retailersRepositoryProvider).list(limit: 200);
      if (!mounted) return;
      final picked = await showDialog<RetailerModel>(
        context: context,
        useRootNavigator: true,
        builder: (_) => RetailerSearchDialog(retailers: result.items),
      );
      if (picked != null) setState(() { _selectedRetailer = picked; _selectedCompany = null; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickCompany() async {
    final balances = _selectedRetailer!.companyBalances;
    if (balances.isEmpty) return;
    final picked = await showDialog<CompanyBalance>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Select Company'),
        children: balances.map((b) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogCtx, b),
          child: ListTile(
            title: Text(b.companyName),
            subtitle: Text('Pending: ${formatCurrency(b.pendingAmount)}'),
            dense: true,
          ),
        )).toList(),
      ),
    );
    if (picked != null) setState(() => _selectedCompany = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedRetailer == null) {
      setState(() => _error = 'Please select a retailer');
      return;
    }
    final hasCompanies = _selectedRetailer!.companyBalances.isNotEmpty;
    if (hasCompanies && _selectedCompany == null) {
      setState(() => _error = 'Please select a company');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(paymentsRepositoryProvider).record(
        retailerId: _selectedRetailer!.id,
        companyId: _selectedCompany?.companyId,
        amount: double.parse(_amountCtrl.text),
        paymentDate: _date.toIso8601String().substring(0, 10),
        method: _method,
        referenceNo: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final retailer = _selectedRetailer;
    final hasCompanies = retailer?.companyBalances.isNotEmpty ?? false;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Record Payment', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),

          // Retailer picker
          InkWell(
            onTap: _pickRetailer,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Retailer',
                border: const OutlineInputBorder(),
                errorText: (_error != null && retailer == null) ? 'Required' : null,
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    retailer?.name ?? 'Select a retailer…',
                    style: TextStyle(color: retailer == null ? theme.hintColor : null),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
          ),

          if (retailer != null) ...[
            const SizedBox(height: 10),

            // Company picker (required when retailer has companies)
            if (hasCompanies) ...[
              InkWell(
                onTap: _pickCompany,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Company *',
                    border: const OutlineInputBorder(),
                    errorText: (_error == 'Please select a company') ? 'Required' : null,
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        _selectedCompany?.companyName ?? 'Select company…',
                        style: TextStyle(color: _selectedCompany == null ? theme.hintColor : null),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Pending amount info — company-specific if selected, else overall
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: () {
                final pending = _selectedCompany?.pendingAmount ?? retailer.pendingCollection;
                final label = _selectedCompany != null
                    ? 'Pending — ${_selectedCompany!.companyName}'
                    : 'Total Pending Collection';
                return Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: theme.textTheme.labelSmall),
                    Text(
                      formatCurrency(pending),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: pending > 0 ? cs.error : null,
                      ),
                    ),
                  ])),
                  if (_selectedCompany == null) ...[
                    Container(width: 1, height: 32, color: theme.dividerColor),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Available Credit', style: theme.textTheme.labelSmall),
                      Text(formatCurrency(retailer.availableCredit),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ])),
                  ],
                ]);
              }(),
            ),
            const SizedBox(height: 12),
          ],
          if (retailer == null) const SizedBox(height: 12),

          TextFormField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount (₹)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a valid amount' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              labelText: 'Method',
              border: OutlineInputBorder(),
            ),
            items: PaymentModel.methods
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Reference No. (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null && _error != 'Please select a company') ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Payment'),
            ),
          ),
        ]),
      ),
    );
  }
}
