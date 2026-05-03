import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
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
            ].join('  •  ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(formatNumber(product.stockQuantity),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: product.stockQuantity <= 10
                          ? Theme.of(ctx).colorScheme.error
                          : null,
                    )),
                const Text('in stock', style: TextStyle(fontSize: 11)),
              ]),
              if (canAdjust) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Adjust stock',
                  onPressed: () => _showAdjustDialog(ctx, ref, product),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  void _showAdjustDialog(BuildContext context, WidgetRef ref, ProductModel product) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Adjust stock — ${product.name}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Delta (e.g. +50 or -10)'),
          keyboardType: const TextInputType.numberWithOptions(signed: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final delta = int.tryParse(ctrl.text);
              if (delta == null || delta == 0) return;
              Navigator.pop(dialogCtx);
              try {
                await ref.read(productsRepositoryProvider).adjustStock(product.id, delta);
                ref.read(productsListProvider.notifier).load(refresh: true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
