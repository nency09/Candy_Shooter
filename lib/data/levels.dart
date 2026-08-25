import '../models/game_models.dart';

List<List<int?>> _initialLayout(int id, int rows, int colorCount) {
  final rowCount = rows + 1;
  const earlyWidths = <List<int>>[
    [3, 4, 5],
    [5, 6, 5, 4],
    [6, 5, 6, 5],
    [7, 6, 5, 6, 5],
    [5, 6, 7, 6],
    [7, 6, 7, 6, 5],
    [6, 5, 6, 5, 6],
    [7, 6, 7, 6, 5, 6],
    [5, 6, 7, 6, 5, 4],
    [7, 6, 7, 6, 7, 6],
  ];
  const earlyShifts = <int>[0, 0, -1, 0, 0, 0, -1, 1, 0, 0];
  return List<List<int?>>.generate(rowCount, (row) {
    final columns = 7 - (row.isOdd ? 1 : 0);
    return List<int?>.generate(columns, (col) {
      if (id <= 10) {
        final width = earlyWidths[id - 1][row];
        final maxStart = columns - width;
        final start = (((columns - width) / 2).floor() + earlyShifts[id - 1])
            .clamp(0, maxStart)
            .toInt();
        if (col < start || col >= start + width) return null;
        // A few gentle cut-outs make the early boards recognisably different
        // while every candy still stays connected to the ceiling.
        if (id == 3 && row == 2 && col == start + 2) return null;
        if (id == 7 && row == 3 && col == start) return null;
        if (id == 9 && row == 4 && col == start + width - 1) return null;
        return (row * 3 + col * 2 + id) % colorCount;
      }
      // Each level uses a fixed cluster pattern rather than random holes.
      final isEdgeGap = row >= 2 && (row * 5 + col * 3 + id) % 7 == 0;
      if (id == 5 && row >= 2 && (col == 0 || col == columns - 1)) {
        return null;
      }
      if (id == 10 && row >= 2 && (col + row).isEven) return null;
      return isEdgeGap ? null : (row * 3 + col * 2 + id) % colorCount;
    });
  });
}

/// Shot budgets are intentionally tied to the board and objective tier, not
/// the level number. The player faces harder formations and ceiling pressure
/// as they progress, without receiving an ever-growing shot allowance.
int _shotBudget(int id) {
  if (id <= 3) return 30;
  if (id <= 6) return 28;
  if (id <= 10) return 27;
  if (id <= 15) return 30;
  if (id <= 19) return 28;
  if (id == 20) return 24;
  if (id <= 29) return 27;
  if (id == 30) return 24;
  if (id <= 39) return 26;
  if (id == 40) return 23;
  if (id <= 49) return 25;
  if (id == 50) return 24;
  if (id <= 70) return 25;
  return 24;
}

final levels = List<LevelConfig>.unmodifiable(
  List<LevelConfig>.generate(100, (index) {
    final id = index + 1;
    final withinChapter = index % 10;
    // The first chapter teaches normal matching with no descending-ceiling
    // pressure. Starting at level 11, boards are fuller and missed shots can
    // bring in a new top row.
    final newRowEnabled = id >= 11;
    final newRowInterval = id <= 5
        ? 6
        : id <= 10
        ? 5
        : id <= 30
        ? 4
        : id % 3 == 0
        ? 3
        : 4;
    final colorCount = id <= 5
        ? 3
        : id <= 30
        ? 4
        : 5;
    final initialRows = id <= 10
        ? const <int>[2, 3, 3, 4, 3, 4, 4, 5, 5, 5][id - 1]
        : id <= 20
        ? 6 + (withinChapter ~/ 4).clamp(0, 2)
        : id <= 40
        ? 7 + (withinChapter ~/ 5).clamp(0, 2)
        : 8;
    return LevelConfig(
      id: id,
      shots: _shotBudget(id),
      colors: CandyColor.values.take(colorCount).toList(),
      objective: id == 20 || id == 30 || id == 40 || id == 50
          ? ObjectiveType.clear
          : ObjectiveType.board,
      target: id == 20
          ? 40
          : id == 30
          ? 50
          : id == 40
          ? 35
          : id == 50
          ? 60
          : 0,
      rows: initialRows,
      initialLayout: _initialLayout(id, initialRows, colorCount),
      star2: 150 + id * 35,
      star3: 230 + id * 45,
      newRowEnabled: newRowEnabled,
      newRowInterval: newRowInterval,
      newRowSize: 0,
      newRowSpecialChance: id >= 51 ? .08 : 0,
      bombRadius: id <= 10
          ? 1
          : id <= 20
          ? 1
          : id <= 30
          ? 1.5
          : 2,
      iceCount: id >= 21 && id <= 30
          ? 2 + (withinChapter ~/ 2)
          : id >= 36 && id <= 50
          ? 4
          : 0,
      bombCount: id >= 31 && id <= 40
          ? 1 + (withinChapter ~/ 2)
          : id >= 45 && id <= 50
          ? 2
          : 0,
      specialCandyTypes: id >= 48
          ? const ['rainbow', 'striped', 'colorBomb']
          : id >= 44
          ? const ['rainbow', 'striped']
          : id >= 41
          ? const ['rainbow']
          : const [],
      challengeTitle: id == 20
          ? '🔥 CHALLENGE LEVEL'
          : id == 30
          ? '👑 HARD LEVEL'
          : id == 40
          ? '💣 BOMB CHALLENGE'
          : id == 50
          ? '🏆 CANDY MASTER'
          : null,
    );
  }),
);
