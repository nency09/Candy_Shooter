import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class WeeklyLeaderboardEntry {
  const WeeklyLeaderboardEntry({
    required this.uid,
    required this.name,
    required this.score,
  });

  final String uid;
  final String name;
  final int score;

  factory WeeklyLeaderboardEntry.fromMap(Map<String, dynamic> data) =>
      WeeklyLeaderboardEntry(
        uid: data['user_id'] as String? ?? '',
        name: (data['display_name'] as String?)?.trim().isNotEmpty == true
            ? (data['display_name'] as String).trim()
            : 'Candy Player',
        score: (data['score'] as num?)?.toInt() ?? 0,
      );
}

class LeaderboardService {
  LeaderboardService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  bool get _isAvailable =>
      _clientOverride != null || SupabaseService.isInitialized;
  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  static String currentWeekId([DateTime? value]) {
    final today = (value ?? DateTime.now()).toUtc();
    final date = DateTime.utc(today.year, today.month, today.day);
    final monday = date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${monday.year}-${twoDigits(monday.month)}-${twoDigits(monday.day)}';
  }

  Stream<List<WeeklyLeaderboardEntry>> watchTop({int limit = 20}) {
    if (!_isAvailable) return Stream.value(const <WeeklyLeaderboardEntry>[]);
    return _client
        .from('weekly_scores')
        .stream(primaryKey: ['week_start', 'user_id'])
        .eq('week_start', currentWeekId())
        .order('score', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(WeeklyLeaderboardEntry.fromMap).toList());
  }

  Stream<WeeklyLeaderboardEntry?> watchPlayer(String uid) {
    if (!_isAvailable) return Stream.value(null);
    return _client
        .from('weekly_scores')
        .stream(primaryKey: ['week_start', 'user_id'])
        .eq('week_start', currentWeekId())
        .map((rows) {
          final row = rows.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['user_id'] == uid,
            orElse: () => null,
          );
          return row == null ? null : WeeklyLeaderboardEntry.fromMap(row);
        });
  }

  Future<void> submitBestScore({
    required String uid,
    required String displayName,
    required int score,
  }) async {
    if (!_isAvailable || score <= 0) return;
    await _client.rpc('submit_weekly_score', params: {'new_score': score});
  }
}
