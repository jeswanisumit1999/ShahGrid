import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/shipments_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/shipment_model.dart';
import '../../../data/repositories/shipments_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/errors/app_exception.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/status_badge.dart';

class ShipmentDetailScreen extends ConsumerWidget {
  const ShipmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(shipmentDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Shipment')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e),
        data: (shipment) => _ShipmentBody(shipment: shipment),
      ),
    );
  }
}

// ── Transition table mirrored from backend ────────────────────────────────────

const _transitions = {
  'Admin': {
    'Pending Stock Verification': ['Ready for Dispatch', 'Cancelled'],
    'Pending Stock Availability': ['Ready for Dispatch', 'Cancelled'],
    'Ready for Dispatch': ['Delivered', 'Cancelled'],
    'Delivered': ['Returned'],
  },
  'Supply Chain': {
    'Pending Stock Verification': ['Ready for Dispatch', 'Cancelled'],
    'Pending Stock Availability': ['Ready for Dispatch', 'Cancelled'],
    'Ready for Dispatch': ['Cancelled'],
  },
  'Godown Manager': {
    'Pending Stock Verification': ['Ready for Dispatch'],
    'Pending Stock Availability': ['Ready for Dispatch'],
    'Ready for Dispatch': ['Delivered'],
  },
};

List<String> _allowedTransitions(List<String> roles, String status) {
  final result = <String>{};
  for (final role in roles) {
    final map = _transitions[role];
    if (map == null) continue;
    result.addAll(map[status] ?? []);
  }
  return result.toList();
}

bool _canDeliverWithAdjustments(List<String> roles) =>
    roles.contains('Admin') || roles.contains('Godown Manager');

bool _canSplit(List<String> roles) =>
    roles.contains('Admin') || roles.contains('Supply Chain');

// ── Body ──────────────────────────────────────────────────────────────────────

class _ShipmentBody extends ConsumerStatefulWidget {
  const _ShipmentBody({required this.shipment});
  final ShipmentModel shipment;

  @override
  ConsumerState<_ShipmentBody> createState() => _ShipmentBodyState();
}

class _ShipmentBodyState extends ConsumerState<_ShipmentBody> {
  bool _updating = false;
  String? _error;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notesCtrl.text = widget.shipment.notes ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String newStatus,
      {List<ItemAdjustment>? adjustments}) async {
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await ref.read(shipmentsRepositoryProvider).updateStatus(
            widget.shipment.id,
            newStatus,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            adjustments: adjustments,
          );
      ref.invalidate(shipmentDetailProvider(widget.shipment.id));
      ref.invalidate(shipmentsProvider);
    } catch (e) {
      final msg = e is AppException ? e.message : e.toString();
      setState(() => _error = msg);
    } finally {
      setState(() => _updating = false);
    }
  }

  Future<void> _onTransitionTap(
      String newStatus, List<String> roles) async {
    if (newStatus == 'Delivered' && _canDeliverWithAdjustments(roles)) {
      await _showDeliverySheet(newStatus);
    } else {
      await _confirmTransition(newStatus);
    }
  }

  Future<void> _confirmTransition(String newStatus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move to "$newStatus"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (newStatus == 'Ready for Dispatch')
              const Text('Stock will be deducted from inventory immediately.'),
            if (newStatus == 'Cancelled' &&
                widget.shipment.status == 'Ready for Dispatch')
              const Text('Stock reserved for this shipment will be restored.'),
            if (newStatus == 'Returned')
              const Text('All delivered stock will be returned to inventory and the order total will be reduced.'),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: newStatus == 'Cancelled' || newStatus == 'Returned'
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _updateStatus(newStatus);
  }

  Future<void> _showDeliverySheet(String newStatus) async {
    final adjustments = await showDialog<List<ItemAdjustment>>(
      context: context,
      builder: (dialogCtx) =>
          _DeliveryAdjustmentDialog(items: widget.shipment.shipmentItems),
    );
    if (adjustments != null && mounted) {
      await _updateStatus(newStatus, adjustments: adjustments);
    }
  }

  Future<void> _showSplitSheet() async {
    final moved = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _SplitShipmentSheet(items: widget.shipment.shipmentItems),
    );
    if (moved == null || moved.isEmpty || !mounted) return;

    setState(() { _updating = true; _error = null; });
    try {
      await ref
          .read(shipmentsRepositoryProvider)
          .splitShipment(widget.shipment.id, moved);
      ref.invalidate(shipmentDetailProvider(widget.shipment.id));
      ref.invalidate(shipmentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Shipment split — new shipment created'),
              backgroundColor: Colors.green),
        );
        // Navigate to shipments list so user can see both
        context.go('/shipments');
      }
    } catch (e) {
      final msg = e is AppException ? e.message : e.toString();
      setState(() => _error = msg);
    } finally {
      setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final roles = user?.roles ?? [];
    final transitions = _allowedTransitions(roles, widget.shipment.status);
    final showSplit =
        widget.shipment.canSplit && _canSplit(roles) && widget.shipment.shipmentItems.length > 1;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header card ──────────────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.shipment.companyName ?? widget.shipment.companyId,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (widget.shipment.retailerName != null)
                      Text('Retailer: ${widget.shipment.retailerName}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                StatusBadge(widget.shipment.status),
              ]),
              const Divider(height: 20),
              _TimestampRow('Created', widget.shipment.createdAt),
              if (widget.shipment.readyAt != null)
                _TimestampRow('Ready for Dispatch', widget.shipment.readyAt),
              if (widget.shipment.deliveredAt != null)
                _TimestampRow('Delivered', widget.shipment.deliveredAt),
              if (widget.shipment.returnedAt != null)
                _TimestampRow('Returned', widget.shipment.returnedAt),
              if (widget.shipment.notes != null && widget.shipment.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Notes: ',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  Expanded(child: Text(widget.shipment.notes!)),
                ]),
              ],
            ]),
          ),
        ),

        // ── Items ─────────────────────────────────────────────────────────────
        const SizedBox(height: 16),
        Text('Items (${widget.shipment.shipmentItems.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...widget.shipment.shipmentItems.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.productName ?? 'Product ${item.orderItemId.substring(0, 8)}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (item.productSku != null)
                            Text('SKU: ${item.productSku}',
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Qty: ${formatNumber(item.quantity)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (item.unitPrice != null)
                          Text(formatCurrency(item.unitPrice! * item.quantity),
                              style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        StatusBadge(item.status, small: true),
                      ],
                    ),
                  ],
                ),
              ),
            )),

        // ── Error ─────────────────────────────────────────────────────────────
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],

        // ── Actions ───────────────────────────────────────────────────────────
        const SizedBox(height: 24),
        Text('Actions', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (transitions.isNotEmpty || showSplit)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...transitions.map((t) => FilledButton.icon(
                    icon: _updating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_transitionIcon(t)),
                    label: Text(t),
                    style: (t == 'Cancelled' || t == 'Returned')
                        ? FilledButton.styleFrom(backgroundColor: scheme.error)
                        : null,
                    onPressed:
                        _updating ? null : () => _onTransitionTap(t, roles),
                  )),
              if (showSplit)
                OutlinedButton.icon(
                  icon: const Icon(Icons.call_split),
                  label: const Text('Split Shipment'),
                  onPressed: _updating ? null : _showSplitSheet,
                ),
            ],
          )
        else if (!widget.shipment.isTerminal)
          Text(
            widget.shipment.status == 'Ready for Dispatch'
                ? 'No actions available for your role.'
                : 'Waiting for stock verification before this shipment can be dispatched.',
            style: TextStyle(
                color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          )
        else
          Text(
            'This shipment is ${widget.shipment.status.toLowerCase()} — no further actions.',
            style: TextStyle(
                color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),

        const SizedBox(height: 40),
      ],
    );
  }

  IconData _transitionIcon(String status) => switch (status) {
        'Ready for Dispatch' => Icons.check_circle_outline,
        'Delivered' => Icons.local_shipping_outlined,
        'Cancelled' => Icons.cancel_outlined,
        'Returned' => Icons.keyboard_return,
        _ => Icons.arrow_forward,
      };
}

class _TimestampRow extends StatelessWidget {
  const _TimestampRow(this.label, this.iso);
  final String label;
  final String? iso;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(formatDateTime(iso)),
        ]),
      );
}

// ── Delivery adjustment dialog ────────────────────────────────────────────────

class _DeliveryAdjustmentDialog extends StatefulWidget {
  const _DeliveryAdjustmentDialog({required this.items});
  final List<ShipmentItemModel> items;

  @override
  State<_DeliveryAdjustmentDialog> createState() => _DeliveryAdjustmentDialogState();
}

class _DeliveryAdjustmentDialogState extends State<_DeliveryAdjustmentDialog> {
  late final List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = widget.items
        .map((i) => TextEditingController(text: '${i.quantity}'))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  List<ItemAdjustment>? _buildAdjustments() {
    final result = <ItemAdjustment>[];
    for (int i = 0; i < widget.items.length; i++) {
      final actual = int.tryParse(_ctrls[i].text);
      if (actual == null || actual < 0 || actual > widget.items[i].quantity) {
        return null;
      }
      result.add(ItemAdjustment(
        shipmentItemId: widget.items[i].id,
        actualQuantity: actual,
      ));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Delivery'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adjust quantities if the retailer accepted less than planned.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (_, i) {
                  final item = widget.items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName ?? item.orderItemId,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              'Planned: ${formatNumber(item.quantity)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _ctrls[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: 'Actual',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixText: '/${item.quantity}',
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final adj = _buildAdjustments();
            if (adj == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invalid quantities — each must be 0 to planned qty'),
                ),
              );
              return;
            }
            Navigator.pop(context, adj);
          },
          child: const Text('Deliver'),
        ),
      ],
    );
  }
}

// ── Split shipment sheet ──────────────────────────────────────────────────────

class _SplitShipmentSheet extends StatefulWidget {
  const _SplitShipmentSheet({required this.items});
  final List<ShipmentItemModel> items;

  @override
  State<_SplitShipmentSheet> createState() => _SplitShipmentSheetState();
}

class _SplitShipmentSheetState extends State<_SplitShipmentSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final remaining = widget.items.length - _selected.length;
    final canConfirm = _selected.isNotEmpty && remaining >= 1;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Split Shipment',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text('Select items to move to a new shipment',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                FilledButton(
                  onPressed: canConfirm
                      ? () => Navigator.pop(context, _selected.toList())
                      : null,
                  child: const Text('Split'),
                ),
              ]),
            ),
            if (!canConfirm && _selected.length == widget.items.length)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'At least one item must remain in the original shipment',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12),
                ),
              ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: widget.items.length,
                itemBuilder: (_, i) {
                  final item = widget.items[i];
                  return CheckboxListTile(
                    value: _selected.contains(item.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(item.id);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
                    title: Text(item.productName ?? item.orderItemId),
                    subtitle: Text('Qty: ${formatNumber(item.quantity)}'
                        '${item.productSku != null ? ' • SKU: ${item.productSku}' : ''}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
