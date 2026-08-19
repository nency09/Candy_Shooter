import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const _url = 'https://wsjehnbhuunidszumlvu.supabase.co';
  static const _publishableKey =
      'sb_publishable_mC61Yqf20Bga0n6j-w_TxA_v5Ap8w_0';
  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, publishableKey: _publishableKey);
    _isInitialized = true;
  }

  static SupabaseClient get client {
    if (!_isInitialized) {
      throw StateError('Supabase has not been initialized.');
    }
    return Supabase.instance.client;
  }
}
