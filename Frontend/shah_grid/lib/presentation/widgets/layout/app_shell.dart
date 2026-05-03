import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

/// Responsive shell: NavigationRail on wide screens, BottomNavBar on mobile.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _destinations = [
    _Dest(icon: Icons.dashboard_outlined, label: 'Dashboard', path: '/dashboard'),
    _Dest(icon: Icons.storefront_outlined, label: 'Retailers', path: '/retailers'),
    _Dest(icon: Icons.receipt_long_outlined, label: 'Orders', path: '/orders'),
    _Dest(icon: Icons.inventory_2_outlined, label: 'Products', path: '/products'),
    _Dest(icon: Icons.local_shipping_outlined, label: 'Shipments', path: '/shipments'),
    _Dest(icon: Icons.payments_outlined, label: 'Payments', path: '/payments'),
    _Dest(icon: Icons.my_location, label: 'Check-Ins', path: '/checkins'),
    _Dest(icon: Icons.admin_panel_settings_outlined, label: 'Users & Roles', path: '/admin/users'),
    _Dest(icon: Icons.person_outline, label: 'Profile', path: '/profile'),
  ];

  int _selectedIndex(BuildContext context, List<_Dest> visible) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = visible.indexWhere((d) => loc.startsWith(d.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final isWide = MediaQuery.sizeOf(context).width >= 800;
    final visibleDests = _filterDestinations(user?.roles ?? []);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(visibleDests[selectedIndex].label),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: visibleDests
            .map((d) => NavigationDestination(icon: Icon(d.icon), label: d.label))
            .toList(),
        onDestinationSelected: (i) => context.go(visibleDests[i].path),
      ),
    );
  }

  List<_Dest> _filterDestinations(List<String> roles) {
    // Profile is always visible; role-specific tabs precede it
    const profile = _Dest(icon: Icons.person_outline, label: 'Profile', path: '/profile');

    List<_Dest> tabs;
    if (roles.contains('Admin')) {
      tabs = _destinations.where((d) => d.path != '/profile' && d.path != '/admin/users' && d.path != '/checkins').toList()
        ..add(const _Dest(icon: Icons.my_location, label: 'Check-Ins', path: '/checkins'))
        ..add(const _Dest(icon: Icons.admin_panel_settings_outlined, label: 'Users & Roles', path: '/admin/users'));
    } else if (roles.contains('Supply Chain')) {
      tabs = _destinations.where((d) => const {
        '/dashboard', '/orders', '/shipments', '/products'
      }.contains(d.path)).toList();
    } else if (roles.contains('Sales Officer')) {
      tabs = _destinations.where((d) => const {
        '/dashboard', '/retailers', '/orders', '/payments', '/checkins'
      }.contains(d.path)).toList();
    } else if (roles.contains('Godown Manager')) {
      tabs = _destinations.where((d) => const {
        '/dashboard', '/shipments', '/products'
      }.contains(d.path)).toList();
    } else {
      tabs = [_destinations.first]; // Pending role: dashboard only
    }

    return [...tabs, profile];
  }
}

class _Dest {
  const _Dest({required this.icon, required this.label, required this.path});
  final IconData icon;
  final String label;
  final String path;
}
