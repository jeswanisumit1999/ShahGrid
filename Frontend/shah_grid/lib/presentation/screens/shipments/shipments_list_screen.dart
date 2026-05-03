import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/shipments_provider.dart';
import '../../../data/models/shipment_model.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/pagination_list_view.dart';
import '../../widgets/common/status_badge.dart';

class ShipmentsListScreen extends ConsumerWidget {
  const ShipmentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shipmentsProvider);
    final notifier = ref.read(shipmentsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shipments'),
        actions: [
          _StatusFilterButton(onFilter: notifier.filterByStatus),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (result) => PaginationListView(
          items: result.items,
          hasMore: result.hasMore,
          onLoadMore: notifier.loadMore,
          onRefresh: () => notifier.load(refresh: true),
          itemBuilder: (ctx, shipment) => Card(
            child: ListTile(
              title: Text(
                [
                  if (shipment.retailerName != null) shipment.retailerName!,
                  shipment.companyName ?? shipment.companyId,
                ].join(' — '),
              ),
              subtitle: Text(formatDate(shipment.createdAt)),
              trailing: StatusBadge(shipment.status),
              onTap: () => ctx.go('/shipments/${shipment.id}'),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFilterButton extends StatefulWidget {
  const _StatusFilterButton({required this.onFilter});
  final void Function(String?) onFilter;

  @override
  State<_StatusFilterButton> createState() => _StatusFilterButtonState();
}

class _StatusFilterButtonState extends State<_StatusFilterButton> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      icon: Badge(
        isLabelVisible: _selected != null,
        child: const Icon(Icons.filter_list),
      ),
      onSelected: (v) {
        setState(() => _selected = v);
        widget.onFilter(v);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('All statuses')),
        ...ShipmentModel.allStatuses.map((s) => PopupMenuItem(value: s, child: Text(s))),
      ],
    );
  }
}
