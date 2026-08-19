import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class CloudProgressService {
  CloudProgressService(this.uid, {SupabaseClient? client})
    : _clientOverride = client;

  final String uid;
  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  Future<Map<String, Object>?> load() async {
    final profile = await _client
        .from('profiles')
        .select('progress')
        .eq('id', uid)
        .maybeSingle();
    final progress = profile?['progress'];
    return progress is Map ? Map<String, Object>.from(progress) : null;
  }

  Future<void> save(Map<String, Object> progress) => _client
      .from('profiles')
      .upsert({'id': uid, 'progress': progress}, onConflict: 'id');
}
