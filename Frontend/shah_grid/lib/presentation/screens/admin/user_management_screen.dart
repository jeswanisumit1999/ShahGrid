import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/admin_models.dart';
import '../../../data/repositories/users_repository.dart';
import '../../../core/errors/app_exception.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _rolesProvider =
    StateNotifierProvider.autoDispose<_RolesNotifier, AsyncValue<List<RoleModel>>>(
        (ref) => _RolesNotifier(ref.read(usersRepositoryProvider)));


final _usersProvider =
    StateNotifierProvider.autoDispose<_UsersNotifier, AsyncValue<_UsersState>>(
        (ref) => _UsersNotifier(ref.read(usersRepositoryProvider)));

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
    _tabs = TabController(length: 2, vsync: this);
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
          tabs: const [Tab(text: 'Roles'), Tab(text: 'Users')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_RolesTab(), _UsersTab()],
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _CreateRoleSheet(
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

  Future<void> _showEditPermissions(BuildContext context, WidgetRef ref) async {
    List<PermissionModel> allPermissions;
    try {
      allPermissions = await ref.read(usersRepositoryProvider).listPermissions();
    } catch (_) {
      allPermissions = [];
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => _EditPermissionsSheet(
        role: role,
        allPermissions: allPermissions,
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
      final msg = e is AppException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }
}

// ── Create Role Bottom Sheet ──────────────────────────────────────────────────

class _CreateRoleSheet extends StatefulWidget {
  const _CreateRoleSheet({required this.repo, required this.onCreate});
  final UsersRepository repo;
  final Future<void> Function(String name, String? desc, List<String> ids) onCreate;

  @override
  State<_CreateRoleSheet> createState() => _CreateRoleSheetState();
}

class _CreateRoleSheetState extends State<_CreateRoleSheet> {
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
      final msg = e is AppException ? e.message : e.toString();
      setState(() { _error = msg; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('New Role', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_saving || _loadingPerms) ? null : _submit,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                  const SizedBox(height: 20),
                  Text('Permissions', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_loadingPerms)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ))
                  else
                    ..._grouped.entries.map((entry) => _PermissionGroup(
                          resource: entry.key,
                          permissions: entry.value,
                          selected: _selected,
                          onToggle: (id, val) => setState(() =>
                              val ? _selected.add(id) : _selected.remove(id)),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit Permissions Sheet ────────────────────────────────────────────────────

class _EditPermissionsSheet extends StatefulWidget {
  const _EditPermissionsSheet({
    required this.role,
    required this.allPermissions,
    required this.onSaved,
  });
  final RoleModel role;
  final List<PermissionModel> allPermissions;
  final Future<void> Function(List<String> permissionIds) onSaved;

  @override
  State<_EditPermissionsSheet> createState() => _EditPermissionsSheetState();
}

class _EditPermissionsSheetState extends State<_EditPermissionsSheet> {
  late Set<String> _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.role.permissions.map((p) => p.id).toSet();
  }

  Map<String, List<PermissionModel>> get _grouped {
    final map = <String, List<PermissionModel>>{};
    for (final p in widget.allPermissions) {
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
      final msg = e is AppException ? e.message : e.toString();
      setState(() { _error = msg; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Edit Permissions',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(widget.role.name,
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      final msg = e is AppException ? e.message : e.toString();
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
      final msg = e is AppException ? e.message : e.toString();
      setState(() { _error = msg; _saving = false; });
    }
  }
}
