import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/retailers_provider.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../data/repositories/users_repository.dart';
import '../../../data/models/retailer_model.dart';
import '../../../data/models/admin_models.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';

class RetailerDetailScreen extends ConsumerWidget {
  const RetailerDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(retailerDetailProvider(id));
    final canManage = ref.watch(authStateProvider).valueOrNull
            ?.hasPermission('retailers', 'manage') ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Retailer')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e),
        data: (retailer) => ListView(
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
                    Text(retailer.phone, style: Theme.of(context).textTheme.bodyMedium),
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
                      onEdit: canManage
                          ? () => _editCreditLimit(context, ref, retailer.creditLimit)
                          : null,
                    ),
                    _InfoRow('Pending Collection', formatCurrency(retailer.pendingCollection)),
                    _InfoRow('Available Credit', formatCurrency(retailer.availableCredit)),
                    _InfoRow('Status', retailer.isActive ? 'Active' : 'Inactive'),
                    _InfoRow('Created', formatDate(retailer.createdAt)),
                  ],
                ),
              ),
            ),
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
          ],
        ),
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
                      content: Text(e.toString()),
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
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
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
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
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
