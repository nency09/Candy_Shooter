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
  });

  final int id;
  final int shots;
  final List<CandyColor> colors;
  final ObjectiveType objective;
  final int target;
  final int rows;
  final int star2;
  final int star3;
}

enum CandyColor { strawberry, lemon, mint, blueberry }

extension CandyColorStyle on CandyColor {
  Color get color => switch (this) {
    CandyColor.strawberry => const Color(0xfff65371),
    CandyColor.lemon => const Color(0xffffcb43),
    CandyColor.mint => const Color(0xff55d69a),
    CandyColor.blueberry => const Color(0xff5f92f7),
  };

  String get symbol => switch (this) {
    CandyColor.strawberry => '\u2665',
    CandyColor.lemon => '\u2726',
    CandyColor.mint => '\u25cf',
    CandyColor.blueberry => '\u25c6',
  };

  String get name => switch (this) {
    CandyColor.strawberry => 'pink',
    CandyColor.lemon => 'yellow',
    CandyColor.mint => 'green',
    CandyColor.blueberry => 'blue',
  };
}

class CandyCell {
  const CandyCell(this.row, this.col, this.color);

  final int row;
  final int col;
  final CandyColor color;

  String get key => '$row:$col';
}
