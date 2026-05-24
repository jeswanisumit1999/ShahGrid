import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/models/admin_models.dart';
import '../../../data/repositories/users_repository.dart';
import '../../../core/network/dio_client.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _rolesProvider =
    StateNotifierProvider.autoDispose<_RolesNotifier, AsyncValue<List<RoleModel>>>(
        (ref) => _RolesNotifier(ref.read(usersRepositoryProvider)));

final _usersProvider =
    StateNotifierProvider.autoDispose<_UsersNotifier, AsyncValue<_UsersState>>(
        (ref) => _UsersNotifier(ref.read(usersRepositoryProvider)));

final _activityProvider =
    StateNotifierProvider.autoDispose<_ActivityNotifier, AsyncValue<_ActivityState>>(
        (ref) => _ActivityNotifier(ref.read(usersRepositoryProvider)));

// ── Notifiers ─────────────────────────────────────────────────────────────────

class _RolesNotifier extends StateNotifier<AsyncValue<List<RoleModel>>> {
  _RolesNotifier(this._repo) : super(const AsyncValue.loading()) { load(); }
  final UsersRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try { state = AsyncValue.data(await _repo.listRoles()); }
    catch (e, st) { state = AsyncValue.error(e, st); }
  }

  Future<void> deleteRole(String roleId) async {
    await _repo.deleteRole(roleId);
    load();
  }

  Future<void> updateRolePermissions(String roleId, List<String> permissionIds) async {
    await _repo.updateRolePermissions(roleId, permissionIds);
    load();
  }
}

class _ActivityState {
  const _ActivityState({required this.items, required this.hasMore, this.nextCursor});
  final List<ActivityLogEntry> items;
  final bool hasMore;
  final String? nextCursor;
}

class _ActivityNotifier extends StateNotifier<AsyncValue<_ActivityState>> {
  _ActivityNotifier(this._repo) : super(const AsyncValue.loading()) { load(); }
  final UsersRepository _repo;
  String? _search;

  Future<void> load({bool refresh = false, String? search}) async {
    _search = search ?? _search;
    if (refresh || state is! AsyncData) state = const AsyncValue.loading();
    try {
      final r = await _repo.listActivityLog(search: _search);
      state = AsyncValue.data(_ActivityState(
        items: r.items, hasMore: r.hasMore, nextCursor: r.nextCursor,
      ));
    } catch (e, st) { state = AsyncValue.error(e, st); }
  }

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore) return;
    try {
      final r = await _repo.listActivityLog(cursor: cur.nextCursor, search: _search);
      state = AsyncValue.data(_ActivityState(
        items: [...cur.items, ...r.items],
        hasMore: r.hasMore,
        nextCursor: r.nextCursor,
      ));
    } catch (_) {}
  }
}

class _UsersState {
  const _UsersState({required this.items, required this.hasMore, this.nextCursor});
  final List<AdminUserModel> items;
  final bool hasMore;
  final String? nextCursor;
}

class _UsersNotifier extends StateNotifier<AsyncValue<_UsersState>> {
  _UsersNotifier(this._repo) : super(const AsyncValue.loading()) { load(); }
  final UsersRepository _repo;
  String? _search;

  Future<void> load({bool refresh = false, String? search}) async {
    _search = search ?? _search;
    if (refresh || state is! AsyncData) state = const AsyncValue.loading();
    try {
      final r = await _repo.listUsers(search: _search);
      state = AsyncValue.data(_UsersState(
        items: r.items, hasMore: r.hasMore, nextCursor: r.nextCursor,
      ));
    } catch (e, st) { state = AsyncValue.error(e, st); }
  }

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore) return;
    try {
      final r = await _repo.listUsers(cursor: cur.nextCursor, search: _search);
      state = AsyncValue.data(_UsersState(
        items: [...cur.items, ...r.items],
        hasMore: r.hasMore,
        nextCursor: r.nextCursor,
      ));
    } catch (_) {}
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Roles'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Roles'),
            Tab(text: 'Users'),
            Tab(text: 'Activity'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_RolesTab(), _UsersTab(), _ActivityTab()],
      ),
    );
  }
}

// ── Roles Tab ─────────────────────────────────────────────────────────────────

class _RolesTab extends ConsumerWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_rolesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRoleSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Role'),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Failed to load roles',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref.read(_rolesProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (roles) => roles.isEmpty
            ? const Center(child: Text('No roles found'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: roles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _RoleCard(role: roles[i]),
              ),
      ),
    );
  }

  void _showCreateRoleSheet(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CreateRoleDialog(
        repo: ref.read(usersRepositoryProvider),
        onCreate: (name, desc, ids) async {
          await ref.read(usersRepositoryProvider).createRole(
                name: name,
                description: desc,
                permissionIds: ids,
              );
          ref.read(_rolesProvider.notifier).load();
        },
      ),
    );
  }
}

class _RoleCard extends ConsumerWidget {
  const _RoleCard({required this.role});
  final RoleModel role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(role.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (role.description != null) ...[
                      const SizedBox(height: 2),
                      Text(role.description!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ]),
                ),
                if (role.isSystemRole)
                  Chip(
                    label: const Text('System'),
                    backgroundColor: scheme.secondaryContainer,
                    labelStyle: TextStyle(
                        color: scheme.onSecondaryContainer, fontSize: 11),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit permissions',
                  onPressed: () => _showEditPermissions(context, ref),
                ),
                if (!role.isSystemRole)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    tooltip: 'Delete role',
                    onPressed: () => _confirmDelete(context, ref),
                  ),
              ],
            ),
            if (role.permissions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: role.permissions
                    .map((p) => Chip(
                          label: Text(p.key,
                              style: const TextStyle(fontSize: 11)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEditPermissions(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _EditPermissionsDialog(
        role: role,
        repo: ref.read(usersRepositoryProvider),
        onSaved: (permissionIds) async {
          await ref.read(_rolesProvider.notifier).updateRolePermissions(role.id, permissionIds);
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete "${role.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(_rolesProvider.notifier).deleteRole(role.id);
    } catch (e) {
      if (!context.mounted) return;
      final msg = friendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }
}

// ── Create Role Dialog ────────────────────────────────────────────────────────

class _CreateRoleDialog extends StatefulWidget {
  const _CreateRoleDialog({required this.repo, required this.onCreate});
  final UsersRepository repo;
  final Future<void> Function(String name, String? desc, List<String> ids) onCreate;

  @override
  State<_CreateRoleDialog> createState() => _CreateRoleDialogState();
}

class _CreateRoleDialogState extends State<_CreateRoleDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final Set<String> _selected = {};
  List<PermissionModel>? _permissions;
  bool _loadingPerms = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final perms = await widget.repo.listPermissions();
      if (mounted) setState(() { _permissions = perms; _loadingPerms = false; });
    } catch (e) {
      if (mounted) setState(() { _permissions = []; _loadingPerms = false; });
    }
  }

  Map<String, List<PermissionModel>> get _grouped {
    final map = <String, List<PermissionModel>>{};
    for (final p in _permissions ?? []) {
      map.putIfAbsent(p.resource, () => []).add(p);
    }
    return map;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Role name is required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onCreate(
        name,
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        _selected.toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final msg = friendlyError(e);
      setState(() { _error = msg; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Role'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Role Name *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Text('Permissions', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: _loadingPerms
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: _grouped.entries
                          .map((entry) => _PermissionGroup(
                                resource: entry.key,
                                permissions: entry.value,
                                selected: _selected,
                                onToggle: (id, val) => setState(() =>
                                    val ? _selected.add(id) : _selected.remove(id)),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _loadingPerms) ? null : _submit,
          child: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Edit Permissions Dialog ───────────────────────────────────────────────────

class _EditPermissionsDialog extends StatefulWidget {
  const _EditPermissionsDialog({
    required this.role,
    required this.repo,
    required this.onSaved,
  });
  final RoleModel role;
  final UsersRepository repo;
  final Future<void> Function(List<String> permissionIds) onSaved;

  @override
  State<_EditPermissionsDialog> createState() => _EditPermissionsDialogState();
}

class _EditPermissionsDialogState extends State<_EditPermissionsDialog> {
  late Set<String> _selected;
  List<PermissionModel>? _allPermissions;
  bool _loadingPerms = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.role.permissions.map((p) => p.id).toSet();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final perms = await widget.repo.listPermissions();
      if (mounted) setState(() { _allPermissions = perms; _loadingPerms = false; });
    } catch (_) {
      if (mounted) setState(() { _allPermissions = []; _loadingPerms = false; });
    }
  }

  Map<String, List<PermissionModel>> get _grouped {
    final map = <String, List<PermissionModel>>{};
    for (final p in _allPermissions ?? []) {
      map.putIfAbsent(p.resource, () => []).add(p);
    }
    return map;
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSaved(_selected.toList());
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions updated'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      final msg = friendlyError(e);
      setState(() { _error = msg; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Edit Permissions'),
          Text(widget.role.name, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: _loadingPerms
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  Expanded(
                    child: ListView(
                      children: _grouped.entries
                          .map((entry) => _PermissionGroup(
                                resource: entry.key,
                                permissions: entry.value,
                                selected: _selected,
                                onToggle: (id, val) => setState(
                                    () => val ? _selected.add(id) : _selected.remove(id)),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _loadingPerms) ? null : _save,
          child: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _PermissionGroup extends StatelessWidget {
  const _PermissionGroup({
    required this.resource,
    required this.permissions,
    required this.selected,
    required this.onToggle,
  });
  final String resource;
  final List<PermissionModel> permissions;
  final Set<String> selected;
  final void Function(String id, bool val) onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(resource,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        initiallyExpanded: true,
        children: permissions
            .map((p) => CheckboxListTile(
                  value: selected.contains(p.id),
                  onChanged: (v) => onToggle(p.id, v ?? false),
                  title: Text(p.action),
                  dense: true,
                ))
            .toList(),
      ),
    );
  }
}

// ── Users Tab ─────────────────────────────────────────────────────────────────

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(_usersProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_usersProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search users…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(_usersProvider.notifier).load(refresh: true, search: '');
                      },
                    )
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(_usersProvider.notifier).load(refresh: true, search: v),
          ),
        ),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Failed to load users',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () =>
                      ref.read(_usersProvider.notifier).load(refresh: true),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            data: (s) => RefreshIndicator(
              onRefresh: () =>
                  ref.read(_usersProvider.notifier).load(refresh: true),
              child: ListView.separated(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: s.items.length + (s.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) {
                  if (i == s.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _UserTile(user: s.items[i]);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user});
  final AdminUserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
          child: user.avatarUrl == null
              ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?')
              : null,
        ),
        title: Text(user.name,
            style: user.isActive
                ? null
                : TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    decoration: TextDecoration.lineThrough)),
        subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.roleName != null)
              Chip(
                label: Text(user.roleName!,
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: scheme.primaryContainer,
                labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            else
              Chip(
                label:
                    const Text('No role', style: TextStyle(fontSize: 11)),
                backgroundColor: scheme.errorContainer,
                labelStyle: TextStyle(color: scheme.onErrorContainer),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _showUserActions(context, ref),
      ),
    );
  }

  Future<void> _showUserActions(BuildContext context, WidgetRef ref) async {
    List<RoleModel> roles;
    try {
      roles = await ref.read(usersRepositoryProvider).listRoles();
    } catch (_) {
      roles = ref.read(_rolesProvider).valueOrNull ?? const [];
    }

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => _UserActionsSheet(
        user: user,
        roles: roles,
        onAssignRole: (roleId) async {
          await ref.read(usersRepositoryProvider).assignRole(
                userId: user.id,
                roleId: roleId,
              );
          ref.read(_usersProvider.notifier).load(refresh: true);
        },
        onDeactivate: () async {
          await ref.read(usersRepositoryProvider).deactivateUser(user.id);
          ref.read(_usersProvider.notifier).load(refresh: true);
        },
      ),
    );
  }
}

class _UserActionsSheet extends StatefulWidget {
  const _UserActionsSheet({
    required this.user,
    required this.roles,
    required this.onAssignRole,
    required this.onDeactivate,
  });
  final AdminUserModel user;
  final List<RoleModel> roles;
  final Future<void> Function(String roleId) onAssignRole;
  final Future<void> Function() onDeactivate;

  @override
  State<_UserActionsSheet> createState() => _UserActionsSheetState();
}

class _UserActionsSheetState extends State<_UserActionsSheet> {
  String? _selectedRoleId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedRoleId = widget.user.roleId;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(
              backgroundImage: widget.user.avatarUrl != null
                  ? NetworkImage(widget.user.avatarUrl!)
                  : null,
              child: widget.user.avatarUrl == null
                  ? Text(widget.user.name.isNotEmpty
                      ? widget.user.name[0].toUpperCase()
                      : '?')
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.user.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(widget.user.email,
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Assign Role', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedRoleId,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
            ),
            items: widget.roles
                .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedRoleId = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: (_saving || _selectedRoleId == null) ? null : _assignRole,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Role'),
              ),
            ),
            if (widget.user.isActive) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                onPressed: _saving ? null : _deactivate,
                child: const Text('Deactivate'),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Future<void> _assignRole() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onAssignRole(_selectedRoleId!);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      final msg = friendlyError(e);
      setState(() { _error = msg; _saving = false; });
    }
  }

  Future<void> _deactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate User'),
        content: Text('Deactivate ${widget.user.name}? They will no longer be able to log in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onDeactivate();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deactivated'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      final msg = friendlyError(e);
      setState(() { _error = msg; _saving = false; });
    }
  }
}

// ── Activity Tab ──────────────────────────────────────────────────────────────

class _ActivityTab extends ConsumerStatefulWidget {
  const _ActivityTab();

  @override
  ConsumerState<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<_ActivityTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(_activityProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_activityProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by action, entity or user…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(_activityProvider.notifier).load(refresh: true, search: '');
                      },
                    )
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(_activityProvider.notifier).load(refresh: true, search: v),
          ),
        ),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Failed to load activity',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => ref.read(_activityProvider.notifier).load(refresh: true),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            data: (s) => s.items.isEmpty
                ? const Center(child: Text('No activity found'))
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(_activityProvider.notifier).load(refresh: true),
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: s.items.length + (s.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 0),
                      itemBuilder: (ctx, i) {
                        if (i == s.items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _ActivityLogTile(entry: s.items[i]);
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ActivityLogTile extends StatelessWidget {
  const _ActivityLogTile({required this.entry});
  final ActivityLogEntry entry;

  static const _entityIcons = {
    'order': Icons.receipt_long_outlined,
    'retailer': Icons.storefront_outlined,
    'product': Icons.inventory_2_outlined,
    'shipment': Icons.local_shipping_outlined,
    'payment': Icons.payments_outlined,
    'user': Icons.person_outline,
    'role': Icons.admin_panel_settings_outlined,
    'setting': Icons.settings_outlined,
    'return': Icons.assignment_return_outlined,
    'visit': Icons.pin_drop_outlined,
  };

  static const _actionColors = {
    'create': Color(0xFF388E3C),
    'delete': Color(0xFFD32F2F),
    'update': Color(0xFFF57C00),
    'assign': Color(0xFF1976D2),
    'record': Color(0xFF00796B),
    'dispatch': Color(0xFF303F9F),
    'deliver': Color(0xFF388E3C),
    'adjust': Color(0xFF7B1FA2),
    'deactivate': Color(0xFFD32F2F),
  };

  String get _formattedAction => entry.action
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _formatKey(String key) => key
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[0]}')
      .replaceAll('_', ' ')
      .trim()
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _formatValue(dynamic v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Yes' : 'No';
    return v.toString();
  }

  IconData get _icon {
    final key = entry.entityType.toLowerCase();
    for (final k in _entityIcons.keys) {
      if (key.contains(k)) return _entityIcons[k]!;
    }
    return Icons.history_outlined;
  }

  Color _iconColor(BuildContext context) {
    final action = entry.action.toLowerCase();
    for (final k in _actionColors.keys) {
      if (action.contains(k)) return _actionColors[k]!;
    }
    return Theme.of(context).colorScheme.primary;
  }

  String get _relativeTime {
    final diff = DateTime.now().difference(entry.createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(entry.createdAt);
  }

  String get _fullTimestamp =>
      DateFormat('d MMM yyyy, HH:mm:ss').format(entry.createdAt);

  static String? _entityRoute(String entityType, String entityId) {
    switch (entityType.toLowerCase()) {
      case 'order':    return '/orders/$entityId';
      case 'retailer': return '/retailers/$entityId';
      case 'shipment': return '/shipments/$entityId';
      default:         return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _iconColor(context);
    final scheme = Theme.of(context).colorScheme;
    final diff = entry.diff;
    final filteredDiff = diff?.entries
        .where((e) => !e.key.endsWith('Id') && e.key != 'id')
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(_icon, color: color, size: 20),
        ),
        title: Text(_formattedAction,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 12, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Flexible(
                child: Text(entry.actorName,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Icon(Icons.access_time, size: 11, color: scheme.outline),
              const SizedBox(width: 3),
              Text(_relativeTime,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.outline)),
            ],
          ),
        ),
        trailing: Chip(
          label: Text(entry.entityType,
              style: const TextStyle(fontSize: 10)),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          backgroundColor: color.withValues(alpha: 0.08),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        childrenPadding: EdgeInsets.zero,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metadata rows
                _DetailRow(label: 'Time', value: _fullTimestamp,
                    icon: Icons.schedule_outlined),
                const SizedBox(height: 6),
                _DetailRow(label: 'Performed by',
                    value: '${entry.actorName}  (${entry.actorEmail})',
                    icon: Icons.person_outlined),
                const SizedBox(height: 6),
                _DetailRow(
                  label: entry.entityType,
                  value: entry.entityLabel ?? '—',
                  icon: Icons.label_outline,
                  onTap: _entityRoute(entry.entityType, entry.entityId) != null
                      ? () => context.go(_entityRoute(entry.entityType, entry.entityId)!)
                      : null,
                ),

                // Diff section
                if (filteredDiff != null && filteredDiff.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Changes',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.8,
                          )),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: filteredDiff.asMap().entries.map((e) {
                        final isLast = e.key == filteredDiff.length - 1;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Text(_formatKey(e.value.key),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            )),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _formatValue(e.value.value),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Divider(height: 1, color: scheme.outlineVariant),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        SizedBox(
          width: 100,
          child: Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ),
        Expanded(
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: scheme.primary,
                                decoration: TextDecoration.underline,
                                decorationColor: scheme.primary,
                              ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 11, color: scheme.primary),
                    ],
                  ),
                )
              : Text(
                  value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
        ),
      ],
    );
  }
}
