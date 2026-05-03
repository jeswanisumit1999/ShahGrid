import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';

void main() {
  // Use real URL paths instead of hash-based routing (#/route).
  // This lets the backend redirect to /auth/callback and GoRouter sees it correctly.
  usePathUrlStrategy();
  runApp(const ProviderScope(child: ShahGridApp()));
}

class ShahGridApp extends ConsumerWidget {
  const ShahGridApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ShahGrid',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
