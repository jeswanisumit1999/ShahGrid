import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/products_repository.dart';
import '../../../core/network/dio_client.dart';
import 'products_list_screen.dart';

final _companiesProvider = StateNotifierProvider.autoDispose<_ListNotifier<CompanySummary>,
    AsyncValue<List<CompanySummary>>>((ref) {
  return _ListNotifier(() => ref.read(productsRepositoryProvider).listCompanies());
});

final _categoriesProvider = StateNotifierProvider.autoDispose<_ListNotifier<CategorySummary>,
    AsyncValue<List<CategorySummary>>>((ref) {
  return _ListNotifier(() => ref.read(productsRepositoryProvider).listCategories());
});

final _brandsProvider = StateNotifierProvider.autoDispose<_ListNotifier<String>,
    AsyncValue<List<String>>>((ref) {
  return _ListNotifier(() => ref.read(productsRepositoryProvider).listBrands());
});

/// Generic notifier for a simple refreshable list.
class _ListNotifier<T> extends StateNotifier<AsyncValue<List<T>>> {
  _ListNotifier(this._fetch) : super(const AsyncValue.loading()) {
    load();
  }
  final Future<List<T>> Function() _fetch;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _fetch());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

class CreateProductScreen extends ConsumerStatefulWidget {
  const CreateProductScreen({super.key});

  @override
  ConsumerState<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends ConsumerState<CreateProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  final _thresholdCtrl = TextEditingController();
  String _brand = '';
  String? _selectedCompanyId;
  String? _selectedCategoryId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _error = null; });
    try {
      final sku = _skuCtrl.text.trim();
      final brand = _brand.trim();
      final threshold = int.tryParse(_thresholdCtrl.text.trim());
      await ref.read(productsRepositoryProvider).create({
        'name': _nameCtrl.text.trim(),
        if (sku.isNotEmpty) 'sku': sku,
        if (brand.isNotEmpty) 'brand': brand,
        'price': double.parse(_priceCtrl.text),
        'stockQuantity': int.parse(_stockCtrl.text),
        'companyId': _selectedCompanyId!,
        if (_selectedCategoryId != null) 'categoryId': _selectedCategoryId,
        if (threshold != null) 'lowStockThreshold': threshold,
      });
      if (mounted) {
        ref.invalidate(productsListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product created'), backgroundColor: Colors.green),
        );
        context.go('/products');
      }
    } catch (e) {
      setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  Future<String?> _showAddCompanyDialog() async {
    final nameCtrl = TextEditingController();
    final gstinCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String? createdId;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Company'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Company Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile Number (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gstinCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
                decoration: const InputDecoration(
                  labelText: 'GSTIN (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                String? ne(String s) => s.isEmpty ? null : s;
                final c = await ref.read(productsRepositoryProvider).createCompany(
                      name,
                      gstin: ne(gstinCtrl.text.trim().toUpperCase()),
                      phone: ne(phoneCtrl.text.trim()),
                      address: ne(addressCtrl.text.trim()),
                    );
                createdId = c.id;
                ref.read(_companiesProvider.notifier).load();
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                final msg = friendlyError(e);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    gstinCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    return createdId;
  }

  /// Shows a dialog to create a new company/category, refreshes the list,
  /// and returns the new item's id so the dropdown can auto-select it.
  Future<String?> _showAddDialog({
    required String title,
    required Future<String> Function(String name) onCreate,
    required VoidCallback onRefresh,
  }) async {
    final ctrl = TextEditingController();
    String? createdId;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Enter name'),
          onSubmitted: (_) => Navigator.pop(ctx),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              try {
                createdId = await onCreate(name);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                final msg = friendlyError(e);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (createdId != null) onRefresh();
    return createdId;
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(_companiesProvider);
    final categories = ref.watch(_categoriesProvider);
    final brandsAsync = ref.watch(_brandsProvider);
    final brands = brandsAsync.valueOrNull ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Add Product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Product Name *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skuCtrl,
              decoration: const InputDecoration(
                labelText: 'SKU (optional)',
                helperText: 'Unique stock-keeping unit identifier',
              ),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.toLowerCase();
                if (query.isEmpty) return const Iterable.empty();
                return brands.where((b) => b.toLowerCase().contains(query));
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (v) => _brand = v,
                  decoration: const InputDecoration(labelText: 'Brand (optional)'),
                );
              },
              onSelected: (value) => setState(() => _brand = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Price (₹) *', prefixText: '₹ '),
              keyboardType: TextInputType.number,
              validator: (v) {
                if ((double.tryParse(v ?? '') ?? 0) <= 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _stockCtrl,
              decoration: const InputDecoration(labelText: 'Initial Stock Quantity'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if ((int.tryParse(v ?? '') ?? -1) < 0) return 'Enter a non-negative number';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _thresholdCtrl,
              decoration: const InputDecoration(
                labelText: 'Low Stock Alert Threshold (optional)',
                helperText: 'Show alert on dashboard when stock falls to or below this number',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n < 0) return 'Enter a non-negative whole number';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Company row ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: companies.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Failed to load companies',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    data: (list) => DropdownButtonFormField<String>(
                      key: ValueKey('co-${list.length}-$_selectedCompanyId'),
                      decoration: const InputDecoration(labelText: 'Company *'),
                      initialValue: list.any((c) => c.id == _selectedCompanyId)
                          ? _selectedCompanyId
                          : null,
                      items: list
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCompanyId = v),
                      validator: (v) => v == null ? 'Select a company' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // "+ Add" button — visible while the companies list is loaded
                if (companies.hasValue)
                  Tooltip(
                    message: 'Add new company',
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.add_business_outlined),
                      onPressed: () async {
                        final newId = await _showAddCompanyDialog();
                        if (newId != null) setState(() => _selectedCompanyId = newId);
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Category row ─────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: categories.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (list) => DropdownButtonFormField<String>(
                      key: ValueKey('cat-${list.length}-$_selectedCategoryId'),
                      decoration: const InputDecoration(labelText: 'Category (optional)'),
                      initialValue: list.any((c) => c.id == _selectedCategoryId)
                          ? _selectedCategoryId
                          : null,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('— None —')),
                        ...list.map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (categories.hasValue)
                  Tooltip(
                    message: 'Add new category',
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.add_outlined),
                      onPressed: () async {
                        final newId = await _showAddDialog(
                          title: 'New Category',
                          onCreate: (name) async {
                            final c = await ref
                                .read(productsRepositoryProvider)
                                .createCategory(name);
                            return c.id;
                          },
                          onRefresh: () =>
                              ref.read(_categoriesProvider.notifier).load(),
                        );
                        if (newId != null) setState(() => _selectedCategoryId = newId);
                      },
                    ),
                  ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Product'),
            ),
          ],
        ),
      ),
    );
  }
}
