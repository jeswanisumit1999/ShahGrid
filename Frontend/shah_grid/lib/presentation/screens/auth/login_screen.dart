import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/web_redirect.dart';
import '../../../core/constants/api_constants.dart';

final _backendOAuthUrl = '${ApiConstants.baseUrl}/auth/google';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

    ref.listen(authStateProvider, (_, next) {
      if (next.hasError) {
        final err = next.error;
        final msg = friendlyError(err!);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    });

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.grid_view_rounded,
                    size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'ShahGrid',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Field Sales Management',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 48),
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  _GoogleSignInButton(
                    onPressed: () {
                      if (kIsWeb) {
                        // Web: hand off to backend OAuth flow; the callback
                        // screen (/auth/callback) will receive the tokens.
                        redirectToUrl(_backendOAuthUrl);
                      } else {
                        // Mobile: use google_sign_in + /auth/google/id-token
                        ref.read(authStateProvider.notifier).signInWithGoogle();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.login),
      label: const Text('Continue with Google'),
    );
  }
}
