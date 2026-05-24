import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../../data/models/analytics_model.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/user_model.dart';
import '../../widgets/common/app_error_widget.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;

    // Permission-based section visibility
    final isAdminLevel = _hasAny(user, ['analytics.read']) &&
        _hasAny(user, ['users.read', 'users.manage', 'roles.manage']);
    final showMyStats = !isAdminLevel &&
        _hasAny(user, [
          'orders.read', 'orders.create', 'orders.manage',
          'payments.read', 'payments.record',
          'visits.read', 'visits.create',
        ]);
    final showStockAlerts =
        _hasAny(user, ['stock.update', 'products.manage', 'shipments.manage']);
    final showGodownStats = _hasAny(user, ['shipments.manage']);
    final showCheckinShortcut = !isAdminLevel && _hasAny(user, ['checkins.create']);
    final showAssignedRetailers = !isAdminLevel && _hasAny(user, ['orders.create']) &&
        !_hasAny(user, ['orders.manage', 'shipments.manage']);

    final showNothing = !isAdminLevel && !showMyStats && !showStockAlerts &&
        !showGodownStats && !showCheckinShortcut && !showAssignedRetailers;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          if (isAdminLevel) ref.invalidate(dashboardProvider);
          if (showMyStats) ref.invalidate(myStatsProvider);
          if (showStockAlerts) ref.invalidate(stockAlertsProvider);
          if (showGodownStats) ref.invalidate(godownStatsProvider);
          if (showAssignedRetailers) ref.invalidate(assignedRetailersProvider);
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

            if (showCheckinShortcut) ...[
              _CheckInShortcut(),
              const SizedBox(height: 16),
            ],

            if (isAdminLevel) _GlobalStatsSection(ref: ref),

            if (showAssignedRetailers) ...[
              _AssignedRetailersSection(ref: ref),
              const SizedBox(height: 24),
            ],

            if (showMyStats)
              _MyStatsSection(
                ref: ref,
                hasOrders: _hasAny(user, ['orders.read', 'orders.create', 'orders.manage']),
                hasPayments: _hasAny(user, ['payments.read', 'payments.record']),
                hasVisits: _hasAny(user, ['visits.read', 'visits.create']),
              ),

            if (showGodownStats) ...[
              _GodownStatsSection(ref: ref),
              const SizedBox(height: 24),
            ],

            if (showMyStats && showStockAlerts) const SizedBox(height: 24),

            if (showStockAlerts) _StockAlertsSection(ref: ref),

            if (showNothing)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No dashboard data available for your role.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Contact your Admin to assign permissions.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _hasAny(UserModel? user, List<String> perms) =>
      perms.any((p) => user?.permissions.contains(p) ?? false);
}

// ── Check-In Shortcut ─────────────────────────────────────────────────────────

class _CheckInShortcut extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.location_on),
        title: const Text('Record Check-In'),
        subtitle: const Text('Log a retailer visit'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/checkins'),
      ),
    );
  }
}

// ── Assigned Retailers ────────────────────────────────────────────────────────

class _AssignedRetailersSection extends StatelessWidget {
  const _AssignedRetailersSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assignedRetailersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(
          error: e, onRetry: () => ref.invalidate(assignedRetailersProvider)),
      data: (retailers) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Retailers', style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => context.go('/retailers'),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (retailers.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 12),
                    const Text('No retailers assigned yet'),
                  ],
                ),
              ),
            )
          else
            ...retailers.take(5).map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    title: Text(r.name),
                    subtitle: Text(r.phone),
                    trailing: Icon(Icons.chevron_right,
                        color: Theme.of(context).colorScheme.outline),
                    onTap: () => context.go('/retailers/${r.id}'),
                  ),
                )),
          if (retailers.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: TextButton(
                  onPressed: () => context.go('/retailers'),
                  child: Text('+ ${retailers.length - 5} more'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Global Stats (Admin-level) ────────────────────────────────────────────────

class _GlobalStatsSection extends StatelessWidget {
  const _GlobalStatsSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dashboardProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          AppErrorWidget(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
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

// ── Personal Stats ────────────────────────────────────────────────────────────

class _MyStatsSection extends StatelessWidget {
  const _MyStatsSection({
    required this.ref,
    required this.hasOrders,
    required this.hasPayments,
    required this.hasVisits,
  });
  final WidgetRef ref;
  final bool hasOrders;
  final bool hasPayments;
  final bool hasVisits;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myStatsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          AppErrorWidget(error: e, onRetry: () => ref.invalidate(myStatsProvider)),
      data: (data) {
        final cards = <Widget>[];

        if (hasOrders) {
          cards.add(_StatCard(
            label: 'My Orders',
            value: '${data.orderCount}',
            icon: Icons.receipt_long,
          ));
        }
        if (hasVisits) {
          if (cards.isNotEmpty) cards.add(const SizedBox(width: 12));
          cards.add(_StatCard(
            label: 'Visits',
            value: '${data.visitCount}',
            icon: Icons.pin_drop,
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Activity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (cards.isNotEmpty) Row(children: cards),
            if (hasPayments) ...[
              const SizedBox(height: 12),
              _StatCard(
                label: 'Payments Collected',
                value: formatCurrency(data.totalPaymentsCollected),
                icon: Icons.payments,
                fullWidth: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Godown Stats ──────────────────────────────────────────────────────────────

class _GodownStatsSection extends StatelessWidget {
  const _GodownStatsSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(godownStatsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          AppErrorWidget(error: e, onRetry: () => ref.invalidate(godownStatsProvider)),
      data: (stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shipment Summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ShipmentStatCard(
            label: 'Pending Stock Availability',
            count: stats.pendingAvailability,
            icon: Icons.hourglass_empty,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          _ShipmentStatCard(
            label: 'Pending Stock Verification',
            count: stats.pendingVerification,
            icon: Icons.fact_check_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(height: 8),
          _ShipmentStatCard(
            label: 'Ready for Dispatch',
            count: stats.readyForDispatch,
            icon: Icons.local_shipping_outlined,
            color: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _ShipmentStatCard extends StatelessWidget {
  const _ShipmentStatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              '$count',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: count > 0 ? color : Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stock Alerts ──────────────────────────────────────────────────────────────

class _StockAlertsSection extends StatelessWidget {
  const _StockAlertsSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockAlertsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          AppErrorWidget(error: e, onRetry: () => ref.invalidate(stockAlertsProvider)),
      data: (products) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Low Stock Alerts', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              if (products.isNotEmpty)
                Badge(
                  label: Text('${products.length}'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (products.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    const Text('All products are well stocked'),
                  ],
                ),
              ),
            )
          else
            ...products.map((p) => _StockAlertCard(product: p)),
        ],
      ),
    );
  }
}

class _StockAlertCard extends StatelessWidget {
  const _StockAlertCard({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final isOut = product.stockQuantity == 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isOut ? Icons.remove_shopping_cart : Icons.warning_amber_rounded,
          color: isOut
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.tertiary,
        ),
        title: Text(product.name),
        subtitle: Text(product.company?.name ?? ''),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${product.stockQuantity} left',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isOut
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
              ),
            ),
            Text(
              'threshold: ${product.lowStockThreshold}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (product.sku != null)
              Text(product.sku!, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        onTap: () => context.go('/products'),
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

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
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
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
