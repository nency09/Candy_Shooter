import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _authOverride = auth;

  final FirebaseAuth? _authOverride;

  bool get _isAvailable => _authOverride != null || Firebase.apps.isNotEmpty;

  FirebaseAuth get _auth {
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    return _authOverride ?? FirebaseAuth.instance;
  }

  Stream<User?> get authState =>
      _isAvailable ? _auth.authStateChanges() : Stream<User?>.value(null);
  User? get currentUser => _isAvailable ? _auth.currentUser : null;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signUp(String name, String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(name.trim());
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();
}
