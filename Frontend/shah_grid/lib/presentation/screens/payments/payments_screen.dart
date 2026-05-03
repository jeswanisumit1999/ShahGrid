import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/payment_model.dart';
import '../../../data/models/retailer_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/payments_repository.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_error_widget.dart';
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
  final List<PaymentModel> _items = [];

  Future<void> load({bool refresh = false}) async {
    if (refresh) { _cursor = null; _items.clear(); }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final r = await _repo.list(cursor: _cursor);
      _items.addAll(r.items);
      _cursor = r.nextCursor;
      state = AsyncValue.data(
          PaginatedResult(items: List.unmodifiable(_items), hasMore: r.hasMore));
    } catch (e, st) { state = AsyncValue.error(e, st); }
  }

  Future<void> loadMore() async { if (state.valueOrNull?.hasMore ?? false) await load(); }
}

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_paymentsProvider);
    final notifier = ref.read(_paymentsProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;
    final canRecord = user?.hasPermission('payments', 'record') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      floatingActionButton: canRecord
          ? FloatingActionButton.extended(
              onPressed: () => _showRecordDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Record Payment'),
            )
          : null,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (result) => PaginationListView(
          items: result.items,
          hasMore: result.hasMore,
          onLoadMore: notifier.loadMore,
          onRefresh: () => notifier.load(refresh: true),
          itemBuilder: (ctx, payment) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.payments)),
            title: Text(payment.retailerName ?? payment.retailerId),
            subtitle: Text('${payment.method.toUpperCase()}  •  ${formatDate(payment.paymentDate)}'),
            trailing: Text(formatCurrency(payment.amount),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  void _showRecordDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _RecordPaymentSheet(
        onSaved: () => ref.read(_paymentsProvider.notifier).load(refresh: true),
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
    final result = await ref.read(retailersRepositoryProvider).list(limit: 100);
    if (!mounted) return;
    final picked = await showDialog<RetailerModel>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Select Retailer'),
        children: result.items.map((r) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogCtx, r),
          child: ListTile(
            title: Text(r.name),
            subtitle: Text('Available: ${formatCurrency(r.availableCredit)}'),
            dense: true,
          ),
        )).toList(),
      ),
    );
    if (picked != null) setState(() => _selectedRetailer = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedRetailer == null) {
      setState(() => _error = 'Please select a retailer');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(paymentsRepositoryProvider).record(
        retailerId: _selectedRetailer!.id,
        amount: double.parse(_amountCtrl.text),
        paymentDate: _date.toIso8601String().substring(0, 10),
        method: _method,
        referenceNo: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Record Payment', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // Retailer picker
          InkWell(
            onTap: _pickRetailer,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Retailer',
                border: const OutlineInputBorder(),
                errorText: (_error != null && _selectedRetailer == null) ? 'Required' : null,
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _selectedRetailer?.name ?? 'Select a retailer…',
                    style: TextStyle(
                      color: _selectedRetailer == null
                          ? Theme.of(context).hintColor
                          : null,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
          ),
          const SizedBox(height: 12),

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
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
