import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/stock_ledger_model.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _ledgerProvider = StateNotifierProvider.autoDispose
    .family<_LedgerNotifier, AsyncValue<_LedgerState>, String>(
  (ref, productId) => _LedgerNotifier(ref.read(productsRepositoryProvider), productId),
);

class _LedgerState {
  const _LedgerState({
    required this.items,
    required this.hasMore,
    required this.productName,
    required this.productSku,
    required this.currentStock,
    this.direction,
  });
  final List<StockLedgerEntry> items;
  final bool hasMore;
  final String productName;
  final String? productSku;
  final int currentStock;
  final String? direction; // null = All, 'in', 'out'
}

class _LedgerNotifier extends StateNotifier<AsyncValue<_LedgerState>> {
  _LedgerNotifier(this._repo, this._productId)
      : super(const AsyncValue.loading()) {
    load();
  }

  final ProductsRepository _repo;
  final String _productId;
  String? _cursor;
  String? _direction;
  final List<StockLedgerEntry> _items = [];
  String _productName = '';
  String? _productSku;
  int _currentStock = 0;

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final r = await _repo.getStockLedger(
        _productId,
        cursor: _cursor,
        direction: _direction,
      );
      if (r.product.isNotEmpty) {
        _productName = r.product['name'] as String? ?? '';
        _productSku = r.product['sku'] as String?;
        _currentStock = r.product['stockQuantity'] as int? ?? 0;
      }
      _items.addAll(r.items);
      _cursor = r.nextCursor;
      state = AsyncValue.data(_LedgerState(
        items: List.unmodifiable(_items),
        hasMore: r.hasMore,
        productName: _productName,
        productSku: _productSku,
        currentStock: _currentStock,
        direction: _direction,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void setDirection(String? dir) {
    _direction = dir;
    load(refresh: true);
  }

  Future<void> loadMore() async {
    if (state.valueOrNull?.hasMore ?? false) await load();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class StockLedgerScreen extends ConsumerWidget {
  const StockLedgerScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ledgerProvider(productId));
    final notifier = ref.read(_ledgerProvider(productId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: async.when(
          loading: () => const Text('Stock Ledger'),
          error: (_, __) => const Text('Stock Ledger'),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.productName, style: const TextStyle(fontSize: 16)),
              if (s.productSku != null)
                Text('SKU: ${s.productSku}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (state) => _LedgerBody(
          state: state,
          notifier: notifier,
          productId: productId,
        ),
      ),
    );
  }
}

class _LedgerBody extends ConsumerStatefulWidget {
  const _LedgerBody({
    required this.state,
    required this.notifier,
    required this.productId,
  });
  final _LedgerState state;
  final _LedgerNotifier notifier;
  final String productId;

  @override
  ConsumerState<_LedgerBody> createState() => _LedgerBodyState();
}

class _LedgerBodyState extends ConsumerState<_LedgerBody> {
  late int _filterIndex;
  final _scrollCtrl = ScrollController();

  static const _directions = [null, 'in', 'out'];

  static int _directionToIndex(String? dir) =>
      dir == 'in' ? 1 : dir == 'out' ? 2 : 0;

  @override
  void initState() {
    super.initState();
    _filterIndex = _directionToIndex(widget.state.direction);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      widget.notifier.loadMore();
    }
  }

  void _setFilter(int index) {
    if (index == _filterIndex) return;
    setState(() => _filterIndex = index);
    widget.notifier.setDirection(_directions[index]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = widget.state;
    final entries = state.items;

    return Column(
      children: [
        // ── Product stock summary ──────────────────────────────────────────
        Container(
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Current Stock', style: theme.textTheme.labelSmall),
                  Text(
                    formatNumber(state.currentStock),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: state.currentStock <= 0 ? cs.error : null,
                    ),
                  ),
                ]),
              ),
              Text('units', style: theme.textTheme.bodySmall),
            ],
          ),
        ),

        // ── Direction filter ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('All')),
              ButtonSegment(value: 1, icon: Icon(Icons.arrow_downward, size: 14), label: Text('Stock In')),
              ButtonSegment(value: 2, icon: Icon(Icons.arrow_upward, size: 14), label: Text('Stock Out')),
            ],
            selected: {_filterIndex},
            onSelectionChanged: (s) => _setFilter(s.first),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),

        // ── Table header ───────────────────────────────────────────────────
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Expanded(flex: 3, child: Text('Date / Type', style: theme.textTheme.labelSmall)),
            SizedBox(width: 52, child: Text('In', textAlign: TextAlign.right, style: theme.textTheme.labelSmall?.copyWith(color: Colors.green.shade700))),
            SizedBox(width: 52, child: Text('Out', textAlign: TextAlign.right, style: theme.textTheme.labelSmall?.copyWith(color: cs.error))),
            SizedBox(width: 60, child: Text('Balance', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
          ]),
        ),
        const Divider(height: 1),

        // ── Ledger rows ────────────────────────────────────────────────────
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No stock movements found'))
              : ListView.separated(
                  controller: _scrollCtrl,
                  itemCount: entries.length + (state.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                  itemBuilder: (ctx, i) {
                    if (i >= entries.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final e = entries[i];
                    return _LedgerRow(entry: e, onTap: () => _navigate(ctx, e));
                  },
                ),
        ),
      ],
    );
  }

  void _navigate(BuildContext ctx, StockLedgerEntry e) {
    if (e.referenceType == 'Shipment' && e.referenceId != null) {
      ctx.go('/shipments/${e.referenceId}');
    } else if (e.referenceType == 'Order' && e.referenceId != null) {
      ctx.go('/orders/${e.referenceId}');
    }
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.onTap});
  final StockLedgerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isIn = entry.isIn;
    final hasRef = entry.referenceType != null && entry.referenceId != null;
    final shortRef = entry.referenceId?.substring(0, 8).toUpperCase();

    return InkWell(
      onTap: hasRef ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + label
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatDate(entry.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
                const SizedBox(height: 2),
                Text(entry.label, style: theme.textTheme.bodyMedium),
                if (shortRef != null)
                  Text(
                    '${entry.referenceType} · $shortRef${hasRef ? ' ↗' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasRef ? cs.primary : cs.outline,
                    ),
                  ),
                if (entry.actorName != null)
                  Text(entry.actorName!,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
              ]),
            ),
            // In column
            SizedBox(
              width: 52,
              child: isIn
                  ? Text(
                      '+${entry.delta}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Out column
            SizedBox(
              width: 52,
              child: !isIn
                  ? Text(
                      '${entry.delta}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Balance
            SizedBox(
              width: 60,
              child: Text(
                formatNumber(entry.balanceAfter),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: entry.balanceAfter <= 0 ? cs.error : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
