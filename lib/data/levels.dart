import '../models/game_models.dart';

final levels = List<LevelConfig>.unmodifiable(
  List<LevelConfig>.generate(100, (index) {
    final id = index + 1;
    final chapter = index ~/ 10;
    final withinChapter = index % 10;
    final newRowEnabled = id >= 11;
    final newRowInterval = !newRowEnabled
        ? 0
        : id <= 14
        ? 5
        : id <= 18
        ? 4
        : id <= 20
        ? 3
        : (5 - (chapter ~/ 2)).clamp(2, 4);
    final colorCount = id < 3
        ? 2
        : id < 16
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
