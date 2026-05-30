import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../../core/network/dio_client.dart';
import '../../widgets/common/pagination_list_view.dart';

final productsListProvider = StateNotifierProvider.autoDispose<_ProductsNotifier,
    AsyncValue<PaginatedResult<ProductModel>>>((ref) {
  return _ProductsNotifier(ref.read(productsRepositoryProvider));
});

class _ProductsNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<ProductModel>>> {
  _ProductsNotifier(this._repo) : super(const AsyncValue.loading()) { load(); }
  final ProductsRepository _repo;
  String? _cursor;
  String _search = '';
  final List<ProductModel> _items = [];

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

  Future<void> search(String q) async { _search = q; await load(refresh: true); }
  Future<void> loadMore() async { if (state.valueOrNull?.hasMore ?? false) await load(); }
}

class ProductsListScreen extends ConsumerWidget {
  const ProductsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productsListProvider);
    final notifier = ref.read(productsListProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;
    final canAdjust = user?.hasPermission('stock', 'update') ?? false;
    final canCreate = user?.hasPermission('products', 'manage') ?? false;

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/products/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
      appBar: AppBar(
        title: const Text('Products'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Search products…',
              leading: const Icon(Icons.search),
              onChanged: notifier.search,
            ),
          ),
        ),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (result) => PaginationListView<ProductModel>(
          items: result.items,
          hasMore: result.hasMore,
          onLoadMore: notifier.loadMore,
          onRefresh: () => notifier.load(refresh: true),
          itemBuilder: (ctx, product) => ListTile(
            title: Text([
              product.name,
              if (product.brand != null) product.brand!,
            ].join('  •  ')),
            subtitle: Text([
              if (product.company != null) product.company!.name,
              if (product.sku != null) 'SKU: ${product.sku}',
              if (product.isLowStock) '⚠ Low stock',
            ].join('  •  ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(formatNumber(product.stockQuantity),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: product.isLowStock
                          ? Theme.of(ctx).colorScheme.error
                          : null,
                    )),
                Text(
                  product.lowStockThreshold != null
                      ? 'min ${product.lowStockThreshold}'
                      : 'in stock',
                  style: TextStyle(
                    fontSize: 11,
                    color: product.isLowStock
                        ? Theme.of(ctx).colorScheme.error
                        : null,
                  ),
                ),
              ]),
              if (canAdjust || canCreate) ...[
                const SizedBox(width: 4),
                PopupMenuButton<_ProductAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    if (action == _ProductAction.adjustStock) {
                      _showAdjustDialog(ctx, ref, product);
                    } else if (action == _ProductAction.ledger) {
                      ctx.go('/products/${product.id}/ledger');
                    } else if (action == _ProductAction.delete) {
                      _showDeleteDialog(ctx, ref, product);
                    }
                  },
                  itemBuilder: (_) => [
                    if (canAdjust) ...[
                      PopupMenuItem(
                        value: _ProductAction.adjustStock,
                        child: const ListTile(
                          leading: Icon(Icons.tune),
                          title: Text('Adjust Stock'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: _ProductAction.ledger,
                        child: const ListTile(
                          leading: Icon(Icons.menu_book_outlined),
                          title: Text('Stock Ledger'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                    if (canCreate)
                      PopupMenuItem(
                        value: _ProductAction.delete,
                        child: const ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, ProductModel product) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Delete "${product.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await ref.read(productsRepositoryProvider).deleteProduct(product.id);
                ref.read(productsListProvider.notifier).load(refresh: true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAdjustDialog(BuildContext context, WidgetRef ref, ProductModel product) {
    final ctrl = TextEditingController();
    int? delta;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setState) {
          final after = delta != null ? product.stockQuantity + delta! : null;
          return AlertDialog(
            title: Text('Adjust stock — ${product.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StockLabel('Before', product.stockQuantity, null),
                    Icon(Icons.arrow_forward,
                        color: Theme.of(dialogCtx).colorScheme.outline),
                    _StockLabel(
                      'After',
                      after ?? product.stockQuantity,
                      after != null && after != product.stockQuantity
                          ? (after > product.stockQuantity ? Colors.green : Colors.orange)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Delta (e.g. +50 or -10)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  onChanged: (v) => setState(() { delta = int.tryParse(v); }),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: delta == null || delta == 0
                    ? null
                    : () async {
                        final d = delta!;
                        Navigator.pop(dialogCtx);
                        try {
                          await ref.read(productsRepositoryProvider).adjustStock(product.id, d);
                          ref.read(productsListProvider.notifier).load(refresh: true);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StockLabel extends StatelessWidget {
  const _StockLabel(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

enum _ProductAction { adjustStock, ledger, delete }
