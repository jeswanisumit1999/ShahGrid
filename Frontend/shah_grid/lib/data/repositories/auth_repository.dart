import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(dioProvider));
});

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  // clientId for web is read from the <meta name="google-signin-client_id"> tag in index.html.
  // Do NOT set serverClientId here — it switches to the auth-code flow and breaks idToken on web.
  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile', 'openid']);

  /// Signs in with Google and exchanges the ID token with the backend.
  Future<({String accessToken, String refreshToken, UserModel user})>
      signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) throw Exception('Google Sign-In cancelled');

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('No ID token from Google');

    final response = await _dio.post(
      ApiConstants.googleIdToken,
      data: {'idToken': idToken},
    );

    final data = unwrap<Map<String, dynamic>>(response);
    return (
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String? ?? '',
      user: UserModel.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  Future<UserModel> getMe() async {
    final response = await _dio.get(ApiConstants.me);
    return UserModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<String> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      ApiConstants.refresh,
      data: {'refreshToken': refreshToken},
    );
    return unwrap<Map<String, dynamic>>(response)['accessToken'] as String;
  }

  Future<void> logout() async {
    await _dio.post(ApiConstants.logout);
    await _googleSignIn.signOut();
  }
}
