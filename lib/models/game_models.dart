import 'dart:ui';

enum ObjectiveType { clear, score, color, board }

class LevelConfig {
  const LevelConfig({
    required this.id,
    required this.shots,
    required this.colors,
    required this.objective,
    required this.target,
    required this.rows,
    required this.star2,
    required this.star3,
    this.newRowEnabled = false,
    this.newRowInterval = 0,
    this.initialLayout = const [],
    this.iceCount = 0,
    this.bombCount = 0,
    this.specialCandyTypes = const [],
    this.challengeTitle,
  });

  final int id;
  final int shots;
  final List<CandyColor> colors;
  final ObjectiveType objective;
  final int target;
  final int rows;
  final int star2;
  final int star3;
  final bool newRowEnabled;
  final int newRowInterval;
  final List<List<int?>> initialLayout;
  final int iceCount;
  final int bombCount;
  final List<String> specialCandyTypes;
  final String? challengeTitle;
}

enum CandyColor { strawberry, lemon, mint, blueberry, grape }

enum BoosterType { bomb, rainbow, lightning, goldenAim, megaBomb, extraSwap }

extension BoosterTypeStyle on BoosterType {
  String get label => switch (this) {
    BoosterType.bomb => 'Bomb',
    BoosterType.rainbow => 'Rainbow',
    BoosterType.lightning => 'Lightning',
    BoosterType.goldenAim => 'Golden Aim',
    BoosterType.megaBomb => 'Mega Bomb',
    BoosterType.extraSwap => 'Extra Swap',
  };

  String get emoji => switch (this) {
    BoosterType.bomb => '💣',
    BoosterType.rainbow => '🌈',
    BoosterType.lightning => '⚡',
    BoosterType.goldenAim => '🎯',
    BoosterType.megaBomb => '💥',
    BoosterType.extraSwap => '🔄',
  };
}

class ChapterConfig {
  const ChapterConfig({
    required this.id,
    required this.name,
    required this.startLevel,
    required this.reward,
    required this.rewardAmount,
    required this.coinReward,
  });

  final int id;
  final String name;
  final int startLevel;
  final BoosterType reward;
  final int rewardAmount;
  final int coinReward;

  int get endLevel => startLevel + 9;
}

extension CandyColorStyle on CandyColor {
  Color get color => switch (this) {
    CandyColor.strawberry => const Color(0xfff65371),
    CandyColor.lemon => const Color(0xffffcb43),
    CandyColor.mint => const Color(0xff55d69a),
    CandyColor.blueberry => const Color(0xff5f92f7),
    CandyColor.grape => const Color(0xffa568e5),
  };

  String get symbol => switch (this) {
    CandyColor.strawberry => '\u2665',
    CandyColor.lemon => '\u2726',
    CandyColor.mint => '\u25cf',
    CandyColor.blueberry => '\u25c6',
    CandyColor.grape => '\u2663',
  };

  String get name => switch (this) {
    CandyColor.strawberry => 'pink',
    CandyColor.lemon => 'yellow',
    CandyColor.mint => 'green',
    CandyColor.blueberry => 'blue',
    CandyColor.grape => 'purple',
  };
}

class CandyCell {
  const CandyCell(this.row, this.col, this.color, {this.isMystery = false});

  final int row;
  final int col;
  final CandyColor color;
  final bool isMystery;

  String get key => '$row:$col';
}
