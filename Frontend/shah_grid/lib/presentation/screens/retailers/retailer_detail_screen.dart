import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/retailers_provider.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../data/repositories/users_repository.dart';
import '../../../data/models/retailer_model.dart';
import '../../../data/models/admin_models.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../../core/network/dio_client.dart';

class RetailerDetailScreen extends ConsumerWidget {
  const RetailerDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(retailerDetailProvider(id));
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final canManage = authUser?.hasPermission('retailers', 'manage') ?? false;
    final canEditCreditLimit = authUser?.hasPermission('retailers', 'credit_limit') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Retailer'),
        actions: [
          if (canManage)
            async.whenOrNull(
              data: (retailer) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'edit') _editInfo(context, ref, retailer);
                  if (v == 'toggle') _toggleActive(context, ref, retailer);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit Info'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      leading: Icon(
                        retailer.isActive ? Icons.block : Icons.check_circle_outline,
                        color: retailer.isActive ? Colors.orange : Colors.green,
                      ),
                      title: Text(retailer.isActive ? 'Deactivate' : 'Activate'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ) ?? const SizedBox.shrink(),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e),
        data: (retailer) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(retailerDetailProvider(id)),
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(retailer.name, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(retailer.phone,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call_outlined),
                          tooltip: 'Call',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              launchUrl(Uri(scheme: 'tel', path: retailer.phone)),
                        ),
                      ],
                    ),
                    if (retailer.address != null) ...[
                      const SizedBox(height: 4),
                      Text(retailer.address!),
                    ],
                    if (retailer.gstin != null) ...[
                      const SizedBox(height: 4),
                      Text('GSTIN: ${retailer.gstin!}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _InfoRow(
                      'Credit Limit',
                      formatCurrency(retailer.creditLimit),
                      onEdit: canEditCreditLimit
                          ? () => _editCreditLimit(context, ref, retailer.creditLimit)
                          : null,
                    ),
                    _InfoRow('Total Pending', formatCurrency(retailer.pendingCollection)),
                    _InfoRow('Available Credit', formatCurrency(retailer.availableCredit)),
                    _InfoRow('Status', retailer.isActive ? 'Active' : 'Inactive'),
                    _InfoRow('Created', formatDate(retailer.createdAt)),
                  ],
                ),
              ),
            ),
            if (retailer.companyBalances.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pending by Company',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...retailer.companyBalances.map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(b.companyName)),
                          Text(
                            formatCurrency(b.pendingAmount),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: b.pendingAmount > 0
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        ]),
                      )),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Assigned Sales Officers', style: Theme.of(context).textTheme.titleMedium),
                if (canManage)
                  TextButton.icon(
                    onPressed: () => _manageOfficers(context, ref, retailer),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Manage'),
                  ),
              ],
            ),
            if (retailer.salesOfficers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No sales officers assigned',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...retailer.salesOfficers.map((o) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(o.name),
                    subtitle: Text(o.email),
                  )),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/orders?retailerId=$id'),
              icon: const Icon(Icons.receipt_long),
              label: const Text('View Orders'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/retailers/$id/ledger'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Payment Ledger'),
            ),
          ],
        ), // ListView
        ), // RefreshIndicator
      ),
    );
  }

  void _manageOfficers(BuildContext context, WidgetRef ref, RetailerModel retailer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _AssignOfficersSheet(
        usersRepo: ref.read(usersRepositoryProvider),
        retailersRepo: ref.read(retailersRepositoryProvider),
        retailerId: id,
        currentOfficerIds: retailer.salesOfficers.map((o) => o.id).toSet(),
        onSaved: () => ref.invalidate(retailerDetailProvider(id)),
      ),
    );
  }

  void _toggleActive(BuildContext context, WidgetRef ref, RetailerModel retailer) {
    final action = retailer.isActive ? 'Deactivate' : 'Activate';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('$action Retailer'),
        content: Text('$action "${retailer.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          FilledButton(
            style: retailer.isActive
                ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                : null,
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await ref.read(retailersRepositoryProvider).update(id, {'isActive': !retailer.isActive});
                ref.invalidate(retailerDetailProvider(id));
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _editInfo(BuildContext context, WidgetRef ref, RetailerModel retailer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _EditRetailerSheet(
        retailer: retailer,
        onSaved: () => ref.invalidate(retailerDetailProvider(id)),
        repo: ref.read(retailersRepositoryProvider),
      ),
    );
  }

  void _editCreditLimit(BuildContext context, WidgetRef ref, double current) {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Credit Limit'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Credit limit (₹)',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(ctrl.text);
              if (value == null || value < 0) return;
              Navigator.pop(dialogCtx);
              try {
                await ref
                    .read(retailersRepositoryProvider)
                    .update(id, {'creditLimit': value});
                ref.invalidate(retailerDetailProvider(id));
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _AssignOfficersSheet extends StatefulWidget {
  const _AssignOfficersSheet({
    required this.usersRepo,
    required this.retailersRepo,
    required this.retailerId,
    required this.currentOfficerIds,
    required this.onSaved,
  });

  final UsersRepository usersRepo;
  final RetailersRepository retailersRepo;
  final String retailerId;
  final Set<String> currentOfficerIds;
  final VoidCallback onSaved;

  @override
  State<_AssignOfficersSheet> createState() => _AssignOfficersSheetState();
}

class _AssignOfficersSheetState extends State<_AssignOfficersSheet> {
  List<AdminUserModel>? _users;
  late Set<String> _selected;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.currentOfficerIds);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final result = await widget.usersRepo.listUsers(limit: 100);
      if (mounted) {
        setState(() {
          _users = result.items.where((u) => u.isActive).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.retailersRepo.update(
        widget.retailerId,
        {'salesOfficerIds': _selected.toList()},
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Assign Sales Officers',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null && _users == null)
            Expanded(
              child: Center(
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _users!.length,
                itemBuilder: (_, i) {
                  final user = _users![i];
                  return CheckboxListTile(
                    value: _selected.contains(user.id),
                    onChanged: _saving
                        ? null
                        : (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(user.id);
                              } else {
                                _selected.remove(user.id);
                              }
                            }),
                    title: Text(user.name),
                    subtitle: Text(user.roleName != null
                        ? '${user.email}  •  ${user.roleName}'
                        : user.email),
                    secondary: const CircleAvatar(child: Icon(Icons.person)),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
            ),
          if (_error != null && _users != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: FilledButton(
              onPressed: _saving || _loading ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Assignments'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditRetailerSheet extends StatefulWidget {
  const _EditRetailerSheet({
    required this.retailer,
    required this.onSaved,
    required this.repo,
  });
  final RetailerModel retailer;
  final VoidCallback onSaved;
  final RetailersRepository repo;

  @override
  State<_EditRetailerSheet> createState() => _EditRetailerSheetState();
}

class _EditRetailerSheetState extends State<_EditRetailerSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _gstin;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.retailer.name);
    _phone = TextEditingController(text: widget.retailer.phone);
    _address = TextEditingController(text: widget.retailer.address ?? '');
    _gstin = TextEditingController(text: widget.retailer.gstin ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repo.update(widget.retailer.id, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
        if (_gstin.text.trim().isNotEmpty) 'gstin': _gstin.text.trim().toUpperCase(),
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Edit Retailer', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone *', border: OutlineInputBorder()),
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.trim().length < 7) ? 'Enter valid phone' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _gstin,
            decoration: const InputDecoration(labelText: 'GSTIN', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.characters,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              if (v.trim().length != 15) return 'GSTIN must be 15 characters';
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Changes'),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.onEdit});
  final String label;
  final String value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined, size: 16),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}
