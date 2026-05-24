import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../data/repositories/direct_sales_repository.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/format_utils.dart';

class CreateDirectSaleScreen extends ConsumerStatefulWidget {
  const CreateDirectSaleScreen({super.key});

  @override
  ConsumerState<CreateDirectSaleScreen> createState() =>
      _CreateDirectSaleScreenState();
}

class _CreateDirectSaleScreenState
    extends ConsumerState<CreateDirectSaleScreen> {
  final _customerCtrl = TextEditingController();
  final _amountPaidCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_SaleLine> _lines = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _customerCtrl.dispose();
    _amountPaidCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (s, l) => s + l.qty * l.unitPrice);
  double get _amountPaid => double.tryParse(_amountPaidCtrl.text) ?? 0;
  double get _balance => (_total - _amountPaid).clamp(0.0, double.infinity);

  Future<void> _pickProduct() async {
    final products =
        await ref.read(productsRepositoryProvider).list(limit: 100);
    if (!mounted) return;
    final product = await showDialog<ProductModel>(
      context: context,
      builder: (_) => _ProductPickerDialog(
        products: products.items,
        alreadyAdded: _lines.map((l) => l.productId).toSet(),
      ),
    );
    if (product == null || !mounted) return;
    final result = await showDialog<({int qty, double price})>(
      context: context,
      builder: (_) => _LineDetailsDialog(product: product),
    );
    if (result == null) return;
    setState(() {
      _lines.add(_SaleLine(
        productId: product.id,
        productName: product.name,
        qty: result.qty,
        unitPrice: result.price,
      ));
      // Auto-fill amount paid to match new total
      _amountPaidCtrl.text = _total.toStringAsFixed(2);
    });
  }

  Future<void> _submit() async {
    final customer = _customerCtrl.text.trim();
    if (customer.isEmpty) {
      setState(() => _error = 'Enter customer name');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product');
      return;
    }
    final paid = double.tryParse(_amountPaidCtrl.text.trim());
    if (paid == null || paid < 0) {
      setState(() => _error = 'Enter a valid amount paid');
      return;
    }
    if (paid > _total) {
      setState(() => _error = 'Amount paid cannot exceed total (${formatCurrency(_total)})');
      return;
    }
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(directSalesRepositoryProvider).create(
            customerName: customer,
            salesOfficerId: user.id,
            items: _lines
                .map((l) => {
                      'productId': l.productId,
                      'quantity': l.qty,
                      'unitPrice': l.unitPrice,
                    })
                .toList(),
            amountPaid: paid,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Direct sale recorded'),
              backgroundColor: Colors.green),
        );
        context.pop();
      }
    } catch (e) {
      setState(() { _error = friendlyError(e); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Direct Sale')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Customer name
          TextFormField(
            controller: _customerCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Customer Name *',
              hintText: 'Enter customer name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 20),

          // Items section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _pickProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Product'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_lines.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('No products added yet',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline)),
                ),
              ),
            )
          else ...[
            ...List.generate(_lines.length, (i) {
              final line = _lines[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(line.productName),
                  subtitle: Text(
                      '${formatNumber(line.qty)} × ${formatCurrency(line.unitPrice)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatCurrency(line.qty * line.unitPrice),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _lines.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Text(
                  'Total: ${formatCurrency(_total)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Amount Paid
          TextField(
            controller: _amountPaidCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount Paid (₹)',
              prefixText: '₹ ',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.payments_outlined),
              helperText: _lines.isEmpty
                  ? null
                  : _balance > 0
                      ? 'Balance remaining: ${formatCurrency(_balance)}'
                      : 'Fully paid',
              helperStyle: TextStyle(
                color: _lines.isNotEmpty && _balance == 0
                    ? Colors.green
                    : Theme.of(context).colorScheme.secondary,
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),

          const SizedBox(height: 16),

          // Notes
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
          ],

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Record Sale  •  ${formatCurrency(_total)}'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _SaleLine {
  _SaleLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
  });
  final String productId;
  final String productName;
  final int qty;
  final double unitPrice;
}

// ── Product Picker ────────────────────────────────────────────────────────────

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog(
      {required this.products, required this.alreadyAdded});
  final List<ProductModel> products;
  final Set<String> alreadyAdded;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<ProductModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.products
        .where((p) => !widget.alreadyAdded.contains(p.id) && p.stockQuantity > 0)
        .toList();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final available = widget.products
        .where((p) => !widget.alreadyAdded.contains(p.id) && p.stockQuantity > 0)
        .toList();
    setState(() {
      _filtered = q.isEmpty
          ? available
          : available
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
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Text('Select Product',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ]),
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
                ? const Center(child: Text('No products available'))
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final p = _filtered[i];
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text(
                            'Stock: ${formatNumber(p.stockQuantity)}  •  ${formatCurrency(p.price)}'),
                        dense: true,
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ── Line Details Dialog ───────────────────────────────────────────────────────

class _LineDetailsDialog extends StatefulWidget {
  const _LineDetailsDialog({required this.product});
  final ProductModel product;

  @override
  State<_LineDetailsDialog> createState() => _LineDetailsDialogState();
}

class _LineDetailsDialogState extends State<_LineDetailsDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '1');
    _priceCtrl =
        TextEditingController(text: widget.product.price.toStringAsFixed(2));
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
    if (qty > widget.product.stockQuantity) {
      setState(
          () => _error = 'Only ${widget.product.stockQuantity} in stock');
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
      title: Text(widget.product.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available stock: ${formatNumber(widget.product.stockQuantity)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantity',
              border: const OutlineInputBorder(),
              helperText: 'Max: ${widget.product.stockQuantity}',
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
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
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
