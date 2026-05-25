import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';

/// Handles the redirect from the backend after Google OAuth completes.
/// URL: /auth/callback?accessToken=...&refreshToken=...
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({
    super.key,
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    _finishLogin();
  }

  Future<void> _finishLogin() async {
    try {
      await TokenStorage.saveTokens(
        access: widget.accessToken,
        refresh: widget.refreshToken,
      );
      await ref.read(authStateProvider.notifier).reload();
      if (mounted) context.go('/dashboard');
    } catch (_) {
      await TokenStorage.clearTokens();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Signing you in…'),
          ],
        ),
      ),
    );
  }
}
