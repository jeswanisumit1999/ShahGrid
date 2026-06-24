import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/shipments_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/shipment_model.dart';
import '../../../data/repositories/shipments_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/network/dio_client.dart';
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

// ── Permission-based transition logic (mirrors backend) ──────────────────────

List<String> _allowedTransitions(List<String> permissions, String status) {
  final result = <String>[];
  const pending = ['Pending Stock Verification', 'Pending Stock Availability'];
  if (pending.contains(status)) {
    if (permissions.contains('shipments.verify')) result.add('Ready for Dispatch');
    if (permissions.contains('shipments.cancel')) result.add('Cancelled');
  }
  if (status == 'Ready for Dispatch') {
    if (permissions.contains('shipments.deliver')) result.add('Delivered');
    if (permissions.contains('shipments.cancel')) result.add('Cancelled');
  }
  if (status == 'Delivered') {
    if (permissions.contains('shipments.return')) result.add('Returned');
  }
  return result;
}

bool _canDeliverWithAdjustments(List<String> permissions) =>
    permissions.contains('shipments.deliver');

bool _canSplit(List<String> permissions) =>
    permissions.contains('shipments.split');

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
      {List<ItemAdjustment>? adjustments, bool force = false}) async {
    setState(() { _updating = true; _error = null; });
    try {
      await ref.read(shipmentsRepositoryProvider).updateStatus(
            widget.shipment.id,
            newStatus,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            adjustments: adjustments,
            force: force,
          );
      ref.invalidate(shipmentDetailProvider(widget.shipment.id));
      ref.invalidate(shipmentsProvider);
    } catch (e) {
      // Insufficient stock on Ready for Dispatch → show warning and let user force
      if (parseError(e).code == 'INSUFFICIENT_STOCK' &&
          newStatus == 'Ready for Dispatch' &&
          !force) {
        setState(() => _updating = false);
        if (!mounted) return;
        final confirmed = await _showForceDispatchDialog();
        if (confirmed == true && mounted) {
          await _updateStatus(newStatus, adjustments: adjustments, force: true);
        }
        return;
      }
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<bool?> _showForceDispatchDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.tertiary, size: 36),
        title: const Text('Insufficient Stock'),
        content: const Text(
          'One or more items in this shipment exceed available stock.\n\n'
          'Dispatching will cause stock levels to go negative. '
          'Please reconcile inventory as soon as possible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.tertiary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dispatch Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _onTransitionTap(
      String newStatus, List<String> permissions) async {
    if (newStatus == 'Delivered' && _canDeliverWithAdjustments(permissions)) {
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
    final moved = await showDialog<List<Map<String, dynamic>>>(
      context: context,
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
      final msg = friendlyError(e);
      setState(() => _error = msg);
    } finally {
      setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final permissions = user?.permissions ?? [];
    final transitions = _allowedTransitions(permissions, widget.shipment.status);
    final showSplit = widget.shipment.canSplit &&
        _canSplit(permissions) &&
        (widget.shipment.shipmentItems.length > 1 ||
            widget.shipment.shipmentItems.any((i) => i.quantity > 1));
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
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/orders/${widget.shipment.orderId}'),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('View Order'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
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
                        _updating ? null : () => _onTransitionTap(t, permissions),
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
  // itemId → quantity to move
  final Map<String, int> _selected = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  int get _totalOriginal =>
      widget.items.fold(0, (sum, i) => sum + i.quantity);

  int get _totalMoved =>
      _selected.values.fold(0, (sum, q) => sum + q);

  int get _remaining => _totalOriginal - _totalMoved;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selected.isNotEmpty && _remaining > 0;

    return AlertDialog(
      title: const Text('Split Shipment'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select items and quantities to move to a new shipment',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (_selected.isNotEmpty && _remaining <= 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'At least one unit must remain in the original shipment',
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.items.map((item) {
                    final isSelected = _selected.containsKey(item.id);
                    final ctrl = _controllers[item.id];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected[item.id] = item.quantity;
                                final c = TextEditingController(text: '${item.quantity}');
                                _controllers[item.id] = c;
                              } else {
                                _selected.remove(item.id);
                                _controllers[item.id]?.dispose();
                                _controllers.remove(item.id);
                              }
                            });
                          },
                          title: Text(item.productName ?? item.orderItemId),
                          subtitle: Text('Total qty: ${formatNumber(item.quantity)}'
                              '${item.productSku != null ? ' • ${item.productSku}' : ''}'),
                          dense: true,
                        ),
                        if (isSelected && ctrl != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              children: [
                                const SizedBox(width: 40),
                                const Text('Move qty:'),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: (_selected[item.id] ?? 1) > 1
                                      ? () => setState(() {
                                            final v = (_selected[item.id] ?? 1) - 1;
                                            _selected[item.id] = v;
                                            ctrl.text = '$v';
                                          })
                                      : null,
                                ),
                                SizedBox(
                                  width: 60,
                                  child: TextField(
                                    controller: ctrl,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                    ),
                                    onChanged: (val) {
                                      final parsed = int.tryParse(val);
                                      if (parsed != null && parsed >= 1 && parsed <= item.quantity) {
                                        setState(() => _selected[item.id] = parsed);
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: (_selected[item.id] ?? 0) < item.quantity
                                      ? () => setState(() {
                                            final v = (_selected[item.id] ?? 0) + 1;
                                            _selected[item.id] = v;
                                            ctrl.text = '$v';
                                          })
                                      : null,
                                ),
                                Text(' / ${formatNumber(item.quantity)}',
                                    style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Remaining in original: ${formatNumber(_remaining)}  •  Moving: ${formatNumber(_totalMoved)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _remaining > 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
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
          onPressed: canConfirm
              ? () => Navigator.pop(
                    context,
                    _selected.entries
                        .map((e) => {'id': e.key, 'quantity': e.value})
                        .toList(),
                  )
              : null,
          child: const Text('Split'),
        ),
      ],
    );
  }
}
