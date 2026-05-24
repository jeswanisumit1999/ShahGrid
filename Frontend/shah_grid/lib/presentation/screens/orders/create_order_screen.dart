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
import '../../../data/repositories/settings_repository.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/format_utils.dart';

final _orderCompaniesProvider =
    FutureProvider.autoDispose<List<CompanySummary>>(
        (ref) => ref.read(productsRepositoryProvider).listCompanies());

final _creditOverrideEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  final settings = await ref.read(settingsRepositoryProvider).list();
  return settings.any((s) => s.key == 'allow_credit_override' && s.boolValue);
});

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  RetailerModel? _selectedRetailer;
  String? _overrideCompanyId;
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
        overrideCompanyId: _overrideCompanyId,
        notes: _notesCtrl.text,
      );
      ref.invalidate(ordersProvider);
      if (mounted) context.go('/orders/${order.id}');
    } catch (e) {
      final msg = friendlyError(e);
      setState(() { _error = msg; _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final canOverride = user?.hasPermission('orders', 'manage') == true ||
        user?.hasPermission('shipments', 'manage') == true;

    final canEditPrice = user?.hasPermission('orders', 'create') == true ||
        user?.hasPermission('orders', 'manage') == true;

    final creditOverrideEnabled =
        ref.watch(_creditOverrideEnabledProvider).valueOrNull ?? false;
    final creditExceeded = _selectedRetailer != null &&
        _lines.isNotEmpty &&
        _total > _selectedRetailer!.availableCredit;

    return Scaffold(
      appBar: AppBar(title: const Text('New Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Retailer ──────────────────────────────────────────────────────
          Text('Retailer', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _RetailerPickerTile(
            selected: _selectedRetailer,
            onSelected: (r) => setState(() => _selectedRetailer = r),
          ),
          const SizedBox(height: 20),

          // ── Items ─────────────────────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Items', style: Theme.of(context).textTheme.titleSmall),
            if (_lines.isNotEmpty)
              TextButton.icon(
                onPressed: _pickProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
          ]),
          const SizedBox(height: 8),

          if (_lines.isEmpty)
            // Tappable empty state — impossible to miss
            InkWell(
              onTap: _pickProduct,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline,
                        size: 36,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('Tap to add products',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
          else ...[
            ..._lines.asMap().entries.map((e) => _OrderLineTile(
                  line: e.value,
                  canEditPrice: canEditPrice,
                  onRemove: () => setState(() => _lines.removeAt(e.key)),
                  onQtyChanged: (q) => setState(() => _lines[e.key] = e.value.withQty(q)),
                  onPriceChanged: (p) => setState(() => _lines[e.key] = e.value.withUnitPrice(p)),
                )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total', style: Theme.of(context).textTheme.titleMedium),
              Text(formatCurrency(_total),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
            if (creditExceeded && creditOverrideEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Order total ${formatCurrency(_total)} exceeds '
                        '${_selectedRetailer!.name}\'s available credit '
                        '(${formatCurrency(_selectedRetailer!.availableCredit)}). '
                        'Credit override is enabled — order will still be placed.',
                        style: TextStyle(
                            color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),

          // ── Notes ─────────────────────────────────────────────────────────
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),

          // ── Override company (collapsed — rarely used) ─────────────────────
          if (canOverride)
            ref.watch(_orderCompaniesProvider).maybeWhen(
              data: (companies) => Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Override Fulfilling Company',
                      style: Theme.of(context).textTheme.bodyMedium),
                  subtitle: _overrideCompanyId != null
                      ? Text(
                          companies.firstWhere((c) => c.id == _overrideCompanyId).name,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        )
                      : const Text('Per product (default)'),
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('override-${companies.length}-$_overrideCompanyId'),
                      decoration: const InputDecoration(
                        labelText: 'Company',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      initialValue: companies.any((c) => c.id == _overrideCompanyId)
                          ? _overrideCompanyId
                          : null,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— Per product (default) —')),
                        ...companies.map(
                            (c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() => _overrideCompanyId = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],

          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_submitting || _selectedRetailer == null || _lines.isEmpty)
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_lines.isEmpty
                    ? 'Place Order'
                    : 'Place Order  •  ${formatCurrency(_total)}'),
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

class _OrderLineTile extends StatefulWidget {
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

  @override
  State<_OrderLineTile> createState() => _OrderLineTileState();
}

class _OrderLineTileState extends State<_OrderLineTile> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.line.qty.toString());
    _priceCtrl = TextEditingController(text: widget.line.unitPrice.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(_OrderLineTile old) {
    super.didUpdateWidget(old);
    if (old.line.qty != widget.line.qty &&
        int.tryParse(_qtyCtrl.text) != widget.line.qty) {
      _qtyCtrl.text = widget.line.qty.toString();
    }
    if (old.line.unitPrice != widget.line.unitPrice &&
        double.tryParse(_priceCtrl.text) != widget.line.unitPrice) {
      _priceCtrl.text = widget.line.unitPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final priceOverridden = widget.line.unitPrice != widget.line.product.price;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.line.product.name,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // ── Quantity ──────────────────────────────────────
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final q = int.tryParse(v);
                            if (q != null && q > 0) widget.onQtyChanged(q);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Price ─────────────────────────────────────────
                      if (widget.canEditPrice)
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            style: priceOverridden
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600)
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Price (₹)',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              suffixIcon: priceOverridden
                                  ? Tooltip(
                                      message:
                                          'Original: ${formatCurrency(widget.line.product.price)}',
                                      child: Icon(Icons.info_outline,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.primary),
                                    )
                                  : null,
                            ),
                            onChanged: (v) {
                              final p = double.tryParse(v);
                              if (p != null && p > 0) widget.onPriceChanged(p);
                            },
                          ),
                        )
                      else
                        Text(formatCurrency(widget.line.unitPrice),
                            style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onRemove,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
