import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/pagination_list_view.dart';

class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ordersProvider);
    final notifier = ref.read(ordersProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;
    final canCreate = user?.hasPermission('orders', 'create') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
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
        data: (result) => PaginationListView(
          items: result.items,
          hasMore: result.hasMore,
          onLoadMore: notifier.loadMore,
          onRefresh: () => notifier.load(refresh: true),
          itemBuilder: (ctx, order) => Card(
            child: ListTile(
              title: Text(order.retailerName ?? order.retailerId),
              subtitle: Text('${order.orderItems.length} item(s)  •  ${formatDate(order.createdAt)}'),
              trailing: Text(
                formatCurrency(order.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => ctx.go('/orders/${order.id}'),
            ),
          ),
        ),
      ),
    );
  }
}
