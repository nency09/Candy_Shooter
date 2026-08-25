import 'dart:async';

import 'package:flutter/material.dart';

import 'services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.onSignedIn});

  final VoidCallback? onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();
  bool _creatingAccount = false;
  bool _busy = false;
  bool _passwordVisible = false;
  bool _waitingForGoogle = false;
  String? _error;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = _auth.authState.listen((user) {
      if (user == null || !_waitingForGoogle || !mounted) return;
      _waitingForGoogle = false;
      setState(() => _busy = false);
      widget.onSignedIn?.call();
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _waitingForGoogle = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creatingAccount) {
        await _auth.signUp(_name.text, _email.text, _password.text);
        // Keep the requested sign-up -> verified email -> sign-in flow even if
        // the provider ever returns a temporary session during registration.
        await _auth.signOut();
        if (mounted) {
          final email = _email.text.trim();
          setState(() {
            _creatingAccount = false;
            _name.clear();
            _password.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(
                'Welcome to Candy Shooter! We sent a verification email to '
                '$email. Open it, verify your account, then sign in.',
              ),
            ),
          );
        }
      } else {
        await _auth.signIn(_email.text, _password.text);
        widget.onSignedIn?.call();
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    try {
      await _auth.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final launched = await _auth.signInWithGoogle();
      if (!launched) throw StateError('Google sign-in could not be opened.');
      if (!mounted) return;
      setState(() {
        _waitingForGoogle = true;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Continue with Google to sign in.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted && !_waitingForGoogle) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('429') ||
        message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('over_email_send_rate_limit')) {
      return 'Too many account attempts were made. Please wait a few minutes '
          'and try again.';
    }
    if (message.contains('invalid-credential') ||
        message.contains('invalid login credentials')) {
      return 'That email or password is not correct.';
    }
    if (message.contains('email-already-in-use') ||
        message.contains('user already registered')) {
      return 'An account already exists with this email.';
    }
    if (message.contains('weak-password') ||
        message.contains('at least 6 characters')) {
      return 'Use a password with at least 6 characters.';
    }
    if (message.contains('invalid-email') ||
        message.contains('unable to validate email')) {
      return 'Enter a valid email address.';
    }
    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      return 'Please open the confirmation email, then sign in.';
    }
    if (message.contains('signup is disabled') ||
        message.contains('signups not allowed')) {
      return 'Account creation is currently unavailable. Please try again later.';
    }
    return 'Unable to continue. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff56bdf6), Color(0xffa27be7), Color(0xffff9fc5)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xfffcfaff),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33003583),
                    offset: Offset(0, 8),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IconButton(
                      alignment: Alignment.centerLeft,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Icon(
                      Icons.account_circle_rounded,
                      color: Color(0xfff6538a),
                      size: 62,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _creatingAccount ? 'CREATE ACCOUNT' : 'WELCOME BACK',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xff654486),
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _creatingAccount
                          ? 'Save your Candy Shooter account.'
                          : 'Sign in to your Candy Shooter account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (_creatingAccount) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) =>
                            _creatingAccount &&
                                (value == null || value.trim().isEmpty)
                            ? 'Enter your name.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) =>
                          value == null || !value.trim().contains('@')
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: !_passwordVisible,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _passwordVisible
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 6
                          ? 'Use at least 6 characters.'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xffd63059),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xfff6538a),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _creatingAccount ? 'CREATE ACCOUNT' : 'SIGN IN',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    if (!_creatingAccount)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Color(0xffd9cbe1)),
                      ),
                      icon: const Icon(
                        Icons.g_mobiledata_rounded,
                        color: Color(0xff4285f4),
                        size: 31,
                      ),
                      label: const Text(
                        'CONTINUE WITH GOOGLE',
                        style: TextStyle(
                          color: Color(0xff654486),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _creatingAccount = !_creatingAccount;
                              _error = null;
                            }),
                      child: Text(
                        _creatingAccount
                            ? 'Already have an account? Sign in'
                            : 'New player? Create an account',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You can also keep playing as a guest.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xff735d75), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
