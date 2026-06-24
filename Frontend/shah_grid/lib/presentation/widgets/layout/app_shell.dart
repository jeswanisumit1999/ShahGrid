import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/user_model.dart';

/// Responsive shell: NavigationRail on wide screens, BottomNavBar on mobile.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  // permissions: any one grants access; empty list = always visible
  static const _destinations = [
    _Dest(
      icon: Icons.dashboard_outlined,
      label: 'Dashboard',
      path: '/dashboard',
      permissions: [],
    ),
    _Dest(
      icon: Icons.storefront_outlined,
      label: 'Retailers',
      path: '/retailers',
      permissions: ['retailers.read', 'retailers.manage'],
    ),
    _Dest(
      icon: Icons.receipt_long_outlined,
      label: 'Orders',
      path: '/orders',
      permissions: ['orders.read', 'orders.create', 'orders.manage'],
    ),
    _Dest(
      icon: Icons.point_of_sale_outlined,
      label: 'Direct Sales',
      path: '/direct-sales',
      permissions: ['orders.direct_sale'],
    ),
    _Dest(
      icon: Icons.inventory_2_outlined,
      label: 'Products',
      path: '/products',
      permissions: ['products.read', 'products.manage'],
    ),
    _Dest(
      icon: Icons.local_shipping_outlined,
      label: 'Shipments',
      path: '/shipments',
      permissions: ['shipments.view'],
    ),
    _Dest(
      icon: Icons.payments_outlined,
      label: 'Payments',
      path: '/payments',
      permissions: ['payments.read', 'payments.record'],
    ),
    _Dest(
      icon: Icons.my_location,
      label: 'Check-Ins',
      path: '/checkins',
      permissions: ['checkins.read', 'checkins.create'],
    ),
    _Dest(
      icon: Icons.admin_panel_settings_outlined,
      label: 'Users & Roles',
      path: '/admin/users',
      permissions: ['roles.manage', 'users.read', 'users.manage'],
    ),
    _Dest(
      icon: Icons.tune_outlined,
      label: 'Settings',
      path: '/settings',
      permissions: ['settings.manage'],
    ),
    _Dest(
      icon: Icons.person_outline,
      label: 'Profile',
      path: '/profile',
      permissions: [],
    ),
  ];

  List<_Dest> _filterDestinations(UserModel? user) {
    final perms = user?.permissions ?? [];
    return _destinations.where((d) {
      if (d.permissions.isEmpty) return true;
      return d.permissions.any((p) => perms.contains(p));
    }).toList();
  }

  int _selectedIndex(BuildContext context, List<_Dest> visible) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = visible.indexWhere((d) => loc.startsWith(d.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final isWide = MediaQuery.sizeOf(context).width >= 800;
    final visibleDests = _filterDestinations(user);
    final selectedIndex = _selectedIndex(context, visibleDests);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1100,
              selectedIndex: selectedIndex,
              destinations: visibleDests
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ))
                  .toList(),
              onDestinationSelected: (i) => context.go(visibleDests[i].path),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    // ── Mobile bottom nav with overflow ──────────────────────────────────────
    final loc = GoRouterState.of(context).matchedLocation;
    const maxVisible = 4; // slots before "More"
    final hasOverflow = visibleDests.length > maxVisible + 1;
    final mainDests = hasOverflow ? visibleDests.take(maxVisible).toList() : visibleDests;
    final overflowDests = hasOverflow ? visibleDests.skip(maxVisible).toList() : <_Dest>[];

    final mainIdx = mainDests.indexWhere((d) => loc.startsWith(d.path));
    final inOverflow = overflowDests.any((d) => loc.startsWith(d.path));
    final bottomIdx = mainIdx >= 0 ? mainIdx : (inOverflow ? mainDests.length : 0);


    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: bottomIdx,
        destinations: [
          ...mainDests.map((d) => NavigationDestination(icon: Icon(d.icon), label: d.label)),
          if (hasOverflow)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: inOverflow,
                smallSize: 8,
                child: const Icon(Icons.more_horiz),
              ),
              label: 'More',
            ),
        ],
        onDestinationSelected: (i) {
          if (!hasOverflow || i < mainDests.length) {
            context.go(mainDests[i].path);
          } else {
            _showMoreSheet(context, loc, overflowDests);
          }
        },
      ),
    );
  }

  void _showMoreSheet(BuildContext outerCtx, String currentLoc, List<_Dest> dests) {
    showModalBottomSheet(
      context: outerCtx,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('More', style: Theme.of(outerCtx).textTheme.titleSmall),
            ),
            ...dests.map((d) {
              final selected = currentLoc.startsWith(d.path);
              return ListTile(
                leading: Icon(d.icon,
                    color: selected ? Theme.of(outerCtx).colorScheme.primary : null),
                title: Text(d.label,
                    style: selected
                        ? TextStyle(
                            color: Theme.of(outerCtx).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          )
                        : null),
                selected: selected,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  outerCtx.go(d.path);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Dest {
  const _Dest({
    required this.icon,
    required this.label,
    required this.path,
    required this.permissions,
  });
  final IconData icon;
  final String label;
  final String path;
  final List<String> permissions;
}
