import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/errors/app_exception.dart';

/// Holds the currently authenticated user. `null` = not logged in.
final authStateProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>(
  (ref) => AuthNotifier(ref.read(authRepositoryProvider)),
);

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  AuthNotifier(this._repo) : super(const AsyncValue.loading()) {
    _init();
  }

  final AuthRepository _repo;

  /// On startup: try to restore session from stored tokens.
  Future<void> _init() async {
    final token = await TokenStorage.getAccessToken();
    if (token == null) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      final user = await _repo.getMe();
      state = AsyncValue.data(user);
    } catch (_) {
      // Token expired or invalid — clear storage and require fresh login
      await TokenStorage.clearTokens();
      state = const AsyncValue.data(null);
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      final result = await _repo.signInWithGoogle();
      await TokenStorage.saveTokens(
        access: result.accessToken,
        refresh: result.refreshToken,
      );
      state = AsyncValue.data(result.user);
    } catch (e, st) {
      state = AsyncValue.error(parseError(e), st);
    }
  }

  /// Re-reads the stored token and fetches /auth/me — used after the OAuth web callback.
  Future<void> reload() => _init();

  Future<void> signOut() async {
    try {
      await _repo.logout();
    } finally {
      await TokenStorage.clearTokens();
      state = const AsyncValue.data(null);
    }
  }

  UserModel? get currentUser => state.valueOrNull;
}

/// Convenience: read the current user (throws if null).
final currentUserProvider = Provider<UserModel>((ref) {
  return ref.watch(authStateProvider).requireValue!;
});
