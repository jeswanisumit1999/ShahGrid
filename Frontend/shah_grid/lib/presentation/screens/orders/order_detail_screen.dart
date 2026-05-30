import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/repositories/orders_repository.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/pdf_preview.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/create_order_args.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/status_badge.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _reorder(BuildContext context, WidgetRef ref, OrderModel order) async {
    try {
      final retailer = await ref.read(retailersRepositoryProvider).getById(order.retailerId);
      final items = order.orderItems
          .where((i) => i.product != null)
          .map((i) => ReorderItem(product: i.product!, qty: i.quantity, unitPrice: i.unitPrice))
          .toList();
      if (context.mounted) {
        context.go('/orders/new', extra: CreateOrderArgs(retailer: retailer, reorderItems: items));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(id));
    final user = ref.watch(authStateProvider).valueOrNull;
    final canCreate = user?.hasPermission('orders', 'create') ?? false;
    final order = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Detail'),
        actions: [
          if (order != null) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy order ID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: order.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Order ID copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (canCreate)
              IconButton(
                icon: const Icon(Icons.replay_outlined),
                tooltip: 'Reorder',
                onPressed: () => _reorder(context, ref, order),
              ),
          ],
        ],
      ),
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

  Future<void> _editNotes() async {
    final ctrl = TextEditingController(text: widget.order.notes ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Notes'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Add a note…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    try {
      await ref.read(ordersRepositoryProvider).updateNotes(
            widget.order.id,
            result.isEmpty ? null : result,
          );
      ref.invalidate(orderDetailProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateChallan() async {
    setState(() => _generatingChallan = true);
    try {
      final bytes = await ref.read(ordersRepositoryProvider).downloadChallan(widget.order.id);
      final shortId = widget.order.id.split('-').first.toUpperCase();
      final filename = 'challan_$shortId.pdf';
      final handle = createPdfPreview(bytes);
      if (!mounted) { handle.dispose(); return; }
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChallanPreviewDialog(handle: handle, filename: filename),
      );
      handle.dispose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingChallan = false);
    }
  }

  Future<void> _addProduct() async {
    try {
      final products = await ref.read(productsRepositoryProvider).list(limit: 100);
      if (!mounted) return;
      final product = await showDialog<ProductModel>(
        context: context,
        builder: (_) => _ProductPickerDialog(products: products.items),
      );
      if (product == null || !mounted) return;
      final result = await showDialog<({int qty, double price})>(
        context: context,
        builder: (_) => _AddItemDetailsDialog(product: product),
      );
      if (result == null || !mounted) return;
      await ref.read(ordersRepositoryProvider).addItem(
            orderId: widget.order.id,
            productId: product.id,
            quantity: result.qty,
            unitPrice: result.price,
          );
      ref.invalidate(orderDetailProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editItem(OrderItemModel item) async {
    final result = await showDialog<({int qty, double price})>(
      context: context,
      builder: (_) => _EditItemDialog(item: item),
    );
    if (result == null) return;
    if (result.qty == item.quantity && result.price == item.unitPrice) return;

    try {
      await ref.read(ordersRepositoryProvider).updateItemQuantity(
            orderId: widget.order.id,
            itemId: item.id,
            quantity: result.qty,
            unitPrice: result.price != item.unitPrice ? result.price : null,
          );
      ref.invalidate(orderDetailProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final canGenerateChallan = user?.hasPermission('challans', 'generate') ?? false;
    final canManage = user?.hasPermission('orders', 'manage') ?? false;
    final canEditItems = !widget.order.isDirectSale && canManage;
    final order = widget.order;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(orderDetailProvider(widget.order.id)),
      child: ListView(
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Items', style: Theme.of(context).textTheme.titleMedium),
            if (canEditItems)
              TextButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Product'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...order.orderItems.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(item.product?.name ?? item.productId),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${formatNumber(item.quantity)} × ${formatCurrency(item.unitPrice)}'),
                    if ((item.deliveredQuantity ?? 0) > 0)
                      Text(
                        'Delivered: ${formatNumber(item.deliveredQuantity!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatCurrency(item.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (canEditItems) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'Edit item',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _editItem(item),
                      ),
                    ],
                  ],
                ),
                isThreeLine: (item.deliveredQuantity ?? 0) > 0,
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

        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Notes', style: Theme.of(context).textTheme.titleMedium),
            if (canManage)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit notes',
                visualDensity: VisualDensity.compact,
                onPressed: _editNotes,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          order.notes != null && order.notes!.isNotEmpty
              ? order.notes!
              : 'No notes',
          style: order.notes == null || order.notes!.isEmpty
              ? Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  )
              : null,
        ),

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
    ), // ListView
    ); // RefreshIndicator
  }
}

// ── Edit Item Dialog ──────────────────────────────────────────────────────────

class _EditItemDialog extends StatefulWidget {
  const _EditItemDialog({required this.item});
  final OrderItemModel item;

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.item.quantity.toString());
    _priceCtrl = TextEditingController(text: widget.item.unitPrice.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = int.tryParse(_qtyCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    final delivered = widget.item.deliveredQuantity ?? 0;
    if (qty == null || qty < 1) {
      setState(() => _error = 'Enter a valid quantity');
      return;
    }
    if (qty < delivered) {
      setState(() => _error = 'Cannot go below delivered quantity ($delivered)');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price');
      return;
    }
    Navigator.pop(context, (qty: qty, price: price));
  }

  @override
  Widget build(BuildContext context) {
    final delivered = widget.item.deliveredQuantity ?? 0;

    return AlertDialog(
      title: Text(widget.item.product?.name ?? 'Edit Item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current: ${formatNumber(widget.item.quantity)} × ${formatCurrency(widget.item.unitPrice)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (delivered > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Already delivered: ${formatNumber(delivered)} — minimum qty is $delivered',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantity',
              border: const OutlineInputBorder(),
              helperText: delivered > 0 ? 'Minimum: $delivered' : null,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Unit Price (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Update')),
      ],
    );
  }
}

// ── Product Picker Dialog ─────────────────────────────────────────────────────

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});
  final List<ProductModel> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<ProductModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.products
          : widget.products
              .where((p) =>
                  p.name.toLowerCase().contains(q) ||
                  (p.sku?.toLowerCase().contains(q) ?? false))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('Select Product', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by name or SKU…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No products found'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final p = _filtered[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                              'SKU: ${p.sku ?? '—'}  •  Stock: ${formatNumber(p.stockQuantity)}  •  ${formatCurrency(p.price)}'),
                          dense: true,
                          onTap: () => Navigator.pop(context, p),
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

// ── Add Item Details Dialog ───────────────────────────────────────────────────

class _AddItemDetailsDialog extends StatefulWidget {
  const _AddItemDetailsDialog({required this.product});
  final ProductModel product;

  @override
  State<_AddItemDetailsDialog> createState() => _AddItemDetailsDialogState();
}

class _AddItemDetailsDialogState extends State<_AddItemDetailsDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '1');
    _priceCtrl = TextEditingController(text: widget.product.price.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = int.tryParse(_qtyCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    if (qty == null || qty < 1) {
      setState(() => _error = 'Enter a valid quantity');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price');
      return;
    }
    Navigator.pop(context, (qty: qty, price: price));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add ${widget.product.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stock: ${formatNumber(widget.product.stockQuantity)}  •  Default price: ${formatCurrency(widget.product.price)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Unit Price (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

// ── Challan Preview ───────────────────────────────────────────────────────────

class _ChallanPreviewDialog extends StatelessWidget {
  const _ChallanPreviewDialog({required this.handle, required this.filename});
  final PdfPreviewHandle handle;
  final String filename;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Column(
        children: [
          AppBar(
            automaticallyImplyLeading: false,
            title: Text(filename),
            actions: [
              TextButton.icon(
                onPressed: () => handle.download(filename),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
              ),
              TextButton.icon(
                onPressed: handle.print,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: HtmlElementView(viewType: handle.viewType),
          ),
        ],
      ),
    );
  }
}
