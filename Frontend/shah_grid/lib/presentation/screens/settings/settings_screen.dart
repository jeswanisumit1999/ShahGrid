import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/settings_model.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../core/network/dio_client.dart';
import '../../widgets/common/app_error_widget.dart';

// ── Display metadata for known keys ──────────────────────────────────────────

const _meta = <String, _SettingMeta>{
  'allow_credit_override': _SettingMeta(
    label: 'Allow Credit Override',
    group: 'Sales Operations',
    icon: Icons.credit_score_outlined,
  ),
  'sales_officer_view_all_retailers': _SettingMeta(
    label: 'View All Retailers',
    group: 'Sales Operations',
    icon: Icons.storefront_outlined,
  ),
  'sales_officer_order_all_retailers': _SettingMeta(
    label: 'Order for Any Retailer',
    group: 'Sales Operations',
    icon: Icons.receipt_long_outlined,
  ),
  'default_low_stock_threshold': _SettingMeta(
    label: 'Default Low Stock Threshold',
    group: 'Stock Management',
    icon: Icons.inventory_outlined,
  ),
  'next_challan_number': _SettingMeta(
    label: 'Next Challan Number',
    group: 'Documents',
    icon: Icons.receipt_outlined,
  ),
};

class _SettingMeta {
  const _SettingMeta({required this.label, required this.group, required this.icon});
  final String label;
  final String group;
  final IconData icon;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _settingsProvider =
    StateNotifierProvider.autoDispose<_SettingsNotifier, AsyncValue<List<AppSetting>>>(
  (ref) => _SettingsNotifier(ref.read(settingsRepositoryProvider)),
);

class _SettingsNotifier extends StateNotifier<AsyncValue<List<AppSetting>>> {
  _SettingsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }
  final SettingsRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repo.list());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(String key, String value) async {
    final current = state.valueOrNull ?? [];
    // Optimistic update
    state = AsyncValue.data(
      current.map((s) => s.key == key ? s.copyWith(value: value) : s).toList(),
    );
    try {
      final updated = await _repo.update(key, value);
      final fresh = state.valueOrNull ?? [];
      state = AsyncValue.data(
        fresh.map((s) => s.key == updated.key ? updated : s).toList(),
      );
    } catch (_) {
      // Rollback
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(
          error: e,
          onRetry: () => ref.read(_settingsProvider.notifier).load(),
        ),
        data: (settings) => RefreshIndicator(
          onRefresh: () => ref.read(_settingsProvider.notifier).load(),
          child: _SettingsList(settings: settings),
        ),
      ),
    );
  }
}

class _SettingsList extends ConsumerWidget {
  const _SettingsList({required this.settings});
  final List<AppSetting> settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group settings
    final groups = <String, List<AppSetting>>{};
    for (final s in settings) {
      final group = _meta[s.key]?.group ?? 'Other';
      groups.putIfAbsent(group, () => []).add(s);
    }

    final groupOrder = ['Sales Operations', 'Stock Management', 'Documents', 'Other'];
    final sortedGroups = groupOrder.where(groups.containsKey).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final group in sortedGroups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(group, style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            )),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: groups[group]!.map((s) {
                final isLast = s == groups[group]!.last;
                return _SettingTile(setting: s, isLast: isLast);
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingTile extends ConsumerWidget {
  const _SettingTile({required this.setting, required this.isLast});
  final AppSetting setting;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = _meta[setting.key];
    final label = meta?.label ?? _keyToLabel(setting.key);
    final icon = meta?.icon ?? Icons.settings_outlined;

    Widget tile;

    if (setting.isBool) {
      tile = SwitchListTile(
        secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        subtitle: setting.description != null
            ? Text(setting.description!, style: Theme.of(context).textTheme.bodySmall)
            : null,
        value: setting.boolValue,
        onChanged: (v) async {
          try {
            await ref.read(_settingsProvider.notifier).update(setting.key, v.toString());
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
              );
            }
          }
        },
      );
    } else {
      tile = ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        subtitle: setting.description != null
            ? Text(setting.description!, style: Theme.of(context).textTheme.bodySmall)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              setting.value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.edit_outlined, size: 18),
          ],
        ),
        onTap: () => _editValue(context, ref),
      );
    }

    return Column(
      children: [
        tile,
        if (!isLast) const Divider(height: 1, indent: 56),
      ],
    );
  }

  Future<void> _editValue(BuildContext context, WidgetRef ref) async {
    final meta = _meta[setting.key];
    final label = meta?.label ?? _keyToLabel(setting.key);
    final ctrl = TextEditingController(text: setting.value);
    final isNumeric = setting.intValue != null;

    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (setting.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(setting.description!,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              if (isNumeric && int.tryParse(v) == null) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (newValue == null || newValue == setting.value) return;

    try {
      await ref.read(_settingsProvider.notifier).update(setting.key, newValue);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Setting updated'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _keyToLabel(String key) =>
      key.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}
