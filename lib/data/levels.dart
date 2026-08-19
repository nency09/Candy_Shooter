import '../models/game_models.dart';

List<List<int?>> _initialLayout(int id, int rows, int colorCount) {
  final rowCount = rows + 1;
  return List<List<int?>>.generate(rowCount, (row) {
    final columns = 7 - (row.isOdd ? 1 : 0);
    return List<int?>.generate(columns, (col) {
      if (id <= 3) return (row * 3 + col + id) % colorCount;
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

final levels = List<LevelConfig>.unmodifiable(
  List<LevelConfig>.generate(100, (index) {
    final id = index + 1;
    final chapter = index ~/ 10;
    final withinChapter = index % 10;
    // New rows begin gently, then become more frequent as the game advances.
    final newRowEnabled = true;
    final newRowInterval = id <= 5
        ? 5
        : id <= 20
        ? 4
        : 3;
    final colorCount = id < 16
        ? 3
        : id < 31
        ? 4
        : 5;
    return LevelConfig(
      id: id,
      shots: id == 1
          ? 30
          : id == 20
          ? 20
          : id == 30
          ? 22
          : id == 40
          ? 20
          : id == 50
          ? 25
          : 32 + chapter * 2 + withinChapter,
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
      rows: 3 + (withinChapter ~/ 3).clamp(0, 3),
      initialLayout: _initialLayout(
        id,
        3 + (withinChapter ~/ 3).clamp(0, 3),
        colorCount,
      ),
      star2: 150 + id * 35,
      star3: 230 + id * 45,
      newRowEnabled: newRowEnabled,
      newRowInterval: newRowInterval,
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
