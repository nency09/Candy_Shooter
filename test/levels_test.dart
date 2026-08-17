import 'package:flutter_test/flutter_test.dart';
import 'package:candy_shooter/data/levels.dart';
import 'package:candy_shooter/models/game_models.dart';

void main() {
  test('MVP catalog contains ten valid playable levels', () {
    expect(levels, hasLength(10));
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      expect(level.id, i + 1);
      expect(level.shots, greaterThan(0));
      expect(level.colors, isNotEmpty);
      expect(level.rows, greaterThan(0));
    }
    expect(levels.last.objective, ObjectiveType.board);
  });
}
