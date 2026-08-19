import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:candy_shooter/data/levels.dart';
import 'package:candy_shooter/main.dart' show BoardGeometry;
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
      expect(level.initialLayout, hasLength(level.rows + 1));
    }
    expect(levels.first.colors, hasLength(3));
    expect(levels.last.objective, ObjectiveType.board);
    expect(
      levels,
      everyElement(predicate<LevelConfig>((level) => level.newRowEnabled)),
    );
    expect(levels[0].newRowInterval, 5);
    expect(levels[4].newRowInterval, 5);
    expect(levels[5].newRowInterval, 4);
    expect(levels[19].newRowInterval, 4);
    expect(levels[20].newRowInterval, 3);
  });

  test('a newly inserted top row does not move existing candies sideways', () {
    final geometry = BoardGeometry(const Size(400, 700));
    const original = CandyCell(2, 3, CandyColor.strawberry);
    const shifted = CandyCell(3, 3, CandyColor.strawberry);

    final before = geometry.position(original);
    final after = geometry.position(shifted, phase: -1);

    expect(after.dx, closeTo(before.dx, .001));
    expect(after.dy, closeTo(before.dy + geometry.rowStep, .001));
  });
}
