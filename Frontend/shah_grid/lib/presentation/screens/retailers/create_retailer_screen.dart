import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/network/dio_client.dart';
import '../../providers/retailers_provider.dart';
import '../../providers/auth_provider.dart';

class CreateRetailerScreen extends ConsumerStatefulWidget {
  const CreateRetailerScreen({super.key});

  @override
  ConsumerState<CreateRetailerScreen> createState() => _CreateRetailerScreenState();
}

class _CreateRetailerScreenState extends ConsumerState<CreateRetailerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _creditCtrl = TextEditingController(text: '10000');
  final _pendingCtrl = TextEditingController(text: '0');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _gstinCtrl.dispose();
    _creditCtrl.dispose();
    _pendingCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _error = null; });
    try {
      final pending = double.tryParse(_pendingCtrl.text) ?? 0;
      final retailer = await ref.read(retailersRepositoryProvider).create({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (_addressCtrl.text.trim().isNotEmpty) 'address': _addressCtrl.text.trim(),
        if (_gstinCtrl.text.trim().isNotEmpty) 'gstin': _gstinCtrl.text.trim().toUpperCase(),
        'creditLimit': double.parse(_creditCtrl.text),
        if (pending > 0) 'initialPendingAmount': pending,
      });
      ref.invalidate(retailersProvider);
      if (mounted) context.go('/retailers/${retailer.id}');
    } catch (e) {
      setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSetCreditLimit =
        ref.watch(authStateProvider).valueOrNull?.hasPermission('retailers', 'credit_limit') ?? false;
    if (!canSetCreditLimit && _creditCtrl.text != '10000') {
      _creditCtrl.text = '10000';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Add Retailer')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone *'),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _gstinCtrl,
              decoration: const InputDecoration(
                labelText: 'GSTIN (optional)',
                hintText: '22AAAAA0000A1Z5',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final val = v.trim().toUpperCase();
                if (val.length != 15 || !RegExp(r'^[A-Z0-9]{15}$').hasMatch(val)) {
                  return 'Must be 15 alphanumeric characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _creditCtrl,
              decoration: InputDecoration(
                labelText: 'Credit Limit (₹) *',
                prefixText: '₹ ',
                helperText: canSetCreditLimit ? null : 'Set by Admin — default ₹10,000',
              ),
              keyboardType: TextInputType.number,
              readOnly: !canSetCreditLimit,
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n < 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pendingCtrl,
              decoration: const InputDecoration(
                labelText: 'Existing Pending Amount (₹)',
                prefixText: '₹ ',
                helperText: 'Leave 0 for new retailers. For migrated retailers, enter the outstanding balance they already owe.',
                helperMaxLines: 2,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n < 0) return 'Enter 0 or a positive amount';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create Retailer'),
            ),
          ],
        ),
      ),
    );
  }
}
