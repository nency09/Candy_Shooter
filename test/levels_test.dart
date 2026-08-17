import 'package:flutter_test/flutter_test.dart';
import 'package:candy_shooter/data/levels.dart';
import 'package:candy_shooter/models/game_models.dart';

void main() {
  test('catalog contains one hundred valid playable levels', () {
    expect(levels, hasLength(100));
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      expect(level.id, i + 1);
      expect(level.shots, greaterThan(0));
      expect(level.colors, isNotEmpty);
      expect(level.rows, greaterThan(0));
    }
    expect(levels.last.objective, ObjectiveType.board);
    expect(
      levels.take(10),
      everyElement(predicate<LevelConfig>((level) => !level.newRowEnabled)),
    );
    expect(levels[10].newRowInterval, 5);
    expect(levels[13].newRowInterval, 5);
    expect(levels[17].newRowInterval, 4);
    expect(levels[19].newRowInterval, 3);
  });
}
