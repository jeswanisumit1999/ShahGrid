import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/retailer_ledger_model.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';

final _retailerLedgerProvider = StateNotifierProvider.autoDispose
    .family<_LedgerNotifier, AsyncValue<_LedgerState>, String>(
  (ref, retailerId) =>
      _LedgerNotifier(ref.read(retailersRepositoryProvider), retailerId),
);

class _LedgerState {
  const _LedgerState({
    required this.items,
    required this.hasMore,
    required this.retailerName,
    required this.currentBalance,
  });
  final List<RetailerLedgerEntry> items;
  final bool hasMore;
  final String retailerName;
  final double currentBalance;
}

class _LedgerNotifier extends StateNotifier<AsyncValue<_LedgerState>> {
  _LedgerNotifier(this._repo, this._retailerId)
      : super(const AsyncValue.loading()) {
    load();
  }

  final RetailersRepository _repo;
  final String _retailerId;
  String? _cursor;
  final List<RetailerLedgerEntry> _items = [];
  String _retailerName = '';
  double _currentBalance = 0;

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final r = await _repo.getRetailerLedger(_retailerId, cursor: _cursor);
      if (r.retailer.isNotEmpty) {
        _retailerName = r.retailer['name'] as String? ?? '';
        _currentBalance =
            double.tryParse(r.retailer['pendingCollection']?.toString() ?? '') ??
                0;
      }
      _items.addAll(r.items);
      _cursor = r.nextCursor;
      state = AsyncValue.data(_LedgerState(
        items: List.unmodifiable(_items),
        hasMore: r.hasMore,
        retailerName: _retailerName,
        currentBalance: _currentBalance,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (state.valueOrNull?.hasMore ?? false) await load();
  }
}

class RetailerLedgerScreen extends ConsumerWidget {
  const RetailerLedgerScreen({super.key, required this.retailerId});
  final String retailerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_retailerLedgerProvider(retailerId));
    final notifier = ref.read(_retailerLedgerProvider(retailerId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: async.when(
          loading: () => const Text('Payment Ledger'),
          error: (_, __) => const Text('Payment Ledger'),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.retailerName, style: const TextStyle(fontSize: 16)),
              const Text('Payment Ledger',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (state) => _LedgerBody(state: state, notifier: notifier),
      ),
    );
  }
}

class _LedgerBody extends ConsumerStatefulWidget {
  const _LedgerBody({required this.state, required this.notifier});
  final _LedgerState state;
  final _LedgerNotifier notifier;

  @override
  ConsumerState<_LedgerBody> createState() => _LedgerBodyState();
}

class _LedgerBodyState extends ConsumerState<_LedgerBody> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      widget.notifier.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = widget.state;
    final entries = state.items;

    return Column(
      children: [
        // Current balance header
        Container(
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Outstanding Balance',
                          style: theme.textTheme.labelSmall),
                      Text(
                        formatCurrency(state.currentBalance),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              state.currentBalance > 0 ? cs.error : null,
                        ),
                      ),
                    ]),
              ),
            ],
          ),
        ),

        // Table header
        const Divider(height: 1),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Expanded(
                flex: 3,
                child: Text('Date / Type',
                    style: theme.textTheme.labelSmall)),
            SizedBox(
                width: 70,
                child: Text('Debit',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.error))),
            SizedBox(
                width: 70,
                child: Text('Credit',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.green.shade700))),
            SizedBox(
                width: 72,
                child: Text('Balance',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall)),
          ]),
        ),
        const Divider(height: 1),

        // Ledger rows
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No payment history found'))
              : ListView.separated(
                  controller: _scrollCtrl,
                  itemCount: entries.length + (state.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (ctx, i) {
                    if (i >= entries.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child:
                            Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _LedgerRow(
                        entry: entries[i],
                        onTap: () => _navigate(ctx, entries[i]));
                  },
                ),
        ),
      ],
    );
  }

  void _navigate(BuildContext ctx, RetailerLedgerEntry e) {
    if (e.referenceType == 'Order' && e.referenceId != null) {
      ctx.go('/orders/${e.referenceId}');
    }
    // Payments don't have a detail screen to navigate to
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.onTap});
  final RetailerLedgerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDebit = entry.isDebit;
    final hasRef =
        entry.referenceType == 'Order' && entry.referenceId != null;
    final shortRef =
        entry.referenceId?.substring(0, 8).toUpperCase();

    return InkWell(
      onTap: hasRef ? onTap : null,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDate(entry.createdAt),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.outline)),
                    const SizedBox(height: 2),
                    Text(entry.label,
                        style: theme.textTheme.bodyMedium),
                    if (entry.companyName != null)
                      Text(entry.companyName!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline)),
                    if (shortRef != null)
                      Text(
                        '${entry.referenceType} · $shortRef${hasRef ? ' ↗' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              hasRef ? cs.primary : cs.outline,
                        ),
                      ),
                    if (entry.actorName != null)
                      Text(entry.actorName!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline)),
                  ]),
            ),
            // Debit column
            SizedBox(
              width: 70,
              child: isDebit
                  ? Text(
                      formatCurrency(entry.delta),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w600),
                    )
                  : const SizedBox.shrink(),
            ),
            // Credit column
            SizedBox(
              width: 70,
              child: !isDebit
                  ? Text(
                      formatCurrency(-entry.delta),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600),
                    )
                  : const SizedBox.shrink(),
            ),
            // Balance
            SizedBox(
              width: 72,
              child: Text(
                formatCurrency(entry.balanceAfter),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: entry.balanceAfter > 0 ? cs.error : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
