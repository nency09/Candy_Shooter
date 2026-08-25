import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AuthService {
  static const _mobileRedirectUrl =
      'com.candyshooter.candyshooter://login-callback';

  AuthService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  bool get _isAvailable =>
      _clientOverride != null || SupabaseService.isInitialized;

  SupabaseClient get _client {
    if (!_isAvailable) {
      throw StateError('Supabase has not been initialized.');
    }
    return _clientOverride ?? SupabaseService.client;
  }

  Stream<User?> get authState => _isAvailable
      ? _client.auth.onAuthStateChange.map((event) => event.session?.user)
      : Stream<User?>.value(null);
  User? get currentUser => _isAvailable ? _client.auth.currentUser : null;

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  Future<bool> signInWithGoogle() => _client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: kIsWeb ? null : _mobileRedirectUrl,
    scopes: 'email profile',
  );

  Future<void> signUp(String name, String email, String password) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      // Confirmation is required before this account can sign in.  On Android,
      // send the player back into Candy Shooter after they tap the email link.
      emailRedirectTo: kIsWeb ? null : _mobileRedirectUrl,
      data: {'display_name': name.trim()},
    );
  }

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() => _client.auth.signOut();
}
