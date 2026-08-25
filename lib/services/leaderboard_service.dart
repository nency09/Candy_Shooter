import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Authenticated weekly ranking entry. It is used for the signed-in player's
/// existing live weekly board, where the app can safely highlight its owner.
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

/// Safe data returned by the public leaderboard views. It deliberately has no
/// email address, cloud-save data, or player UUID.
class PublicLeaderboardEntry {
  const PublicLeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    required this.levelReached,
    required this.totalStars,
  });

  final int rank;
  final String name;
  final int score;
  final int levelReached;
  final int totalStars;

  factory PublicLeaderboardEntry.fromMap(Map<String, dynamic> data) =>
      PublicLeaderboardEntry(
        rank: (data['rank'] as num?)?.toInt() ?? 0,
        name: (data['display_name'] as String?)?.trim().isNotEmpty == true
            ? (data['display_name'] as String).trim()
            : 'Candy Player',
        score: (data['score'] as num?)?.toInt() ?? 0,
        levelReached: (data['level_reached'] as num?)?.toInt() ?? 1,
        totalStars: (data['total_stars'] as num?)?.toInt() ?? 0,
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

  /// Anyone can read these safe views. Polling keeps guest access simple while
  /// the protected game tables remain private.
  Stream<List<PublicLeaderboardEntry>> watchWeeklyGlobal({int limit = 20}) =>
      _watchView('weekly_global_leaderboard', limit: limit);

  Stream<List<PublicLeaderboardEntry>> watchGlobalProgress({int limit = 20}) =>
      _watchView('global_progress_leaderboard', limit: limit);

  Stream<List<PublicLeaderboardEntry>> _watchView(
    String view, {
    required int limit,
  }) async* {
    if (!_isAvailable) {
      yield const <PublicLeaderboardEntry>[];
      return;
    }
    yield await _readView(view, limit: limit);
    yield* Stream.periodic(
      const Duration(seconds: 15),
    ).asyncMap((_) => _readView(view, limit: limit));
  }

  Future<List<PublicLeaderboardEntry>> _readView(
    String view, {
    required int limit,
  }) async {
    final rows = await _client.from(view).select().order('rank').limit(limit);
    return (rows as List)
        .map(
          (row) => PublicLeaderboardEntry.fromMap(row as Map<String, dynamic>),
        )
        .toList();
  }

  /// Submission remains authenticated. The database uses auth.uid() and the
  /// profile display name, so callers cannot submit a result for another user.
  Future<void> submitLeaderboardResult({
    required int score,
    required int levelReached,
    required int totalStars,
  }) async {
    if (!_isAvailable || score <= 0) return;
    await _client.rpc(
      'submit_leaderboard_result',
      params: {
        'new_score': score,
        'new_level': levelReached,
        'new_total_stars': totalStars,
      },
    );
  }
}
