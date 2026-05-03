import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/repositories/orders_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/pdf_downloader.dart';
import '../../../data/models/order_model.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/status_badge.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(id));

    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e),
        data: (order) => _OrderBody(order: order),
      ),
    );
  }
}

class _OrderBody extends ConsumerStatefulWidget {
  const _OrderBody({required this.order});
  final OrderModel order;

  @override
  ConsumerState<_OrderBody> createState() => _OrderBodyState();
}

class _OrderBodyState extends ConsumerState<_OrderBody> {
  bool _generatingChallan = false;

  Future<void> _generateChallan() async {
    setState(() => _generatingChallan = true);
    try {
      final bytes = await ref.read(ordersRepositoryProvider).downloadChallan(widget.order.id);
      final shortId = widget.order.id.split('-').first.toUpperCase();
      await downloadPdf(bytes, 'challan_$shortId.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate challan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingChallan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGenerateChallan = ref.watch(authStateProvider).valueOrNull
            ?.hasPermission('challans', 'generate') ??
        false;
    final order = widget.order;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Retailer', style: Theme.of(context).textTheme.labelMedium),
              Text(order.retailerName ?? order.retailerId,
                  style: Theme.of(context).textTheme.titleMedium),
              const Divider(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sales Officer', style: Theme.of(context).textTheme.labelSmall),
                  Text(order.salesOfficerName ?? '—'),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Date', style: Theme.of(context).textTheme.labelSmall),
                  Text(formatDate(order.createdAt)),
                ]),
              ]),
              const Divider(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total'),
                Text(formatCurrency(order.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
              if (order.isDirectSale) ...[
                const SizedBox(height: 8),
                const StatusBadge('Direct Sale'),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // Order items
        Text('Items', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...order.orderItems.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(item.product?.name ?? item.productId),
                subtitle: Text('${formatNumber(item.quantity)} × ${formatCurrency(item.unitPrice)}'),
                trailing: Text(formatCurrency(item.lineTotal),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            )),

        // Shipments
        if (order.shipments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Shipments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...order.shipments.map((s) {
            final ship = s as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(ship['id'].toString().substring(0, 8)),
                trailing: StatusBadge(ship['status'] as String? ?? ''),
                onTap: () => context.go('/shipments/${ship['id']}'),
              ),
            );
          }),
        ],

        if (order.notes != null && order.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Notes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(order.notes!),
        ],

        // Challan
        if (canGenerateChallan) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _generatingChallan ? null : _generateChallan,
            icon: _generatingChallan
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Generate Challan'),
          ),
        ],
      ],
    );
  }
}
