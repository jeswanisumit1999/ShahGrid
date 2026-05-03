import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/order_model.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/status_badge.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final isSalesOfficer = user?.hasRole('Sales Officer') ?? false;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
          ref.invalidate(myStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Welcome, ${user?.name ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              user?.roles.join(', ') ?? '',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 20),

            // Sales officer sees personal stats; admins/supply chain see global dashboard
            if (isSalesOfficer) ...[
              _MyStatsSection(ref: ref),
            ] else ...[
              _AdminDashboardSection(ref: ref),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardSection extends StatelessWidget {
  const _AdminDashboardSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dashboardProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _StatCard(label: 'Total Orders', value: '${data.totalOrders}', icon: Icons.receipt_long),
            const SizedBox(width: 12),
            _StatCard(label: 'Retailers', value: '${data.totalRetailers}', icon: Icons.storefront),
          ]),
          const SizedBox(height: 12),
          _StatCard(
            label: 'Pending Collection',
            value: formatCurrency(data.totalPendingCollection),
            icon: Icons.account_balance_wallet,
            fullWidth: true,
          ),
          const SizedBox(height: 24),
          Text('Recent Orders', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...data.recentOrders.map((o) => _OrderCard(order: o)),
        ],
      ),
    );
  }
}

class _MyStatsSection extends StatelessWidget {
  const _MyStatsSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myStatsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(myStatsProvider)),
      data: (data) => Column(
        children: [
          Row(children: [
            _StatCard(label: 'My Orders', value: '${data.orderCount}', icon: Icons.receipt_long),
            const SizedBox(width: 12),
            _StatCard(label: 'Visits', value: '${data.visitCount}', icon: Icons.pin_drop),
          ]),
          const SizedBox(height: 12),
          _StatCard(
            label: 'Payments Collected',
            value: formatCurrency(data.totalPaymentsCollected),
            icon: Icons.payments,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
    return fullWidth ? card : Expanded(child: card);
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(order.retailerName ?? order.retailerId),
        subtitle: Text(formatCurrency(order.totalAmount)),
        trailing: Text(formatDate(order.createdAt)),
        onTap: () => context.go('/orders/${order.id}'),
      ),
    );
  }
}
