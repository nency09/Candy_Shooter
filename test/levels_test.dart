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
      levels.take(10),
      everyElement(predicate<LevelConfig>((level) => !level.newRowEnabled)),
    );
    expect(
      levels.skip(10),
      everyElement(predicate<LevelConfig>((level) => level.newRowEnabled)),
    );
    expect(levels[0].newRowInterval, 6);
    expect(levels[4].newRowInterval, 6);
    expect(levels[5].newRowInterval, 5);
    expect(levels[9].newRowInterval, 5);
    expect(levels[10].newRowInterval, 4);
    expect(levels[19].newRowInterval, 4);
    expect(levels[20].newRowInterval, 4);
    expect(levels[10].rows, greaterThan(levels[9].rows));
    expect(levels[0].initialLayout, isNot(levels[1].initialLayout));
    expect(levels[5].colors, hasLength(4));
    expect(
      levels.map((level) => level.shots),
      everyElement(inInclusiveRange(23, 30)),
    );
    expect(levels[0].shots, 30);
    expect(levels[3].shots, 28);
    expect(levels[6].shots, 27);
    expect(levels[10].shots, 30);
    expect(levels[19].shots, 24);
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

  test('the shooter and centred top grid cell share the board centre line', () {
    final geometry = BoardGeometry(const Size(400, 700));
    const centreTopCell = CandyCell(0, 3, CandyColor.strawberry);

    expect(geometry.launcher.dx, closeTo(200, .001));
    expect(
      geometry.position(centreTopCell).dx,
      closeTo(geometry.launcher.dx, .001),
    );
  });
}
