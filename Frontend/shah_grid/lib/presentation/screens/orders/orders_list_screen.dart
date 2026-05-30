import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/pagination_list_view.dart';
import '../../widgets/common/status_badge.dart';

class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  bool _myOrdersOnly = true;
  bool _initialized = false;
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final user = ref.read(authStateProvider).valueOrNull;
      final isSalesOfficer = (user?.hasPermission('orders', 'create') ?? false) &&
          !(user?.hasPermission('orders', 'manage') ?? false);
      if (!isSalesOfficer) _myOrdersOnly = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_myOrdersOnly && user != null) {
          ref.read(ordersProvider.notifier).filterBySalesOfficer(user.id);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleFilter() {
    final user = ref.read(authStateProvider).valueOrNull;
    setState(() => _myOrdersOnly = !_myOrdersOnly);
    ref.read(ordersProvider.notifier).filterBySalesOfficer(
          _myOrdersOnly ? user?.id : null,
        );
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        ref.read(ordersProvider.notifier).search(null);
      }
    });
  }

  void _onSearchChanged(String query) {
    ref.read(ordersProvider.notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersProvider);
    final notifier = ref.read(ordersProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;

    final canCreate = user?.hasPermission('orders', 'create') ?? false;
    final isSalesOfficer = canCreate && !(user?.hasPermission('orders', 'manage') ?? false);

    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by retailer name…',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('Orders'),
        actions: [
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            tooltip: _searchVisible ? 'Close search' : 'Search',
            onPressed: _toggleSearch,
          ),
          if (isSalesOfficer && !_searchVisible)
            TextButton.icon(
              icon: Icon(_myOrdersOnly ? Icons.people : Icons.person),
              label: Text(_myOrdersOnly ? 'My Orders' : 'All'),
              onPressed: _toggleFilter,
            ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/orders/new'),
              icon: const Icon(Icons.add),
              label: const Text('New Order'),
            )
          : null,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (result) => result.items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 16),
                    Text(
                      _searchCtrl.text.isNotEmpty
                          ? 'No orders match "${_searchCtrl.text}"'
                          : 'No orders yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              )
            : PaginationListView(
                items: result.items,
                hasMore: result.hasMore,
                onLoadMore: notifier.loadMore,
                onRefresh: () => notifier.load(refresh: true),
                itemBuilder: (ctx, order) {
                  final shipmentStatuses = order.shipments
                      .whereType<Map>()
                      .map((s) => s['status'] as String? ?? '')
                      .toList();
                  final orderStatus = _deriveOrderStatus(shipmentStatuses);
                  return Card(
                    child: ListTile(
                      title: Text(order.retailerName ?? order.retailerId),
                      subtitle: Text(
                          '${order.orderItems.length} item(s)  •  ${formatDate(order.createdAt)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatCurrency(order.totalAmount),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          StatusBadge(orderStatus),
                        ],
                      ),
                      onTap: () => ctx.go('/orders/${order.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _deriveOrderStatus(List<String> shipmentStatuses) {
  if (shipmentStatuses.isEmpty) return 'Pending';
  const terminal = {'Delivered', 'Cancelled', 'Returned'};
  final allTerminal = shipmentStatuses.every(terminal.contains);
  if (allTerminal) {
    if (shipmentStatuses.any((s) => s == 'Delivered')) return 'Delivered';
    if (shipmentStatuses.any((s) => s == 'Returned')) return 'Returned';
    return 'Cancelled';
  }
  if (shipmentStatuses.any((s) => s == 'Ready for Dispatch')) return 'Ready';
  return 'Processing';
}
