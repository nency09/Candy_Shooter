import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/levels.dart';
import 'models/game_models.dart';
import 'services/progress_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CandyShooterApp());
}

class AppModel extends ChangeNotifier {
  AppModel() {
    _load();
  }

  final _store = ProgressService();
  int unlocked = 1;
  int coins = 125;
  List<int> stars = List.filled(levels.length, 0);
  List<int> scores = List.filled(levels.length, 0);
  bool sound = true;
  bool music = true;
  bool haptics = true;
  bool ready = false;

  Future<void> _load() async {
    final started = DateTime.now();
    try {
      final saved = await _store.load();
      unlocked = (saved['unlocked'] as int? ?? 1).clamp(1, levels.length);
      coins = math.max(0, saved['coins'] as int? ?? 125);
      stars = _normaliseScores(saved['stars']);
      scores = _normaliseScores(saved['scores']);
      sound = saved['sound'] as bool? ?? true;
      music = saved['music'] as bool? ?? true;
      haptics = saved['haptics'] as bool? ?? true;
    } catch (_) {
      // Invalid local data falls back to a fresh, playable profile.
    }
    final remaining =
        const Duration(milliseconds: 750) - DateTime.now().difference(started);
    if (!remaining.isNegative) await Future<void>.delayed(remaining);
    ready = true;
    notifyListeners();
  }

  List<int> _normaliseScores(Object? values) {
    final list = values is List ? values : const <Object>[];
    return List<int>.generate(
      levels.length,
      (index) => index < list.length
          ? math.max(0, int.tryParse('${list[index]}') ?? 0)
          : 0,
    );
  }

  Future<void> _save() => _store.save(
    unlocked: unlocked,
    coins: coins,
    stars: stars,
    scores: scores,
    sound: sound,
    music: music,
    haptics: haptics,
  );

  Future<void> finishLevel(int level, int score, int earnedStars) async {
    final index = level - 1;
    stars[index] = math.max(stars[index], earnedStars.clamp(1, 3));
    scores[index] = math.max(scores[index], score);
    unlocked = math.max(unlocked, math.min(levels.length, level + 1));
    coins += 15 + earnedStars * 10;
    await _save();
    notifyListeners();
  }

  Future<void> updateSettings({bool? sound, bool? music, bool? haptics}) async {
    if (sound != null) this.sound = sound;
    if (music != null) this.music = music;
    if (haptics != null) this.haptics = haptics;
    notifyListeners();
    await _save();
  }

  Future<void> reset() async {
    await _store.reset();
    unlocked = 1;
    coins = 125;
    stars = List.filled(levels.length, 0);
    scores = List.filled(levels.length, 0);
    sound = music = haptics = true;
    await _save();
    notifyListeners();
  }
}

class CandyShooterApp extends StatefulWidget {
  const CandyShooterApp({super.key});

  @override
  State<CandyShooterApp> createState() => _CandyShooterAppState();
}

class _CandyShooterAppState extends State<CandyShooterApp> {
  final model = AppModel();

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (_, __) => MaterialApp(
      title: 'Candy Shooter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xfff65371),
      ),
      home: model.ready ? AppShell(model: model) : const SplashScreen(),
    ),
  );
}

enum AppPage { home, map, game, settings, collection }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.model});

  final AppModel model;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppPage page = AppPage.home;
  int level = 1;

  void go(AppPage next, {int? selectedLevel}) {
    setState(() {
      page = next;
      if (selectedLevel != null) level = selectedLevel;
    });
  }

  @override
  Widget build(BuildContext context) => switch (page) {
    AppPage.home => HomeScreen(model: widget.model, go: go),
    AppPage.map => LevelMapScreen(model: widget.model, go: go),
    AppPage.settings => SettingsScreen(
      model: widget.model,
      onBack: () => go(AppPage.home),
    ),
    AppPage.collection => CollectionScreen(
      model: widget.model,
      onBack: () => go(AppPage.home),
    ),
    AppPage.game => GameScreen(
      key: ValueKey(level),
      model: widget.model,
      config: levels[level - 1],
      onExit: () => go(AppPage.map),
      onNext: level == levels.length
          ? () => go(AppPage.map)
          : () => go(AppPage.game, selectedLevel: level + 1),
    ),
  };
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..forward();

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: Center(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) => Transform.scale(
          scale: .72 + Curves.elasticOut.transform(controller.value) * .28,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CandyBall(color: CandyColor.strawberry, size: 104),
              SizedBox(height: 18),
              LogoText(),
              SizedBox(height: 12),
              Text(
                'Pop. Smile. Repeat!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.model, required this.go});

  final AppModel model;
  final void Function(AppPage, {int? selectedLevel}) go;

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Row(
              children: [
                RoundIcon(Icons.settings_rounded, () => go(AppPage.settings)),
                const Spacer(),
                CoinPill(coins: model.coins),
              ],
            ),
          ),
          const Spacer(),
          const LollipopDecoration(size: 86),
          const SizedBox(height: 2),
          const LogoText(),
          const SizedBox(height: 20),
          PulseButton(label: 'PLAY', onTap: () => go(AppPage.map)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              MiniNav(
                icon: Icons.map_rounded,
                label: 'Levels',
                onTap: () => go(AppPage.map),
              ),
              MiniNav(
                icon: Icons.card_giftcard_rounded,
                label: 'Rewards',
                onTap: () => go(AppPage.collection),
              ),
              MiniNav(
                icon: Icons.emoji_events_rounded,
                label: 'Stars',
                onTap: () => go(AppPage.map),
              ),
              MiniNav(
                icon: Icons.settings_rounded,
                label: 'Settings',
                onTap: () => go(AppPage.settings),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HomeProgressCard(
            level: model.unlocked,
            stars: model.stars.fold<int>(0, (sum, value) => sum + value),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class LevelMapScreen extends StatelessWidget {
  const LevelMapScreen({super.key, required this.model, required this.go});

  final AppModel model;
  final void Function(AppPage, {int? selectedLevel}) go;

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: Column(
        children: [
          PageHeader(
            title: 'CANDY LAND',
            onBack: () => go(AppPage.home),
            trailing: CoinPill(coins: model.coins),
          ),
          const WorldRibbon('WORLD 1 \u2022 SWEET BEGINNINGS'),
          Expanded(
            child: WorldPathMap(
              unlocked: model.unlocked,
              stars: model.stars,
              onLevelTap: (number) => go(AppPage.game, selectedLevel: number),
            ),
          ),
        ],
      ),
    ),
  );
}

class WorldRibbon extends StatelessWidget {
  const WorldRibbon(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -.025,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xfff35d84),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x550a5780),
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    ),
  );
}

class WorldPathMap extends StatelessWidget {
  const WorldPathMap({
    super.key,
    required this.unlocked,
    required this.stars,
    required this.onLevelTap,
  });

  final int unlocked;
  final List<int> stars;
  final ValueChanged<int> onLevelTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      const mapHeight = 980.0;
      final width = constraints.maxWidth;
      final points = List<Offset>.generate(levels.length, (index) {
        final x = width / 2 + math.sin(index * 1.36) * width * .27;
        return Offset(x, 64 + index * 88.0);
      });
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: SizedBox(
          height: math.max(mapHeight, constraints.maxHeight),
          width: width,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: WorldPathPainter(points)),
              ),
              for (var index = 0; index < levels.length; index++)
                Positioned(
                  left: points[index].dx - 37,
                  top: points[index].dy - 37,
                  child: LevelBubble(
                    number: index + 1,
                    stars: stars[index],
                    locked: index + 1 > unlocked,
                    current: index + 1 == unlocked,
                    onTap: index + 1 <= unlocked
                        ? () => onLevelTap(index + 1)
                        : null,
                  ),
                ),
              const Positioned(left: 22, bottom: 24, child: CandyChest()),
            ],
          ),
        ),
      );
    },
  );
}

class CandyChest extends StatelessWidget {
  const CandyChest({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 58,
        height: 45,
        decoration: BoxDecoration(
          color: const Color(0xffffbf3c),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x440a5780),
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: const Icon(
          Icons.redeem_rounded,
          color: Color(0xffe05a55),
          size: 32,
        ),
      ),
      const SizedBox(height: 2),
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: Color(0xffffd24b), size: 16),
          Text(
            '10/20',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ],
  );
}

class HomeProgressCard extends StatelessWidget {
  const HomeProgressCard({super.key, required this.level, required this.stars});

  final int level;
  final int stars;

  @override
  Widget build(BuildContext context) => Container(
    width: 205,
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffffdfb4), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x330a5780),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Column(
      children: [
        const Text(
          'Candy Land',
          style: TextStyle(
            color: Color(0xff684e67),
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          'Level $level / ${levels.length}',
          style: const TextStyle(
            color: Color(0xff684e67),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: level / levels.length,
                  minHeight: 9,
                  backgroundColor: const Color(0xffffe3b2),
                  valueColor: const AlwaysStoppedAnimation(Color(0xff70c83c)),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xffffae26),
                  size: 18,
                ),
                Text(
                  '$stars',
                  style: const TextStyle(
                    color: Color(0xffffae26),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class BoardGeometry {
  BoardGeometry(this.size)
    : worldWidth = math.min(size.width, 400),
      ballDiameter = math.min(math.min(size.width, 400) * .12, 48);

  final Size size;
  final double worldWidth;
  final double ballDiameter;

  double get left => (size.width - worldWidth) / 2;
  double get xStep => ballDiameter;
  double get rowStep => ballDiameter * .8660254;
  double get top => math.max(32, size.height * .075);
  double get wallLeft => left + ballDiameter / 2;
  double get wallRight => left + worldWidth - ballDiameter / 2;
  Offset get launcher => Offset(size.width / 2, size.height * .89);

  Offset position(CandyCell cell) {
    final first = size.width / 2 - 3 * xStep;
    return Offset(
      first + (cell.col + (cell.row.isOdd ? .5 : 0)) * xStep,
      top + cell.row * rowStep,
    );
  }
}

class ShotSpark {
  ShotSpark({required this.position, required this.velocity});

  Offset position;
  Offset velocity;
  double life = 1;
}

class PopEffect {
  const PopEffect({
    required this.position,
    required this.color,
    required this.size,
  });

  final Offset position;
  final CandyColor color;
  final double size;
}

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.model,
    required this.config,
    required this.onExit,
    required this.onNext,
  });

  final AppModel model;
  final LevelConfig config;
  final VoidCallback onExit;
  final VoidCallback onNext;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final random = math.Random();
  final List<CandyCell> board = [];
  Timer? flightTimer;
  late final AnimationController launchController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController popController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 340),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(popEffects.clear);
        }
      });
  CandyColor current = CandyColor.strawberry;
  CandyColor next = CandyColor.lemon;
  List<Offset> aimPath = const [];
  final List<Offset> shotTrail = [];
  final List<ShotSpark> shotSparks = [];
  final List<PopEffect> popEffects = [];
  Offset? aimInput;
  Offset? flight;
  CandyColor? flyingColor;
  int shots = 0;
  int score = 0;
  int cleared = 0;
  int yellowCleared = 0;
  int combo = 0;
  bool paused = false;
  bool finished = false;
  bool won = false;
  String praise = 'Aim for a sweet match!';

  @override
  void initState() {
    super.initState();
    _newLevel();
  }

  void _newLevel() {
    flightTimer?.cancel();
    board.clear();
    shots = widget.config.shots;
    score = cleared = yellowCleared = combo = 0;
    aimPath = const [];
    shotTrail.clear();
    shotSparks.clear();
    popEffects.clear();
    aimInput = null;
    flight = null;
    flyingColor = null;
    paused = finished = won = false;
    praise = 'Aim for a sweet match!';
    for (var row = 0; row < widget.config.rows + 1; row++) {
      final columns = 7 - (row % 2);
      for (var col = 0; col < columns; col++) {
        if (row < 2 || random.nextDouble() > .18) {
          board.add(
            CandyCell(
              row,
              col,
              widget.config.colors[(row * 3 + col * 2 + widget.config.id) %
                  widget.config.colors.length],
            ),
          );
        }
      }
    }
    current = widget.config.colors.first;
    next = widget.config.colors[1 % widget.config.colors.length];
  }

  bool _touches(CandyCell first, CandyCell second, BoardGeometry g) =>
      (g.position(first) - g.position(second)).distance < g.ballDiameter * 1.04;

  List<CandyCell> _neighbors(CandyCell cell, BoardGeometry g) => board
      .where((other) => other != cell && _touches(other, cell, g))
      .toList();

  Offset? _velocity(Offset local, BoardGeometry g) {
    var target = local;
    if (target.dy > g.launcher.dy - 35) {
      target = Offset(target.dx, g.size.height * .35);
    }
    final direction = target - g.launcher;
    if (direction.dy >= -12 || direction.distance == 0) return null;
    return direction / direction.distance * 7;
  }

  List<Offset> _trajectory(Offset local, BoardGeometry g) {
    final initial = _velocity(local, g);
    if (initial == null) return const [];
    var velocity = initial;
    var point = g.launcher;
    final path = <Offset>[point];
    for (var step = 0; step < 1000; step++) {
      var nextPoint = point + velocity;
      if (nextPoint.dx < g.wallLeft || nextPoint.dx > g.wallRight) {
        path.add(point);
        velocity = Offset(-velocity.dx, velocity.dy);
        nextPoint = point + velocity;
      }
      point = nextPoint;
      if (point.dy <= g.top - g.ballDiameter / 2 ||
          board.any(
            (cell) => (g.position(cell) - point).distance < g.ballDiameter,
          )) {
        path.add(point);
        return path;
      }
    }
    return path;
  }

  void _updateAim(Offset point, BoardGeometry g) {
    if (finished || paused || flight != null) return;
    setState(() {
      aimInput = point;
      aimPath = _trajectory(point, g);
    });
  }

  void _shoot(Offset point, BoardGeometry g) {
    if (finished || paused || flight != null) return;
    final initial = _velocity(point, g);
    if (initial == null) return;
    if (widget.model.sound) SoundService.instance.playShoot();
    var velocity = initial;
    setState(() {
      final firedColor = current;
      aimPath = const [];
      aimInput = null;
      flyingColor = firedColor;
      current = next;
      next = widget.config.colors[random.nextInt(widget.config.colors.length)];
      shotTrail
        ..clear()
        ..add(g.launcher);
      shotSparks
        ..clear()
        ..addAll(
          List<ShotSpark>.generate(12, (index) {
            final spread = (index - 5.5) * .16;
            final vector = initial / initial.distance;
            return ShotSpark(
              position: g.launcher,
              velocity:
                  vector * (4 + random.nextDouble() * 4) +
                  Offset(spread * 6, random.nextDouble() * 2),
            );
          }),
        );
      flight = g.launcher;
    });
    launchController.forward(from: 0);
    flightTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || paused) return;
      setState(() {
        final previous = flight;
        if (previous == null) return;
        shotTrail.insert(0, previous);
        if (shotTrail.length > 14) shotTrail.removeLast();
        for (final spark in shotSparks) {
          spark.position += spark.velocity;
          spark.velocity += const Offset(0, .18);
          spark.life -= .055;
        }
        shotSparks.removeWhere((spark) => spark.life <= 0);
        var point = previous + velocity;
        if (point.dx < g.wallLeft || point.dx > g.wallRight) {
          velocity = Offset(-velocity.dx, velocity.dy);
          point = previous + velocity;
        }
        final hit = board.any(
          (cell) => (g.position(cell) - point).distance < g.ballDiameter,
        );
        if (hit || point.dy <= g.top - g.ballDiameter / 2) {
          flightTimer?.cancel();
          flightTimer = null;
          flight = null;
          shotTrail.clear();
          final firedColor = flyingColor ?? current;
          flyingColor = null;
          _attach(point, g, firedColor);
        } else {
          flight = point;
        }
      });
    });
  }

  CandyCell? _attachmentFor(
    Offset impact,
    BoardGeometry g,
    CandyColor firedColor,
  ) {
    final options = <CandyCell>[];
    for (var row = 0; row <= 11; row++) {
      for (var col = 0; col < 7 - (row % 2); col++) {
        if (board.any((cell) => cell.row == row && cell.col == col)) continue;
        final candidate = CandyCell(row, col, firedColor);
        if (row == 0 ||
            board.isEmpty ||
            board.any((cell) => _touches(candidate, cell, g))) {
          options.add(candidate);
        }
      }
    }
    if (options.isEmpty) return null;
    options.sort(
      (a, b) => (g.position(a) - impact).distance.compareTo(
        (g.position(b) - impact).distance,
      ),
    );
    return options.first;
  }

  void _attach(Offset impact, BoardGeometry g, CandyColor firedColor) {
    final added = _attachmentFor(impact, g, firedColor);
    shots--;
    if (added == null) {
      praise = 'The board is full. Try again!';
      if (shots <= 0) _finish(false);
      return;
    }
    board.add(added);
    final group = <CandyCell>[];
    final pending = <CandyCell>[added];
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      if (group.contains(cell)) continue;
      group.add(cell);
      for (final neighbor in _neighbors(cell, g)) {
        if (neighbor.color == added.color && !group.contains(neighbor)) {
          pending.add(neighbor);
        }
      }
    }
    if (group.length >= 3) {
      _showPop(group, g);
      _playPopSound(group.length);
      board.removeWhere(group.contains);
      cleared += group.length;
      if (added.color == CandyColor.lemon) yellowCleared += group.length;
      combo++;
      score += group.length * 10 + math.max(0, combo - 1) * 10;
      praise = combo > 1 ? 'Combo x$combo! Amazing!' : 'POP! Great shot!';
      _dropFloating(g);
      if (widget.model.haptics) HapticFeedback.mediumImpact();
    } else {
      combo = 0;
      praise = 'Nice try \u2014 make 3!';
      if (widget.model.sound) SoundService.instance.playNoMatch();
    }
    if (_objectiveDone) {
      _finish(true);
    } else if (shots <= 0) {
      _finish(false);
    }
  }

  void _dropFloating(BoardGeometry g) {
    final connected = <CandyCell>[];
    final pending = board.where((cell) => cell.row == 0).toList();
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      if (connected.contains(cell)) continue;
      connected.add(cell);
      for (final neighbor in _neighbors(cell, g)) {
        if (!connected.contains(neighbor)) pending.add(neighbor);
      }
    }
    final dropped = board.where((cell) => !connected.contains(cell)).toList();
    if (dropped.isNotEmpty) {
      board.removeWhere(dropped.contains);
      cleared += dropped.length;
      yellowCleared += dropped
          .where((cell) => cell.color == CandyColor.lemon)
          .length;
      score += dropped.length * 15;
      praise = 'Sweet drop +${dropped.length * 15}!';
    }
  }

  void _showPop(List<CandyCell> candies, BoardGeometry g) {
    popEffects
      ..clear()
      ..addAll(
        candies.map(
          (candy) => PopEffect(
            position: g.position(candy),
            color: candy.color,
            size: g.ballDiameter,
          ),
        ),
      );
    popController.forward(from: 0);
  }

  void _playPopSound(int candyCount) {
    if (!widget.model.sound) return;
    SoundService.instance.playPop(candyCount: candyCount);
  }

  bool get _objectiveDone => board.isEmpty;

  String get _objectiveText => 'Clear all: ${board.length} left';

  int get _earnedStars => score >= widget.config.star3
      ? 3
      : score >= widget.config.star2
      ? 2
      : 1;

  Future<void> _finish(bool didWin) async {
    if (finished) return;
    finished = true;
    won = didWin;
    if (didWin) {
      await widget.model.finishLevel(widget.config.id, score, _earnedStars);
    }
    if (mounted) setState(() {});
  }

  Future<void> _showPause() async {
    if (finished || paused) return;
    setState(() => paused = true);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('PAUSED'),
        content: const Text('Take a tiny candy break!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'restart'),
            child: const Text('RESTART'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'exit'),
            child: const Text('EXIT LEVEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'exit') {
      flightTimer?.cancel();
      widget.onExit();
    } else if (action == 'restart') {
      setState(_newLevel);
    } else {
      setState(() => paused = false);
    }
  }

  @override
  void dispose() {
    flightTimer?.cancel();
    launchController.dispose();
    popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GradientScaffold(
    playfield: true,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                RoundIcon(Icons.arrow_back_rounded, widget.onExit),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'LEVEL ${widget.config.id}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                RoundIcon(Icons.pause_rounded, _showPause),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: InfoPill(
                      icon: Icons.track_changes_rounded,
                      text: _objectiveText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InfoPill(
                  icon: Icons.auto_awesome_rounded,
                  text: '$shots shots',
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final g = BoardGeometry(constraints.biggest);
                final candySize = g.ballDiameter;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _updateAim(details.localPosition, g),
                  onTapUp: (details) => _shoot(details.localPosition, g),
                  onPanStart: (details) => _updateAim(details.localPosition, g),
                  onPanUpdate: (details) =>
                      _updateAim(details.localPosition, g),
                  onPanEnd: (_) {
                    if (aimInput != null) _shoot(aimInput!, g);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: AimPainter(path: aimPath)),
                      ),
                      ...board.map((cell) {
                        final position = g.position(cell);
                        return Positioned(
                          left: position.dx - candySize / 2,
                          top: position.dy - candySize / 2,
                          child: CandyBall(color: cell.color, size: candySize),
                        );
                      }),
                      ...popEffects.map(
                        (effect) => Positioned(
                          left: effect.position.dx - effect.size / 2,
                          top: effect.position.dy - effect.size / 2,
                          child: IgnorePointer(
                            child: PopCandyEffect(
                              effect: effect,
                              animation: popController,
                            ),
                          ),
                        ),
                      ),
                      ...shotSparks.map(
                        (spark) => Positioned(
                          left: spark.position.dx - 7,
                          top: spark.position.dy - 7,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: spark.life.clamp(0, 1),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xfffff0a6),
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      ...shotTrail.asMap().entries.map((entry) {
                        final fade =
                            (shotTrail.length - entry.key) /
                            (shotTrail.length + 1);
                        final diameter = candySize * (.16 + fade * .20);
                        return Positioned(
                          left: entry.value.dx - diameter / 2,
                          top: entry.value.dy - diameter / 2,
                          child: IgnorePointer(
                            child: Container(
                              width: diameter,
                              height: diameter,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (flyingColor ?? current).color.withValues(
                                  alpha: fade * .55,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(
                                      alpha: fade * .65,
                                    ),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      if (flight != null)
                        Positioned(
                          left: flight!.dx - candySize / 2,
                          top: flight!.dy - candySize / 2,
                          child: AnimatedBuilder(
                            animation: launchController,
                            builder: (_, child) => Transform.scale(
                              scale:
                                  1 +
                                  .13 *
                                      (1 -
                                          Curves.easeOut.transform(
                                            launchController.value,
                                          )),
                              child: child,
                            ),
                            child: CandyBall(
                              color: flyingColor ?? current,
                              size: candySize,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 6,
                        child: Text(
                          praise,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Positioned(
                        left: g.launcher.dx - candySize * .68,
                        bottom: 18,
                        child: AnimatedBuilder(
                          animation: launchController,
                          builder: (_, child) {
                            final recoil =
                                math.sin(launchController.value * math.pi) * 9;
                            return Transform.translate(
                              offset: Offset(0, recoil),
                              child: Transform.scale(
                                scale:
                                    1 +
                                    math.sin(launchController.value * math.pi) *
                                        .055,
                                child: child,
                              ),
                            );
                          },
                          child: LollipopLauncher(
                            color: current,
                            size: candySize * 1.36,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 17,
                        bottom: 26,
                        child: Column(
                          children: [
                            const Text(
                              'NEXT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            CandyBall(color: next, size: candySize * .76),
                          ],
                        ),
                      ),
                      if (finished)
                        ResultOverlay(
                          won: won,
                          candiesCleared: cleared,
                          stars: _earnedStars,
                          onPrimary: won
                              ? widget.onNext
                              : () => setState(_newLevel),
                          onSecondary: widget.onExit,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class AimPainter extends CustomPainter {
  AimPainter({required this.path});

  final List<Offset> path;

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;
    final paint = Paint()..color = Colors.white70;
    for (var segment = 0; segment < path.length - 1; segment++) {
      final start = path[segment];
      final end = path[segment + 1];
      final direction = end - start;
      if (direction.distance == 0) continue;
      for (
        double distance = 16;
        distance <= direction.distance;
        distance += 13
      ) {
        canvas.drawCircle(
          start + direction / direction.distance * distance,
          2.3,
          paint,
        );
      }
      canvas.drawCircle(end, 2.3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AimPainter oldDelegate) =>
      oldDelegate.path != path;
}

class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.won,
    required this.candiesCleared,
    required this.stars,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool won;
  final int candiesCleared;
  final int stars;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xaa27305e),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? 'LEVEL COMPLETE!' : 'Almost there!',
                style: TextStyle(
                  color: won
                      ? const Color(0xffe75a84)
                      : const Color(0xff8154c7),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                won
                    ? 'Awesome! You made it sweet.'
                    : 'Try again \u2014 you are close!',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              won
                  ? StarRow(stars: stars, size: 40)
                  : const Icon(
                      Icons.sentiment_satisfied_alt_rounded,
                      color: Color(0xffff779f),
                      size: 42,
                    ),
              Text(
                'Candies cleared: $candiesCleared',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: won ? 'NEXT LEVEL' : 'TRY AGAIN',
                onTap: onPrimary,
              ),
              TextButton(
                onPressed: onSecondary,
                child: Text(won ? 'LEVEL MAP' : 'BACK TO MAP'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.model, required this.onBack});

  final AppModel model;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PageHeader(title: 'SETTINGS', onBack: onBack),
          Panel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingTile(
                  label: 'Sound effects',
                  value: model.sound,
                  onChanged: (value) => model.updateSettings(sound: value),
                ),
                SettingTile(
                  label: 'Music',
                  value: model.music,
                  onChanged: (value) => model.updateSettings(music: value),
                ),
                SettingTile(
                  label: 'Vibration',
                  value: model.haptics,
                  onChanged: (value) => model.updateSettings(haptics: value),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => _confirmReset(context),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset Progress'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _confirmReset(BuildContext context) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'This removes your saved stars, scores, and coins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
    if (shouldReset == true) await model.reset();
  }
}

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({
    super.key,
    required this.model,
    required this.onBack,
  });

  final AppModel model;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: Column(
        children: [
          PageHeader(
            title: 'COLLECTION',
            onBack: onBack,
            trailing: CoinPill(coins: model.coins),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Keep playing to collect sweet launcher skins!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(22),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              children: [
                CollectionCard(
                  name: 'Classic Pop',
                  color: CandyColor.strawberry,
                  unlocked: true,
                ),
                CollectionCard(
                  name: 'Lollipop',
                  color: CandyColor.lemon,
                  unlocked: model.unlocked >= 4,
                ),
                CollectionCard(
                  name: 'Mint Swirl',
                  color: CandyColor.mint,
                  unlocked: model.unlocked >= 7,
                ),
                CollectionCard(
                  name: 'Rainbow Glow',
                  color: CandyColor.blueberry,
                  unlocked: model.unlocked >= 10,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

const _sky = BoxDecoration(
  gradient: LinearGradient(
    colors: [Color(0xff6dc9ff), Color(0xffb59aff), Color(0xffffb4d0)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),
);

class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.child,
    this.playfield = false,
  });

  final Widget child;
  final bool playfield;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: _sky,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CandyWorldPainter(playfield: playfield),
              ),
            ),
          ),
          child,
        ],
      ),
    ),
  );
}

class CandyWorldPainter extends CustomPainter {
  const CandyWorldPainter({required this.playfield});

  final bool playfield;

  @override
  void paint(Canvas canvas, Size size) {
    if (playfield) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xffc5b8f4),
      );
      _cloud(canvas, Offset(size.width * .12, size.height * .18), 22);
      _cloud(canvas, Offset(size.width * .86, size.height * .28), 19);
      final ground = Path()
        ..moveTo(0, size.height * .88)
        ..quadraticBezierTo(
          size.width * .28,
          size.height * .79,
          size.width * .52,
          size.height * .9,
        )
        ..quadraticBezierTo(
          size.width * .8,
          size.height * .82,
          size.width,
          size.height * .88,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(ground, Paint()..color = const Color(0xffffa8d3));
      return;
    }
    final hillBack = Path()
      ..moveTo(0, size.height * .68)
      ..quadraticBezierTo(
        size.width * .2,
        size.height * .51,
        size.width * .43,
        size.height * .68,
      )
      ..quadraticBezierTo(
        size.width * .73,
        size.height * .47,
        size.width,
        size.height * .65,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hillBack, Paint()..color = const Color(0xff9bdd71));
    final hillFront = Path()
      ..moveTo(0, size.height * .77)
      ..quadraticBezierTo(
        size.width * .2,
        size.height * .64,
        size.width * .48,
        size.height * .8,
      )
      ..quadraticBezierTo(
        size.width * .77,
        size.height * .62,
        size.width,
        size.height * .76,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hillFront, Paint()..color = const Color(0xff75c969));
    _cloud(canvas, Offset(size.width * .14, size.height * .18), 15);
    _cloud(canvas, Offset(size.width * .83, size.height * .16), 20);
    _lollipop(
      canvas,
      Offset(size.width * .1, size.height * .68),
      17,
      const Color(0xffff77a5),
    );
    _lollipop(
      canvas,
      Offset(size.width * .88, size.height * .62),
      20,
      const Color(0xffff8fb4),
    );
    _lollipop(
      canvas,
      Offset(size.width * .24, size.height * .74),
      13,
      const Color(0xffffb64a),
    );
    _sprinkles(canvas, size);
  }

  void _cloud(Canvas canvas, Offset center, double radius) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .72);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center + Offset(radius * .8, radius * .1),
      radius * .7,
      paint,
    );
    canvas.drawCircle(
      center - Offset(radius * .75, -radius * .18),
      radius * .55,
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(radius * .25, radius * .45),
          width: radius * 3,
          height: radius,
        ),
        const Radius.circular(12),
      ),
      paint,
    );
  }

  void _lollipop(Canvas canvas, Offset center, double radius, Color color) {
    final stick = Paint()
      ..color = const Color(0xfffff3cf)
      ..strokeWidth = radius * .3;
    canvas.drawLine(
      center + Offset(0, radius * .5),
      center + Offset(-radius * .2, radius * 2.2),
      stick,
    );
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius * .76,
      Paint()
        ..color = Colors.white.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .22,
    );
  }

  void _sprinkles(Canvas canvas, Size size) {
    final colors = [
      const Color(0xffff78aa),
      const Color(0xffffd15c),
      const Color(0xff9e72ef),
    ];
    for (var index = 0; index < 18; index++) {
      final x = (index * 57 % size.width) + 4;
      final y = size.height * (.58 + (index % 6) * .06);
      canvas.drawCircle(
        Offset(x, y),
        2.4,
        Paint()..color = colors[index % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant CandyWorldPainter oldDelegate) =>
      oldDelegate.playfield != playfield;
}

class WorldPathPainter extends CustomPainter {
  const WorldPathPainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final pink = Paint()
      ..color = const Color(0xffef7392)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      canvas.drawLine(start, end, white);
      final direction = end - start;
      final unit = direction / direction.distance;
      for (double d = 0; d < direction.distance; d += 22) {
        canvas.drawLine(
          start + unit * d,
          start + unit * math.min(d + 10, direction.distance),
          pink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant WorldPathPainter oldDelegate) =>
      oldDelegate.points != points;
}

class LollipopDecoration extends StatelessWidget {
  const LollipopDecoration({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 1.32,
    child: Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: size * .65,
          child: Transform.rotate(
            angle: -.17,
            child: Container(
              width: size * .16,
              height: size * .65,
              decoration: BoxDecoration(
                color: const Color(0xfffff2ca),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xffff779f),
          ),
          child: CustomPaint(painter: CandySwirlPainter()),
        ),
      ],
    ),
  );
}

class LollipopLauncher extends StatelessWidget {
  const LollipopLauncher({super.key, required this.color, required this.size});

  final CandyColor color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 1.36,
    height: size * 1.62,
    child: Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: size * .54,
          child: Container(
            width: size * .68,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xffffe6ec),
              borderRadius: BorderRadius.circular(size * .25),
              border: Border.all(color: const Color(0xffff8fb1), width: 3),
            ),
          ),
        ),
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.color,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x550a5780),
                offset: Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: CustomPaint(painter: CandySwirlPainter()),
        ),
        Positioned(
          bottom: 0,
          child: Container(
            width: size * 1.36,
            height: size * .26,
            decoration: BoxDecoration(
              color: const Color(0xfff477a0),
              borderRadius: BorderRadius.circular(size),
            ),
          ),
        ),
      ],
    ),
  );
}

class CandySwirlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .11
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
      size.width * .16,
      size.height * .16,
      size.width * .68,
      size.height * .68,
    );
    canvas.drawArc(rect, -.5, math.pi * 1.7, false, paint);
    canvas.drawArc(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width * .36,
        height: size.height * .36,
      ),
      math.pi * .3,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CandySwirlPainter oldDelegate) => false;
}

class LogoText extends StatelessWidget {
  const LogoText({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Text(
        'CANDY',
        style: TextStyle(
          fontSize: 45,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Color(0x5500337c),
              offset: Offset(0, 5),
              blurRadius: 0,
            ),
          ],
        ),
      ),
      Text(
        'SHOOTER',
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          color: Color(0xffffee78),
          shadows: [
            Shadow(
              color: Color(0x5500337c),
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
      ),
    ],
  );
}

class CandyBall extends StatelessWidget {
  const CandyBall({super.key, required this.color, required this.size});

  final CandyColor color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(color.color, Colors.white, .3)!, color.color],
      ),
      border: Border.all(color: Colors.white, width: math.max(1, size * .045)),
      boxShadow: [
        BoxShadow(
          color: color.color.withValues(alpha: .35),
          offset: const Offset(0, 3),
          blurRadius: 0,
        ),
      ],
    ),
    child: CustomPaint(
      size: Size.square(size * .52),
      painter: CandyMarkPainter(color),
    ),
  );
}

class PopCandyEffect extends StatelessWidget {
  const PopCandyEffect({
    super.key,
    required this.effect,
    required this.animation,
  });

  final PopEffect effect;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, __) {
      final progress = Curves.easeOut.transform(animation.value);
      final fade = (1 - progress).clamp(0.0, 1.0);
      final burstRadius = effect.size * (.25 + progress * .95);
      return SizedBox(
        width: effect.size,
        height: effect.size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: fade,
              child: Transform.scale(
                scale: 1 + progress * .45,
                child: CandyBall(color: effect.color, size: effect.size),
              ),
            ),
            Container(
              width: effect.size * (.55 + progress * 1.25),
              height: effect.size * (.55 + progress * 1.25),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: fade * .9),
                  width: 2.5,
                ),
              ),
            ),
            for (var index = 0; index < 7; index++)
              Positioned(
                left:
                    effect.size / 2 +
                    math.cos(index * math.pi * 2 / 7) * burstRadius -
                    3,
                top:
                    effect.size / 2 +
                    math.sin(index * math.pi * 2 / 7) * burstRadius -
                    3,
                child: Opacity(
                  opacity: fade,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 9 + progress * 5,
                    color: index.isEven
                        ? Colors.white
                        : const Color(0xffffee85),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class CandyMarkPainter extends CustomPainter {
  const CandyMarkPainter(this.color);

  final CandyColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .9);
    final center = size.center(Offset.zero);
    switch (color) {
      case CandyColor.strawberry:
        final heart = Path()
          ..moveTo(center.dx, size.height * .88)
          ..cubicTo(
            -size.width * .1,
            size.height * .56,
            size.width * .04,
            size.height * .08,
            center.dx,
            size.height * .35,
          )
          ..cubicTo(
            size.width * .96,
            size.height * .08,
            size.width * 1.1,
            size.height * .56,
            center.dx,
            size.height * .88,
          )
          ..close();
        canvas.drawPath(heart, paint);
      case CandyColor.lemon:
        final star = Path();
        for (var point = 0; point < 8; point++) {
          final radius = point.isEven ? size.width * .48 : size.width * .2;
          final angle = -math.pi / 2 + point * math.pi / 4;
          final position =
              center +
              Offset(math.cos(angle) * radius, math.sin(angle) * radius);
          if (point == 0) {
            star.moveTo(position.dx, position.dy);
          } else {
            star.lineTo(position.dx, position.dy);
          }
        }
        star.close();
        canvas.drawPath(star, paint);
      case CandyColor.mint:
        canvas.drawCircle(center, size.width * .28, paint);
        canvas.drawCircle(
          center,
          size.width * .1,
          Paint()..color = color.color,
        );
      case CandyColor.blueberry:
        final diamond = Path()
          ..moveTo(center.dx, size.height * .05)
          ..lineTo(size.width * .95, center.dy)
          ..lineTo(center.dx, size.height * .95)
          ..lineTo(size.width * .05, center.dy)
          ..close();
        canvas.drawPath(diamond, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CandyMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 235,
    height: 62,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.play_arrow_rounded, size: 27),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xfff65080),
        foregroundColor: Colors.white,
        elevation: 5,
        shadowColor: const Color(0xffa62f59),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    ),
  );
}

class PulseButton extends StatefulWidget {
  const PulseButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) => Transform.scale(
      scale: 1 + controller.value * .035,
      child: PrimaryButton(label: widget.label, onTap: widget.onTap),
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class RoundIcon extends StatelessWidget {
  const RoundIcon(this.icon, this.onTap, {super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xffffbbcf), width: 2),
      ),
      child: Icon(icon, color: const Color(0xfff65371)),
    ),
  );
}

class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffffd25b), width: 2),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.monetization_on_rounded,
          color: Color(0xffffb725),
          size: 19,
        ),
        const SizedBox(width: 4),
        Text(
          '$coins',
          style: const TextStyle(
            color: Color(0xff9d6a19),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class MiniNav extends StatelessWidget {
  const MiniNav({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffffd7b7), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330a5780),
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xfff65b7d)),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff6d506d),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 8, 15, 14),
    child: Row(
      children: [
        RoundIcon(Icons.arrow_back_rounded, onBack),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Color(0x4400408a), offset: Offset(0, 3))],
            ),
          ),
        ),
        trailing ?? const SizedBox(width: 45),
      ],
    ),
  );
}

class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.stars,
    required this.size,
    this.activeColor = const Color(0xffffbc32),
  });

  final int stars;
  final double size;
  final Color activeColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List<Widget>.generate(
      3,
      (index) => Icon(
        index < stars ? Icons.star_rounded : Icons.star_outline_rounded,
        color: index < stars ? activeColor : activeColor.withValues(alpha: .45),
        size: size,
      ),
    ),
  );
}

class LevelBubble extends StatelessWidget {
  const LevelBubble({
    super.key,
    required this.number,
    required this.stars,
    required this.locked,
    required this.current,
    this.onTap,
  });

  final int number;
  final int stars;
  final bool locked;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(40),
    child: Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: locked
            ? const Color(0xff9aa2bb)
            : current
            ? const Color(0xffffd34b)
            : const Color(0xffff83ac),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff573773).withValues(alpha: .4),
            offset: const Offset(0, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            locked ? Icons.lock_rounded : Icons.star_rounded,
            color: Colors.white,
            size: locked ? 25 : 16,
          ),
          Text(
            '$number',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (!locked)
            StarRow(stars: stars, size: 11, activeColor: Colors.white),
        ],
      ),
    ),
  );
}

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xfffcfaff),
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33003583),
          offset: Offset(0, 7),
          blurRadius: 0,
        ),
      ],
    ),
    child: child,
  );
}

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    value: value,
    onChanged: onChanged,
  );
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({
    super.key,
    required this.name,
    required this.color,
    required this.unlocked,
  });

  final String name;
  final CandyColor color;
  final bool unlocked;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ColorFiltered(
          colorFilter: unlocked
              ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
              : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
          child: CandyBall(color: color, size: 65),
        ),
        const SizedBox(height: 8),
        Text(
          unlocked ? name : 'Locked',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        if (!unlocked) const Icon(Icons.lock_rounded, size: 15),
      ],
    ),
  );
}
