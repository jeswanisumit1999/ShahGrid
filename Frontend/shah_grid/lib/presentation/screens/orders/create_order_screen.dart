import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/orders_provider.dart';
import '../../../data/models/retailer_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../data/repositories/orders_repository.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/format_utils.dart';

// Loaded once per screen instance — companies for override selector
final _orderCompaniesProvider =
    FutureProvider.autoDispose<List<CompanySummary>>(
        (ref) => ref.read(productsRepositoryProvider).listCompanies());

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  RetailerModel? _selectedRetailer;
  String? _overrideCompanyId;
  bool _isDirectSale = false;
  final List<_OrderLine> _lines = [];
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (s, l) => s + l.qty * l.unitPrice);

  Future<void> _submit() async {
    if (_selectedRetailer == null || _lines.isEmpty) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() { _submitting = true; _error = null; });
    try {
      final order = await ref.read(ordersRepositoryProvider).create(
        retailerId: _selectedRetailer!.id,
        salesOfficerId: user.id,
        items: _lines.map((l) => {
          'productId': l.product.id,
          'quantity': l.qty,
          'unitPrice': l.unitPrice,
        }).toList(),
        isDirectSale: _isDirectSale,
        overrideCompanyId: _overrideCompanyId,
        notes: _notesCtrl.text,
      );
      ref.invalidate(ordersProvider);
      if (mounted) context.go('/orders/${order.id}');
    } catch (e) {
      final msg = e is AppException ? e.message : e.toString();
      setState(() { _error = msg; _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final canOverride = user?.hasRole('Admin') == true ||
        user?.hasRole('Supply Chain') == true;

    return Scaffold(
      appBar: AppBar(title: const Text('New Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Retailer picker
          Text('Retailer', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _RetailerPickerTile(
            selected: _selectedRetailer,
            onSelected: (r) => setState(() => _selectedRetailer = r),
          ),
          const SizedBox(height: 12),

          // Direct Sale toggle
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Direct Sale'),
              subtitle: const Text('Stock deducted immediately — no shipment created'),
              value: _isDirectSale,
              onChanged: (v) => setState(() => _isDirectSale = v),
            ),
          ),
          const SizedBox(height: 20),

          // Company override (Admin / Supply Chain only)
          if (canOverride) ...[
            Text('Override Fulfilling Company',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Force all shipments to come from one company '
              'regardless of each product\'s assigned company.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ref.watch(_orderCompaniesProvider).when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (companies) => DropdownButtonFormField<String>(
                key: ValueKey('override-${companies.length}-$_overrideCompanyId'),
                decoration: const InputDecoration(
                  labelText: 'Company (optional)',
                  border: OutlineInputBorder(),
                ),
                initialValue: companies.any((c) => c.id == _overrideCompanyId)
                    ? _overrideCompanyId
                    : null,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Per product (default) —')),
                  ...companies.map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => setState(() => _overrideCompanyId = v),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Items
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Items', style: Theme.of(context).textTheme.titleSmall),
            TextButton.icon(
              onPressed: _pickProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            ),
          ]),
          ..._lines.asMap().entries.map((e) => _OrderLineTile(
                line: e.value,
                canEditPrice: user?.hasRole('Admin') == true,
                onRemove: () => setState(() => _lines.removeAt(e.key)),
                onQtyChanged: (q) => setState(() => _lines[e.key] = e.value.withQty(q)),
                onPriceChanged: (p) => setState(() => _lines[e.key] = e.value.withUnitPrice(p)),
              )),

          if (_lines.isNotEmpty) ...[
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total', style: Theme.of(context).textTheme.titleMedium),
              Text(formatCurrency(_total),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
          ],

          const SizedBox(height: 16),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],

          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_submitting || _selectedRetailer == null || _lines.isEmpty)
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Place Order'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProduct() async {
    try {
      final products = await ref.read(productsRepositoryProvider).list(limit: 100);
      if (!mounted) return;
      final product = await showDialog<ProductModel>(
        context: context,
        builder: (_) => _ProductPickerDialog(products: products.items),
      );
      if (product != null) {
        setState(() => _lines.add(_OrderLine(product: product, qty: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load products: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _RetailerPickerTile extends ConsumerWidget {
  const _RetailerPickerTile({required this.selected, required this.onSelected});
  final RetailerModel? selected;
  final void Function(RetailerModel) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.storefront_outlined),
        title: Text(selected?.name ?? 'Select a retailer'),
        subtitle: selected != null ? Text('Available: ${formatCurrency(selected!.availableCredit)}') : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final retailers = await ref.read(retailersRepositoryProvider).list(limit: 50);
          if (!context.mounted) return;
          final pick = await showDialog<RetailerModel>(
            context: context,
            builder: (dialogCtx) => SimpleDialog(
              title: const Text('Select Retailer'),
              children: retailers.items.map((r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogCtx, r),
                child: ListTile(
                  title: Text(r.name),
                  subtitle: Text('Credit: ${formatCurrency(r.availableCredit)}'),
                  dense: true,
                ),
              )).toList(),
            ),
          );
          if (pick != null) onSelected(pick);
        },
      ),
    );
  }
}

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
                  Text('Select Product',
                      style: Theme.of(context).textTheme.titleLarge),
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
                              'SKU: ${p.sku}  •  Stock: ${formatNumber(p.stockQuantity)}  •  ${formatCurrency(p.price)}'),
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

class _OrderLine {
  _OrderLine({required this.product, required this.qty, double? unitPrice})
      : unitPrice = unitPrice ?? product.price;
  final ProductModel product;
  final int qty;
  final double unitPrice;
  _OrderLine withQty(int q) => _OrderLine(product: product, qty: q, unitPrice: unitPrice);
  _OrderLine withUnitPrice(double p) => _OrderLine(product: product, qty: qty, unitPrice: p);
}

class _OrderLineTile extends StatelessWidget {
  const _OrderLineTile({
    required this.line,
    required this.onRemove,
    required this.onQtyChanged,
    required this.canEditPrice,
    required this.onPriceChanged,
  });
  final _OrderLine line;
  final VoidCallback onRemove;
  final void Function(int) onQtyChanged;
  final bool canEditPrice;
  final void Function(double) onPriceChanged;

  void _showPriceDialog(BuildContext context) {
    final ctrl = TextEditingController(text: line.unitPrice.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Set price — ${line.product.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Unit price (₹)', prefixText: '₹ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final p = double.tryParse(ctrl.text);
              if (p != null && p > 0) {
                onPriceChanged(p);
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final priceOverridden = line.unitPrice != line.product.price;
    return ListTile(
      title: Text(line.product.name),
      subtitle: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          formatCurrency(line.unitPrice),
          style: priceOverridden
              ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)
              : null,
        ),
        if (priceOverridden) ...[
          const SizedBox(width: 4),
          Text(
            formatCurrency(line.product.price),
            style: TextStyle(
              fontSize: 11,
              decoration: TextDecoration.lineThrough,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
        if (canEditPrice) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showPriceDialog(context),
            child: Icon(Icons.edit, size: 14, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.remove), onPressed: line.qty > 1 ? () => onQtyChanged(line.qty - 1) : null),
        Text(formatNumber(line.qty)),
        IconButton(icon: const Icon(Icons.add), onPressed: () => onQtyChanged(line.qty + 1)),
        IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
      ]),
    );
  }
}
