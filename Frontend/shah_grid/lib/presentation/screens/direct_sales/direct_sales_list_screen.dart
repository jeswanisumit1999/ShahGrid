import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/direct_sale_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/direct_sales_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/pagination_list_view.dart';

final directSalesListProvider = StateNotifierProvider.autoDispose<
    _DirectSalesNotifier, AsyncValue<PaginatedResult<DirectSaleModel>>>((ref) {
  return _DirectSalesNotifier(ref.read(directSalesRepositoryProvider));
});

class _DirectSalesNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<DirectSaleModel>>> {
  _DirectSalesNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }
  final DirectSalesRepository _repo;
  String? _cursor;
  String _search = '';
  final List<DirectSaleModel> _items = [];

  Future<void> load({bool refresh = false}) async {
    if (refresh) { _cursor = null; _items.clear(); }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final r = await _repo.list(cursor: _cursor, search: _search.isEmpty ? null : _search);
      _items.addAll(r.items);
      _cursor = r.nextCursor;
      state = AsyncValue.data(
          PaginatedResult(items: List.unmodifiable(_items), hasMore: r.hasMore));
    } catch (e, st) { state = AsyncValue.error(e, st); }
  }

  Future<void> search(String q) async {
    _search = q;
    await load(refresh: true);
  }

  Future<void> loadMore() async {
    if (state.valueOrNull?.hasMore ?? false) await load();
  }
}

class DirectSalesListScreen extends ConsumerStatefulWidget {
  const DirectSalesListScreen({super.key});

  @override
  ConsumerState<DirectSalesListScreen> createState() => _DirectSalesListScreenState();
}

class _DirectSalesListScreenState extends ConsumerState<DirectSalesListScreen> {
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        ref.read(directSalesListProvider.notifier).search('');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(directSalesListProvider);
    final notifier = ref.read(directSalesListProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;
    final canCreate = user?.hasPermission('orders', 'direct_sale') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by customer name…',
                  border: InputBorder.none,
                ),
                onChanged: (q) => notifier.search(q),
              )
            : const Text('Direct Sales'),
        actions: [
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/direct-sales/new');
                ref.read(directSalesListProvider.notifier).load(refresh: true);
              },
              icon: const Icon(Icons.add),
              label: const Text('New Sale'),
            )
          : null,
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (result) => result.items.isEmpty
            ? RefreshIndicator(
                onRefresh: () => notifier.load(refresh: true),
                child: ListView(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.point_of_sale_outlined,
                              size: 64,
                              color: Theme.of(context).colorScheme.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            _searchCtrl.text.isNotEmpty
                                ? 'No results for "${_searchCtrl.text}"'
                                : 'No direct sales yet',
                            style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (_searchCtrl.text.isEmpty)
                            Text('Tap + New Sale to record one',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.outline)),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : PaginationListView<DirectSaleModel>(
                items: result.items,
                hasMore: result.hasMore,
                onLoadMore: notifier.loadMore,
                onRefresh: () => notifier.load(refresh: true),
                itemBuilder: (ctx, sale) => ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(ctx).colorScheme.secondaryContainer,
                        child: Icon(Icons.person_outline,
                            color: Theme.of(ctx).colorScheme.onSecondaryContainer),
                      ),
                      if (sale.challanNumber != null)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Theme.of(ctx).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.receipt_outlined,
                              size: 12,
                              color: Theme.of(ctx).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(sale.customerName),
                  subtitle: Text([
                    if (sale.salesOfficerName != null) sale.salesOfficerName!,
                    formatDate(sale.createdAt),
                    if (sale.challanNumber != null) 'Challan #${sale.challanNumber}',
                  ].join('  •  ')),
                  trailing: Text(
                    formatCurrency(sale.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () => ctx.go('/direct-sales/${sale.id}'),
                ),
              ),
      ),
    );
  }
}
