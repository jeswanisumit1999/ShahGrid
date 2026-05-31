import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../presentation/providers/auth_provider.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/auth_callback_screen.dart';
import '../presentation/screens/splash/splash_screen.dart';
import '../presentation/screens/dashboard/dashboard_screen.dart';
import '../presentation/screens/retailers/retailers_list_screen.dart';
import '../presentation/screens/retailers/retailer_detail_screen.dart';
import '../presentation/screens/orders/orders_list_screen.dart';
import '../presentation/screens/orders/order_detail_screen.dart';
import '../presentation/screens/orders/create_order_screen.dart';
import '../data/models/create_order_args.dart';
import '../presentation/screens/products/products_list_screen.dart';
import '../presentation/screens/products/create_product_screen.dart';
import '../presentation/screens/products/stock_ledger_screen.dart';
import '../presentation/screens/retailers/create_retailer_screen.dart';
import '../presentation/screens/retailers/retailer_ledger_screen.dart';
import '../presentation/screens/shipments/shipments_list_screen.dart';
import '../presentation/screens/shipments/shipment_detail_screen.dart';
import '../presentation/screens/payments/payments_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/admin/user_management_screen.dart';
import '../presentation/screens/checkins/checkins_screen.dart';
import '../presentation/screens/direct_sales/direct_sales_list_screen.dart';
import '../presentation/screens/direct_sales/direct_sale_detail_screen.dart';
import '../presentation/screens/direct_sales/create_direct_sale_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/widgets/layout/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: GoRouterRefreshStream(
      ref.read(authStateProvider.notifier).stream,
    ),
    redirect: (context, state) {
      final authValue = ref.read(authStateProvider);
      final isLoading = authValue.isLoading;
      final isLoggedIn = authValue.valueOrNull != null;
      final loc = state.matchedLocation;
      final isOnLogin    = loc == '/login';
      final isOnCallback = loc == '/auth/callback';

      if (isLoading) return loc == '/splash' ? null : '/splash';
      if (isOnCallback) return null; // let the callback screen handle itself
      if (loc == '/splash') return isLoggedIn ? '/dashboard' : '/login';
      if (!isLoggedIn && !isOnLogin) return '/login';
      if (isLoggedIn && isOnLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/auth/callback',
        builder: (_, s) => AuthCallbackScreen(
          accessToken: s.uri.queryParameters['accessToken'] ?? '',
          refreshToken: s.uri.queryParameters['refreshToken'] ?? '',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/retailers',
            builder: (_, __) => const RetailersListScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, __) => const CreateRetailerScreen()),
              GoRoute(
                path: ':id',
                builder: (_, s) => RetailerDetailScreen(id: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'ledger',
                    builder: (_, s) => RetailerLedgerScreen(retailerId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/orders',
            builder: (_, __) => const OrdersListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, s) => CreateOrderScreen(
                  args: s.extra is CreateOrderArgs ? s.extra as CreateOrderArgs : null,
                ),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => OrderDetailScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/products',
            builder: (_, __) => const ProductsListScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, __) => const CreateProductScreen()),
              GoRoute(
                path: ':id/ledger',
                builder: (_, s) => StockLedgerScreen(productId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/shipments',
            builder: (_, __) => const ShipmentsListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ShipmentDetailScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/payments', builder: (_, __) => const PaymentsScreen()),
          GoRoute(path: '/checkins', builder: (_, __) => const CheckInsScreen()),
          GoRoute(
            path: '/direct-sales',
            builder: (_, __) => const DirectSalesListScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, __) => const CreateDirectSaleScreen()),
              GoRoute(
                path: ':id',
                builder: (_, s) => DirectSaleDetailScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/admin/users', builder: (_, __) => const UserManagementScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod stream to GoRouter's Listenable-based refresh mechanism.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final dynamic _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
