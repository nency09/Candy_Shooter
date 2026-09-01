import 'package:candy_shooter/services/leaderboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekly leaderboard uses the UTC Monday as its week identifier', () {
    expect(
      LeaderboardService.currentWeekId(DateTime.utc(2026, 9, 6, 23, 59)),
      '2026-08-31',
    );
    expect(
      LeaderboardService.currentWeekId(DateTime.utc(2026, 9, 7)),
      '2026-09-07',
    );
  });

  test(
    'legacy private leaderboard paths do not require table access',
    () async {
      final leaderboard = LeaderboardService();

      expect(await leaderboard.watchTop().first, isEmpty);
      expect(await leaderboard.watchPlayer('player-id').first, isNull);
    },
  );
}
