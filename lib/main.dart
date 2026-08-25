import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'auth_screen.dart';
import 'data/levels.dart';
import 'data/chapters.dart';
import 'models/game_models.dart';
import 'services/auth_service.dart';
import 'services/cloud_progress_service.dart';
import 'services/leaderboard_service.dart';
import 'services/progress_service.dart';
import 'services/sound_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CandyShooterApp());
}

class LuckySpinReward {
  const LuckySpinReward({
    required this.label,
    required this.index,
    required this.segmentCount,
  });

  final String label;
  final int index;
  final int segmentCount;
}

/// A wheel segment. The wheel is rebuilt from the player's current level so
/// it never awards a power-up before that power-up has been introduced.
class LuckySpinPrize {
  const LuckySpinPrize({
    required this.label,
    required this.wheelLabel,
    required this.icon,
    this.booster,
    this.coins = 0,
    this.isMystery = false,
  });

  final String label;
  final String wheelLabel;
  final IconData icon;
  final BoosterType? booster;
  final int coins;
  final bool isMystery;
}

class AppModel extends ChangeNotifier {
  AppModel() {
    _authSubscription = auth.authState.listen((_) => _onAuthChanged());
    _load();
  }

  final _store = ProgressService();
  final auth = AuthService();
  final leaderboard = LeaderboardService();
  StreamSubscription? _authSubscription;
  int unlocked = 1;
  int coins = 125;
  List<int> stars = List.filled(levels.length, 0);
  List<int> scores = List.filled(levels.length, 0);
  bool sound = true;
  bool music = true;
  bool haptics = true;
  int bombBoosters = 0;
  int rainbowBoosters = 0;
  int lightningBoosters = 0;
  int colorBlastBoosters = 0;
  int rocketBoosters = 0;
  int goldenAimBoosters = 0;
  int megaBombBoosters = 0;
  int extraSwapBoosters = 0;
  Set<int> claimedChapterRewards = <int>{};
  bool seenNewRowTutorial = false;
  String lastLuckySpin = '';
  bool ready = false;
  bool _loadingCloudProgress = false;
  bool _hasSignedInSession = false;

  Future<void> _load() async {
    final started = DateTime.now();
    try {
      // Guest gameplay is intentionally temporary. Preferences still remain on
      // the device, while levels, coins and boosters restart on the next app
      // launch unless the player signs in.
      if (auth.currentUser == null) await _store.clearGuestProgress();
      final saved = await _store.load();
      unlocked = (saved['unlocked'] as int? ?? 1).clamp(1, levels.length);
      coins = math.max(0, saved['coins'] as int? ?? 125);
      stars = _normaliseScores(saved['stars']);
      scores = _normaliseScores(saved['scores']);
      sound = saved['sound'] as bool? ?? true;
      music = saved['music'] as bool? ?? true;
      haptics = saved['haptics'] as bool? ?? true;
      bombBoosters = math.max(0, saved['bombBoosters'] as int? ?? 0);
      rainbowBoosters = math.max(0, saved['rainbowBoosters'] as int? ?? 0);
      lightningBoosters = math.max(0, saved['lightningBoosters'] as int? ?? 0);
      colorBlastBoosters = math.max(
        0,
        saved['colorBlastBoosters'] as int? ?? 0,
      );
      rocketBoosters = math.max(0, saved['rocketBoosters'] as int? ?? 0);
      goldenAimBoosters = math.max(0, saved['goldenAimBoosters'] as int? ?? 0);
      megaBombBoosters = math.max(0, saved['megaBombBoosters'] as int? ?? 0);
      extraSwapBoosters = math.max(0, saved['extraSwapBoosters'] as int? ?? 0);
      claimedChapterRewards =
          (saved['claimedChapterRewards'] as List? ?? const [])
              .map((value) => int.tryParse('$value'))
              .whereType<int>()
              .toSet();
      seenNewRowTutorial = saved['seenNewRowTutorial'] as bool? ?? false;
      lastLuckySpin = saved['lastLuckySpin'] as String? ?? '';
    } catch (_) {
      // Invalid local data falls back to a fresh, playable profile.
    }
    final remaining =
        const Duration(milliseconds: 750) - DateTime.now().difference(started);
    if (!remaining.isNegative) await Future<void>.delayed(remaining);
    ready = true;
    notifyListeners();
    _onAuthChanged();
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

  Future<void> _save() async {
    await _saveLocalProgress();
    _saveCloudProgress();
  }

  Future<void> _saveLocalProgress() => _store.save(
    unlocked: unlocked,
    coins: coins,
    stars: stars,
    scores: scores,
    sound: sound,
    music: music,
    haptics: haptics,
    bombBoosters: bombBoosters,
    rainbowBoosters: rainbowBoosters,
    lightningBoosters: lightningBoosters,
    colorBlastBoosters: colorBlastBoosters,
    rocketBoosters: rocketBoosters,
    goldenAimBoosters: goldenAimBoosters,
    megaBombBoosters: megaBombBoosters,
    extraSwapBoosters: extraSwapBoosters,
    claimedChapterRewards: claimedChapterRewards.toList(),
    seenNewRowTutorial: seenNewRowTutorial,
    lastLuckySpin: lastLuckySpin,
  );

  Map<String, Object> _cloudProgressSnapshot() {
    final user = auth.currentUser;
    return {
      'displayName':
          (user?.userMetadata?['display_name'] as String?)?.trim().isNotEmpty ==
              true
          ? (user!.userMetadata!['display_name'] as String).trim()
          : (user?.email?.split('@').first ?? 'Candy Player'),
      'email': user?.email ?? '',
      'unlocked': unlocked,
      'coins': coins,
      'stars': stars,
      'scores': scores,
      'sound': sound,
      'music': music,
      'haptics': haptics,
      'bombBoosters': bombBoosters,
      'rainbowBoosters': rainbowBoosters,
      'lightningBoosters': lightningBoosters,
      'colorBlastBoosters': colorBlastBoosters,
      'rocketBoosters': rocketBoosters,
      'goldenAimBoosters': goldenAimBoosters,
      'megaBombBoosters': megaBombBoosters,
      'extraSwapBoosters': extraSwapBoosters,
      'claimedChapterRewards': claimedChapterRewards.toList(),
      'seenNewRowTutorial': seenNewRowTutorial,
      'lastLuckySpin': lastLuckySpin,
    };
  }

  void _onAuthChanged() {
    if (!ready) return;
    final user = auth.currentUser;
    if (user != null) {
      _hasSignedInSession = true;
      _loadCloudProgress(user.id);
    } else if (_hasSignedInSession) {
      _hasSignedInSession = false;
      _startFreshGuestSession();
    }
  }

  Future<void> _startFreshGuestSession() async {
    await _store.clearGuestProgress();
    _applyFreshProgress();
    notifyListeners();
  }

  void _applyFreshProgress() {
    unlocked = 1;
    coins = 125;
    stars = List.filled(levels.length, 0);
    scores = List.filled(levels.length, 0);
    bombBoosters = rainbowBoosters = 0;
    lightningBoosters = colorBlastBoosters = rocketBoosters = 0;
    goldenAimBoosters = megaBombBoosters = 0;
    extraSwapBoosters = 0;
    claimedChapterRewards.clear();
    seenNewRowTutorial = false;
    lastLuckySpin = '';
  }

  Future<void> _loadCloudProgress(String uid) async {
    if (_loadingCloudProgress) return;
    _loadingCloudProgress = true;
    final cloud = CloudProgressService(uid);
    try {
      final saved = await cloud.load();
      // The user may have logged out while their cloud save was loading.
      if (auth.currentUser?.id != uid) return;
      if (saved == null) {
        // A new account starts with its own clean progress. It must not inherit
        // coins, boosters, or levels from the temporary guest session.
        _applyFreshProgress();
        await _saveLocalProgress();
        await cloud.save(_cloudProgressSnapshot());
        notifyListeners();
        return;
      }
      _applyCloudProgress(saved);
      await _saveLocalProgress();
      await cloud.save(_cloudProgressSnapshot());
      notifyListeners();
    } catch (_) {
      // The game remains fully playable if the device is temporarily offline.
    } finally {
      _loadingCloudProgress = false;
    }
  }

  void _applyCloudProgress(Map<String, Object> saved) {
    unlocked = ((saved['unlocked'] as num?)?.toInt() ?? 1).clamp(
      1,
      levels.length,
    );
    coins = math.max(0, (saved['coins'] as num?)?.toInt() ?? 125);
    stars = _normaliseScores(saved['stars']);
    scores = _normaliseScores(saved['scores']);
    sound = saved['sound'] as bool? ?? true;
    music = saved['music'] as bool? ?? true;
    haptics = saved['haptics'] as bool? ?? true;
    bombBoosters = math.max(0, (saved['bombBoosters'] as num?)?.toInt() ?? 0);
    rainbowBoosters = math.max(
      0,
      (saved['rainbowBoosters'] as num?)?.toInt() ?? 0,
    );
    lightningBoosters = math.max(
      0,
      (saved['lightningBoosters'] as num?)?.toInt() ?? 0,
    );
    colorBlastBoosters = math.max(
      0,
      (saved['colorBlastBoosters'] as num?)?.toInt() ?? 0,
    );
    rocketBoosters = math.max(
      0,
      (saved['rocketBoosters'] as num?)?.toInt() ?? 0,
    );
    goldenAimBoosters = math.max(
      0,
      (saved['goldenAimBoosters'] as num?)?.toInt() ?? 0,
    );
    megaBombBoosters = math.max(
      0,
      (saved['megaBombBoosters'] as num?)?.toInt() ?? 0,
    );
    extraSwapBoosters = math.max(
      0,
      (saved['extraSwapBoosters'] as num?)?.toInt() ?? 0,
    );
    claimedChapterRewards =
        (saved['claimedChapterRewards'] as List? ?? const [])
            .map((value) => int.tryParse('$value'))
            .whereType<int>()
            .toSet();
    seenNewRowTutorial = saved['seenNewRowTutorial'] as bool? ?? false;
    lastLuckySpin = saved['lastLuckySpin'] as String? ?? '';
  }

  void _saveCloudProgress() {
    final user = auth.currentUser;
    if (user == null || _loadingCloudProgress) return;
    CloudProgressService(
      user.id,
    ).save(_cloudProgressSnapshot()).catchError((_) {});
  }

  int boosterCount(BoosterType type) => switch (type) {
    BoosterType.bomb => bombBoosters,
    BoosterType.rainbow => rainbowBoosters,
    BoosterType.lightning => lightningBoosters,
    BoosterType.colorBlast => colorBlastBoosters,
    BoosterType.rocket => rocketBoosters,
    BoosterType.goldenAim => goldenAimBoosters,
    BoosterType.megaBomb => megaBombBoosters,
    BoosterType.extraSwap => extraSwapBoosters,
  };

  /// The player meets these boosters gradually, so Lucky Spin, the shop and
  /// the in-game tray all follow the same progression rules.
  int boosterUnlockLevel(BoosterType type) => switch (type) {
    BoosterType.bomb || BoosterType.extraSwap => 1,
    BoosterType.rainbow => 6,
    BoosterType.lightning => 11,
    BoosterType.goldenAim => 1,
    BoosterType.colorBlast => 21,
    BoosterType.rocket => 31,
    BoosterType.megaBomb => 41,
  };

  bool isBoosterUnlocked(BoosterType type) =>
      unlocked >= boosterUnlockLevel(type);

  bool isChapterUnlocked(ChapterConfig chapter) =>
      chapter.id == 1 || claimedChapterRewards.contains(chapter.id - 1);

  Future<ChapterConfig?> finishLevel(
    int level,
    int score,
    int earnedStars,
  ) async {
    final index = level - 1;
    stars[index] = math.max(stars[index], earnedStars.clamp(1, 3));
    scores[index] = math.max(scores[index], score);
    final chapter = chapterForLevel(level);
    final isChapterEnd = level == chapter.endLevel;
    if (!isChapterEnd || claimedChapterRewards.contains(chapter.id)) {
      unlocked = math.max(unlocked, math.min(levels.length, level + 1));
    }
    coins += 15 + earnedStars * 10;
    await _save();
    notifyListeners();
    _submitLeaderboardResult(
      score: score,
      levelReached: level,
      totalStars: stars.fold<int>(0, (sum, stars) => sum + stars),
    );
    return isChapterEnd && !claimedChapterRewards.contains(chapter.id)
        ? chapter
        : null;
  }

  Future<void> _submitLeaderboardResult({
    required int score,
    required int levelReached,
    required int totalStars,
  }) async {
    if (auth.currentUser == null) return;
    try {
      await leaderboard.submitLeaderboardResult(
        score: score,
        levelReached: levelReached,
        totalStars: totalStars,
      );
    } catch (_) {
      // A finished level is never blocked by a temporary leaderboard failure.
    }
  }

  Future<void> claimChapterReward(ChapterConfig chapter) async {
    if (claimedChapterRewards.contains(chapter.id)) return;
    claimedChapterRewards.add(chapter.id);
    coins += chapter.coinReward;
    switch (chapter.reward) {
      case BoosterType.bomb:
        bombBoosters += chapter.rewardAmount;
      case BoosterType.rainbow:
        rainbowBoosters += chapter.rewardAmount;
      case BoosterType.lightning:
        lightningBoosters += chapter.rewardAmount;
      case BoosterType.colorBlast:
        colorBlastBoosters += chapter.rewardAmount;
      case BoosterType.rocket:
        rocketBoosters += chapter.rewardAmount;
      case BoosterType.goldenAim:
        goldenAimBoosters += chapter.rewardAmount;
      case BoosterType.megaBomb:
        megaBombBoosters += chapter.rewardAmount;
      case BoosterType.extraSwap:
        extraSwapBoosters += chapter.rewardAmount;
    }
    if (chapter.endLevel < levels.length) {
      unlocked = math.max(unlocked, chapter.endLevel + 1);
    }
    await _save();
    notifyListeners();
  }

  Future<bool> useBooster(BoosterType type) async {
    if (!isBoosterUnlocked(type) || boosterCount(type) == 0) return false;
    switch (type) {
      case BoosterType.bomb:
        bombBoosters--;
      case BoosterType.rainbow:
        rainbowBoosters--;
      case BoosterType.lightning:
        lightningBoosters--;
      case BoosterType.colorBlast:
        colorBlastBoosters--;
      case BoosterType.rocket:
        rocketBoosters--;
      case BoosterType.goldenAim:
        goldenAimBoosters--;
      case BoosterType.megaBomb:
        megaBombBoosters--;
      case BoosterType.extraSwap:
        extraSwapBoosters--;
    }
    await _save();
    notifyListeners();
    return true;
  }

  Future<bool> buyBooster(BoosterType type, int cost) async {
    if (!isBoosterUnlocked(type) || cost <= 0 || coins < cost) return false;
    coins -= cost;
    switch (type) {
      case BoosterType.bomb:
        bombBoosters++;
      case BoosterType.rainbow:
        rainbowBoosters++;
      case BoosterType.lightning:
        lightningBoosters++;
      case BoosterType.colorBlast:
        colorBlastBoosters++;
      case BoosterType.rocket:
        rocketBoosters++;
      case BoosterType.goldenAim:
        goldenAimBoosters++;
      case BoosterType.megaBomb:
        megaBombBoosters++;
      case BoosterType.extraSwap:
        extraSwapBoosters++;
    }
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> grantMysteryReward({
    int coinsWon = 0,
    BoosterType? booster,
  }) async {
    coins += math.max(0, coinsWon);
    switch (booster) {
      case BoosterType.bomb:
        bombBoosters++;
      case BoosterType.rainbow:
        rainbowBoosters++;
      case BoosterType.lightning:
        lightningBoosters++;
      case BoosterType.colorBlast:
        colorBlastBoosters++;
      case BoosterType.rocket:
        rocketBoosters++;
      case BoosterType.goldenAim:
        goldenAimBoosters++;
      case BoosterType.megaBomb:
        megaBombBoosters++;
      case BoosterType.extraSwap:
        extraSwapBoosters++;
      case null:
        break;
    }
    await _save();
    notifyListeners();
  }

  Future<void> markNewRowTutorialSeen() async {
    seenNewRowTutorial = true;
    await _save();
    notifyListeners();
  }

  bool get canLuckySpin => lastLuckySpin != _today;
  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  static const _coins50 = LuckySpinPrize(
    label: '50 Coins',
    wheelLabel: '50\nCOINS',
    icon: Icons.monetization_on_rounded,
    coins: 50,
  );
  static const _coins100 = LuckySpinPrize(
    label: '100 Coins',
    wheelLabel: '100\nCOINS',
    icon: Icons.monetization_on_rounded,
    coins: 100,
  );
  static const _bombPrize = LuckySpinPrize(
    label: 'Bomb',
    wheelLabel: 'BOMB',
    icon: Icons.warning_amber_rounded,
    booster: BoosterType.bomb,
  );
  static const _rainbowPrize = LuckySpinPrize(
    label: 'Rainbow',
    wheelLabel: 'RAINBOW',
    icon: Icons.brightness_5_rounded,
    booster: BoosterType.rainbow,
  );
  static const _lightningPrize = LuckySpinPrize(
    label: 'Lightning',
    wheelLabel: 'LIGHTNING',
    icon: Icons.bolt_rounded,
    booster: BoosterType.lightning,
  );
  static const _colorBlastPrize = LuckySpinPrize(
    label: 'Color Blast',
    wheelLabel: 'COLOR\nBLAST',
    icon: Icons.color_lens_rounded,
    booster: BoosterType.colorBlast,
  );
  static const _rocketPrize = LuckySpinPrize(
    label: 'Rocket',
    wheelLabel: 'ROCKET',
    icon: Icons.rocket_launch_rounded,
    booster: BoosterType.rocket,
  );
  static const _goldenAimPrize = LuckySpinPrize(
    label: 'Golden Aim',
    wheelLabel: 'GOLDEN\nAIM',
    icon: Icons.gps_fixed_rounded,
    booster: BoosterType.goldenAim,
  );
  static const _mysteryPrize = LuckySpinPrize(
    label: 'Mystery',
    wheelLabel: 'MYSTERY',
    icon: Icons.card_giftcard_rounded,
    isMystery: true,
  );

  /// Exactly six usable slices are shown. New rewards replace repeat coin
  /// slices as the player reaches the levels where they are explained.
  List<LuckySpinPrize> get luckySpinPrizes {
    if (unlocked >= 51) {
      return const [
        _coins100,
        _bombPrize,
        _rainbowPrize,
        _lightningPrize,
        _rocketPrize,
        _mysteryPrize,
      ];
    }
    if (unlocked >= 31) {
      return const [
        _coins100,
        _bombPrize,
        _rainbowPrize,
        _lightningPrize,
        _colorBlastPrize,
        _rocketPrize,
      ];
    }
    if (unlocked >= 21) {
      return const [
        _coins50,
        _coins100,
        _bombPrize,
        _rainbowPrize,
        _lightningPrize,
        _colorBlastPrize,
      ];
    }
    if (unlocked >= 11) {
      return const [
        _coins50,
        _coins100,
        _bombPrize,
        _goldenAimPrize,
        _rainbowPrize,
        _lightningPrize,
      ];
    }
    if (unlocked >= 6) {
      return const [
        _coins50,
        _coins100,
        _bombPrize,
        _goldenAimPrize,
        _rainbowPrize,
      ];
    }
    return const [_coins50, _coins100, _bombPrize, _goldenAimPrize];
  }

  void _awardLuckyPrize(LuckySpinPrize prize) {
    coins += prize.coins;
    switch (prize.booster) {
      case BoosterType.bomb:
        bombBoosters++;
      case BoosterType.rainbow:
        rainbowBoosters++;
      case BoosterType.lightning:
        lightningBoosters++;
      case BoosterType.colorBlast:
        colorBlastBoosters++;
      case BoosterType.rocket:
        rocketBoosters++;
      case BoosterType.goldenAim:
        goldenAimBoosters++;
      case BoosterType.megaBomb:
        megaBombBoosters++;
      case BoosterType.extraSwap:
        extraSwapBoosters++;
      case null:
        break;
    }
  }

  Future<LuckySpinReward?> luckySpin() async {
    if (!canLuckySpin) return null;
    final prizes = luckySpinPrizes;
    final index = math.Random().nextInt(prizes.length);
    final prize = prizes[index];
    var label = prize.label;
    if (prize.isMystery) {
      // Mystery only arrives after level 50. It now genuinely gives a random
      // useful reward instead of always silently becoming 75 coins.
      final mysteryOptions = <LuckySpinPrize>[
        _coins50,
        _coins100,
        _bombPrize,
        _rainbowPrize,
        _lightningPrize,
        _colorBlastPrize,
        _rocketPrize,
      ];
      final mysteryReward =
          mysteryOptions[math.Random().nextInt(mysteryOptions.length)];
      _awardLuckyPrize(mysteryReward);
      label = 'Mystery: ${mysteryReward.label}';
    } else {
      _awardLuckyPrize(prize);
    }
    lastLuckySpin = _today;
    await _save();
    notifyListeners();
    return LuckySpinReward(
      label: label,
      index: index,
      segmentCount: prizes.length,
    );
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
    bombBoosters = rainbowBoosters = 0;
    lightningBoosters = colorBlastBoosters = rocketBoosters = 0;
    goldenAimBoosters = megaBombBoosters = 0;
    extraSwapBoosters = 0;
    claimedChapterRewards.clear();
    seenNewRowTutorial = false;
    lastLuckySpin = '';
    await _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
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
        splashFactory: InkSparkle.splashFactory,
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 140),
            overlayColor: WidgetStatePropertyAll(
              const Color(0xffffc6dc).withValues(alpha: .34),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 140),
            overlayColor: WidgetStatePropertyAll(
              const Color(0xffffc6dc).withValues(alpha: .28),
            ),
          ),
        ),
      ),
      home: model.ready ? AppShell(model: model) : const SplashScreen(),
    ),
  );
}

enum AppPage { home, map, game, settings, collection, shop, leaderboard }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.model});

  final AppModel model;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppPage page = AppPage.home;
  int level = 1;
  int mapChapter = 1;

  void go(AppPage next, {int? selectedLevel}) {
    setState(() {
      page = next;
      if (selectedLevel != null) level = selectedLevel;
      if (next == AppPage.map) {
        mapChapter = chapterForLevel(widget.model.unlocked).id;
      }
    });
  }

  Widget _currentPage() => switch (page) {
    AppPage.home => HomeScreen(model: widget.model, go: go),
    AppPage.map => LevelMapScreen(
      model: widget.model,
      go: go,
      chapter: mapChapter,
      onChapter: (chapter) => setState(() => mapChapter = chapter),
    ),
    AppPage.settings => SettingsScreen(
      model: widget.model,
      onBack: () => go(AppPage.home),
    ),
    AppPage.collection => CollectionScreen(
      model: widget.model,
      onBack: () => go(AppPage.home),
    ),
    AppPage.shop => BoosterShopScreen(
      model: widget.model,
      onBack: () => go(AppPage.home),
    ),
    AppPage.leaderboard => LeaderboardScreen(
      model: widget.model,
      onBack: () => go(AppPage.home),
      onSignIn: () => go(AppPage.home),
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

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 180),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.025, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: KeyedSubtree(
      key: ValueKey('${page.name}-${page == AppPage.game ? level : ''}'),
      child: _currentPage(),
    ),
  );
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
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                    child: Row(
                      children: [
                        RoundIcon(
                          Icons.settings_rounded,
                          () => go(AppPage.settings),
                        ),
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
                        icon: Icons.card_giftcard_rounded,
                        label: 'Rewards',
                        onTap: () => go(AppPage.collection),
                      ),
                      MiniNav(
                        icon: Icons.storefront_rounded,
                        label: 'Shop',
                        onTap: () => go(AppPage.shop),
                      ),
                      MiniNav(
                        icon: Icons.emoji_events_rounded,
                        label: 'Ranks',
                        onTap: () => go(AppPage.leaderboard),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HomeProgressCard(
                    level: model.unlocked,
                    stars: model.stars.fold<int>(
                      0,
                      (sum, value) => sum + value,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class LevelMapScreen extends StatelessWidget {
  const LevelMapScreen({
    super.key,
    required this.model,
    required this.go,
    required this.chapter,
    required this.onChapter,
  });

  final AppModel model;
  final void Function(AppPage, {int? selectedLevel}) go;
  final int chapter;
  final ValueChanged<int> onChapter;

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
          WorldRibbon(
            'WORLD $chapter • ${chapters[chapter - 1].name.toUpperCase()}',
          ),
          ChapterProgressCard(
            stars: model.stars
                .skip((chapter - 1) * 10)
                .take(10)
                .fold<int>(0, (sum, stars) => sum + stars),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: WorldPathMap(
              chapter: chapters[chapter - 1],
              unlocked: model.unlocked,
              stars: model.stars,
              onLevelTap: (number) => go(AppPage.game, selectedLevel: number),
              onNavigate: go,
              onDailySpin: () => showDialog<void>(
                context: context,
                builder: (_) => LuckySpinDialog(model: model),
              ),
            ),
          ),
          MapBottomNavigation(go: go),
        ],
      ),
    ),
  );
}

class ChapterProgressCard extends StatelessWidget {
  const ChapterProgressCard({super.key, required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(24, 14, 24, 2),
    padding: const EdgeInsets.fromLTRB(17, 14, 17, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffffdfb4), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33003583),
          offset: Offset(0, 5),
          blurRadius: 0,
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'CHAPTER PROGRESS',
                style: TextStyle(
                  color: Color(0xff573773),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$stars / 30',
              style: const TextStyle(
                color: Color(0xfff6538a),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.star_rounded, color: Color(0xffffcb3d), size: 26),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: LinearProgressIndicator(
            value: stars / 30,
            minHeight: 16,
            backgroundColor: const Color(0xffefeaf1),
            valueColor: const AlwaysStoppedAnimation(Color(0xfff55f8a)),
          ),
        ),
      ],
    ),
  );
}

class ChapterTab extends StatelessWidget {
  const ChapterTab({
    super.key,
    required this.chapter,
    required this.selected,
    required this.locked,
    this.onTap,
  });

  final ChapterConfig chapter;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      width: 145,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xffffe7ef)
            : Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? const Color(0xfff6538a) : const Color(0xffddd4d5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Text(
            locked
                ? '🔒'
                : selected
                ? '🍬'
                : '🗺️',
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              chapter.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: locked
                    ? const Color(0xff938b8b)
                    : const Color(0xff6d506d),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
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

class WorldPathMap extends StatefulWidget {
  const WorldPathMap({
    super.key,
    required this.chapter,
    required this.unlocked,
    required this.stars,
    required this.onLevelTap,
    required this.onNavigate,
    required this.onDailySpin,
  });

  final int unlocked;
  final ChapterConfig chapter;
  final List<int> stars;
  final ValueChanged<int> onLevelTap;
  final void Function(AppPage, {int? selectedLevel}) onNavigate;
  final VoidCallback onDailySpin;

  @override
  State<WorldPathMap> createState() => _WorldPathMapState();
}

class _WorldPathMapState extends State<WorldPathMap> {
  final ScrollController _scrollController = ScrollController();
  bool _positioned = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final width = constraints.maxWidth;
      final firstVisibleLevel = math.max(1, widget.chapter.startLevel - 10);
      final visibleLevels = levels
          .skip(firstVisibleLevel - 1)
          .take(20)
          .toList();
      final mapHeight = math.max(
        constraints.maxHeight + 80,
        visibleLevels.length * 112.0 + 220,
      );
      final points = List<Offset>.generate(visibleLevels.length, (index) {
        // Level 1 is intentionally at the bottom.  Each following level
        // climbs the candy path toward the top of the map.
        final x = width * .61 + math.sin(index * 1.28 + .45) * width * .21;
        return Offset(
          x.clamp(82.0, width - 48.0),
          mapHeight - 88 - index * 112.0,
        );
      });
      final currentIndex = visibleLevels.indexWhere(
        (level) => level.id == widget.unlocked,
      );
      if (!_positioned && currentIndex >= 0) {
        _positioned = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients || !mounted) return;
          final target = (points[currentIndex].dy - constraints.maxHeight * .64)
              .clamp(0.0, _scrollController.position.maxScrollExtent);
          _scrollController.jumpTo(target);
        });
      }
      return Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 20),
            child: SizedBox(
              height: math.max(mapHeight, constraints.maxHeight),
              width: width,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: WorldPathPainter(points)),
                  ),
                  for (var index = 0; index < visibleLevels.length; index++)
                    Positioned(
                      left: points[index].dx - 37,
                      top: points[index].dy - 37,
                      child: LevelBubble(
                        number: visibleLevels[index].id,
                        stars: widget.stars[visibleLevels[index].id - 1],
                        locked: visibleLevels[index].id > widget.unlocked,
                        current: visibleLevels[index].id == widget.unlocked,
                        onTap: visibleLevels[index].id <= widget.unlocked
                            ? () => widget.onLevelTap(visibleLevels[index].id)
                            : null,
                      ),
                    ),
                  if (currentIndex >= 0)
                    Positioned(
                      left: points[currentIndex].dx > width * .58
                          ? 14
                          : width - 120,
                      top: points[currentIndex].dy - 42,
                      child: const MapNextCallout(),
                    ),
                  Positioned(
                    top: 20,
                    right: 16,
                    child: ChapterMapReward(chapter: widget.chapter),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 100,
            child: MapShortcutRail(
              onNavigate: widget.onNavigate,
              onDailySpin: widget.onDailySpin,
            ),
          ),
        ],
      );
    },
  );
}

class MapShortcutRail extends StatelessWidget {
  const MapShortcutRail({
    super.key,
    required this.onNavigate,
    required this.onDailySpin,
  });

  final void Function(AppPage, {int? selectedLevel}) onNavigate;
  final VoidCallback onDailySpin;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MapShortcutButton(
        icon: Icons.storefront_rounded,
        label: 'Shop',
        color: const Color(0xffffb43c),
        onTap: () => onNavigate(AppPage.shop),
      ),
      const SizedBox(height: 8),
      MapShortcutButton(
        icon: Icons.casino_rounded,
        label: 'Daily spin',
        color: const Color(0xff9a66d8),
        onTap: onDailySpin,
      ),
    ],
  );
}

class MapShortcutButton extends StatelessWidget {
  const MapShortcutButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: .7), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33003583),
            offset: Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff654486),
              fontSize: 9,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class MapNextCallout extends StatelessWidget {
  const MapNextCallout({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xfff6538a),
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33003583),
          offset: Offset(0, 3),
          blurRadius: 0,
        ),
      ],
    ),
    child: const Text(
      'NEXT',
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class ChapterMapReward extends StatelessWidget {
  const ChapterMapReward({super.key, required this.chapter});

  final ChapterConfig chapter;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 130),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xffffd47b), width: 2),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.card_giftcard_rounded,
          color: Color(0xffffad28),
          size: 23,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Chapter reward\n${chapter.reward.label}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff654486),
              fontSize: 9,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class MapBottomNavigation extends StatelessWidget {
  const MapBottomNavigation({super.key, required this.go});

  final void Function(AppPage, {int? selectedLevel}) go;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .93),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xffffd7ed), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33003583),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: MapBottomItem(
            icon: Icons.map_rounded,
            label: 'MAP',
            color: const Color(0xfff6538a),
            active: true,
            onTap: () => go(AppPage.map),
          ),
        ),
        Expanded(
          child: MapBottomItem(
            icon: Icons.emoji_events_rounded,
            label: 'RANKS',
            color: const Color(0xff9a66d8),
            onTap: () => go(AppPage.leaderboard),
          ),
        ),
        Expanded(
          child: MapBottomItem(
            icon: Icons.card_giftcard_rounded,
            label: 'REWARDS',
            color: const Color(0xfff3a92e),
            onTap: () => go(AppPage.collection),
          ),
        ),
      ],
    ),
  );
}

class MapBottomItem extends StatelessWidget {
  const MapBottomItem({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: .14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          Text(
            label,
            style: TextStyle(
              color: active ? color : const Color(0xff654486),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class ChapterRewardBanner extends StatelessWidget {
  const ChapterRewardBanner({super.key, required this.chapter});

  final ChapterConfig chapter;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xfff4608e),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: const Color(0xffffb1cb), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44003583),
          offset: Offset(0, 6),
          blurRadius: 0,
        ),
      ],
    ),
    child: Row(
      children: [
        const Text('🎁', style: TextStyle(fontSize: 44)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Complete this chapter\nto earn ${chapter.reward.emoji} ${chapter.reward.label} ×${chapter.rewardAmount}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
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
        Text(
          chapterForLevel(level).name,
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
  BoardGeometry(this.size, {this.gridPhase = 0})
    : worldWidth = math.min(size.width, 400),
      ballDiameter = math.min(math.min(size.width, 400) * .12, 48);

  final Size size;
  final int gridPhase;
  final double worldWidth;
  final double ballDiameter;

  double get left => (size.width - worldWidth) / 2;
  double get xStep => ballDiameter;
  double get rowStep => ballDiameter * .8660254;
  double get top => math.max(32, size.height * .075);
  double get wallLeft => left + ballDiameter / 2;
  double get wallRight => left + worldWidth - ballDiameter / 2;
  Offset get launcher => Offset(size.width / 2, size.height * .89);
  double get dangerLine => launcher.dy - ballDiameter * 3.05;

  Offset position(CandyCell cell, {int? phase}) {
    final first = size.width / 2 - 3 * xStep;
    final isOffsetRow = (cell.row + (phase ?? gridPhase)).isOdd;
    return Offset(
      first + (cell.col + (isOffsetRow ? .5 : 0)) * xStep,
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

class _ShotCollision {
  const _ShotCollision({required this.position, this.cell});

  final Offset position;
  final CandyCell? cell;
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

class DropEffect {
  const DropEffect({
    required this.position,
    required this.color,
    required this.size,
    required this.delay,
  });

  final Offset position;
  final CandyColor color;
  final double size;
  final double delay;
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
  // The result panel is rendered above the complete screen, not just inside
  // the lower playfield, so it can be genuinely centred for the player.
  bool showFullScreenResultOverlay = true;
  final List<CandyCell> board = [];
  Timer? rowTimer;
  late final Ticker _flightTicker = createTicker(_tickFlight);
  Duration? _lastFlightTick;
  Offset? _flightVelocity;
  BoardGeometry? _flightGeometry;
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
  late final AnimationController dropController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 460),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(dropEffects.clear);
        }
      });
  late final AnimationController rowController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _settleIncomingRow();
        }
      });
  late final AnimationController bombController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => bombExplosion = null);
        }
      });
  late final AnimationController rocketController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => rocketBlastY = null);
        }
      });
  CandyColor current = CandyColor.strawberry;
  CandyColor next = CandyColor.lemon;
  List<Offset> aimPath = const [];
  final List<Offset> shotTrail = [];
  final List<ShotSpark> shotSparks = [];
  final List<PopEffect> popEffects = [];
  final List<DropEffect> dropEffects = [];
  final List<CandyCell> incomingRow = [];
  // Snapshot used only to render the old board while the logical board has
  // already moved down to its new grid rows.
  final List<CandyCell> movingBoard = [];
  Offset? aimInput;
  Offset? _lastAimSample;
  Offset? _pendingAimPoint;
  BoardGeometry? _pendingAimGeometry;
  bool _aimUpdateScheduled = false;
  Offset? flight;
  CandyColor? flyingColor;
  bool flyingBomb = false;
  bool bombLaunching = false;
  bool flyingRocket = false;
  bool rocketLaunching = false;
  bool colorBlastAnimating = false;
  final Set<String> colorBlastTargets = <String>{};
  Offset? bombExplosion;
  double? rocketBlastY;
  int shots = 0;
  int score = 0;
  int cleared = 0;
  int yellowCleared = 0;
  int combo = 0;
  int rowShotCounter = 0;
  int rowsEntered = 0;
  int gridPhase = 0;
  int goldenAimShots = 0;
  int freeSwaps = 1;
  BoosterType? activeBooster;
  bool paused = false;
  bool finished = false;
  bool won = false;
  bool chapterComplete = false;
  ChapterConfig? completedChapter;
  bool rowWarning = false;
  bool rowAnimating = false;
  BoardGeometry? activeGeometry;
  String praise = 'Aim for a sweet match!';

  @override
  void initState() {
    super.initState();
    _newLevel();
    if (widget.config.newRowEnabled && !widget.model.seenNewRowTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRowTutorial());
    } else if (widget.config.challengeTitle != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showChallengeIntro(),
      );
    }
  }

  void _newLevel() {
    _stopFlightTicker();
    rowTimer?.cancel();
    rowController.stop();
    rowController.value = 0;
    bombController.stop();
    bombController.value = 0;
    board.clear();
    shots = widget.config.shots;
    score = cleared = yellowCleared = combo = 0;
    rowShotCounter = rowsEntered = gridPhase = 0;
    goldenAimShots = 0;
    freeSwaps = 1;
    activeBooster = null;
    aimPath = const [];
    shotTrail.clear();
    shotSparks.clear();
    popEffects.clear();
    dropEffects.clear();
    incomingRow.clear();
    movingBoard.clear();
    aimInput = null;
    _lastAimSample = null;
    _pendingAimPoint = null;
    _pendingAimGeometry = null;
    _aimUpdateScheduled = false;
    flight = null;
    flyingColor = null;
    flyingBomb = bombLaunching = flyingRocket = rocketLaunching = false;
    colorBlastAnimating = false;
    colorBlastTargets.clear();
    bombExplosion = null;
    rocketBlastY = null;
    rowWarning = rowAnimating = false;
    paused = finished = won = chapterComplete = false;
    completedChapter = null;
    praise = 'Aim for a sweet match!';
    final layout = widget.config.initialLayout;
    for (var row = 0; row < layout.length; row++) {
      for (var col = 0; col < layout[row].length; col++) {
        final colorIndex = layout[row][col];
        if (colorIndex == null) continue;
        board.add(
          CandyCell(
            row,
            col,
            widget.config.colors[colorIndex % widget.config.colors.length],
          ),
        );
      }
    }
    // Bomb candies are board objects, not normal colour-match candies. Their
    // exact cells remain part of the same staggered grid and can be triggered
    // by a bomb blast later in the level.
    for (
      var index = 0;
      index < widget.config.bombCount && board.isNotEmpty;
      index++
    ) {
      final candidates = board.where((cell) => !cell.isBomb).toList();
      if (candidates.isEmpty) break;
      final selected = candidates[random.nextInt(candidates.length)];
      board
        ..remove(selected)
        ..add(
          CandyCell(
            selected.row,
            selected.col,
            selected.color,
            isMystery: selected.isMystery,
            isBomb: true,
          ),
        );
    }
    if (widget.config.id >= 51 && board.isNotEmpty) {
      final candidates = board.where((cell) => cell.row >= 2).toList();
      final selected =
          (candidates.isEmpty ? board : candidates)[random.nextInt(
            candidates.isEmpty ? board.length : candidates.length,
          )];
      board
        ..remove(selected)
        ..add(
          CandyCell(
            selected.row,
            selected.col,
            selected.color,
            isMystery: true,
            isBomb: selected.isBomb,
          ),
        );
    }
    current = widget.config.colors.first;
    next = widget.config.colors[1 % widget.config.colors.length];
  }

  int _columnsForRow(int row, {int? phase}) =>
      7 - ((row + (phase ?? gridPhase)).isOdd ? 1 : 0);

  /// Returns the six logical neighbours of a cell in the staggered board.
  ///
  /// Gameplay decisions must use row/column addresses, rather than the
  /// rendered coordinates. That keeps matches and ceiling connectivity stable
  /// while the whole board is animating down after a ceiling drop.
  List<CandyCell> _neighbors(CandyCell cell) {
    final offsetRow = (cell.row + gridPhase).isOdd;
    final diagonalColumn = offsetRow ? cell.col + 1 : cell.col - 1;
    final neighborKeys = <String>{
      '${cell.row}:${cell.col - 1}',
      '${cell.row}:${cell.col + 1}',
      '${cell.row - 1}:${cell.col}',
      '${cell.row - 1}:$diagonalColumn',
      '${cell.row + 1}:${cell.col}',
      '${cell.row + 1}:$diagonalColumn',
    };
    return board
        .where((other) => other != cell && neighborKeys.contains(other.key))
        .toList(growable: false);
  }

  Offset? _velocity(Offset local, BoardGeometry g) {
    var target = local;
    if (target.dy > g.launcher.dy - 35) {
      target = Offset(target.dx, g.size.height * .35);
    }
    final direction = target - g.launcher;
    if (direction.dy >= -12 || direction.distance == 0) return null;
    // Keep the physical path identical, but make the actual launched candy
    // feel responsive on a tap. Exact segment collision checks still prevent
    // it from skipping past a candy at this higher speed.
    return direction / direction.distance * 10;
  }

  /// Finds the first physical contact along one projectile movement segment.
  /// The returned point is a candy-centre collision point, not an overshot
  /// timer position, so aiming and snapping use the same geometry.
  _ShotCollision? _firstCollision(Offset start, Offset end, BoardGeometry g) {
    final segment = end - start;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared == 0) return null;

    _ShotCollision? first;
    var firstT = double.infinity;
    void consider(double t, CandyCell? cell) {
      if (t < 0 || t > 1 || t >= firstT) return;
      firstT = t;
      first = _ShotCollision(position: start + segment * t, cell: cell);
    }

    // The projectile touches a board candy when the two centres are one
    // diameter apart. Solve that circle/line-segment intersection exactly.
    for (final cell in board) {
      final fromCenter = start - g.position(cell);
      final b = 2 * (fromCenter.dx * segment.dx + fromCenter.dy * segment.dy);
      final c = fromCenter.distanceSquared - g.ballDiameter * g.ballDiameter;
      final discriminant = b * b - 4 * lengthSquared * c;
      if (discriminant < 0) continue;
      final root = math.sqrt(discriminant);
      consider((-b - root) / (2 * lengthSquared), cell);
      consider((-b + root) / (2 * lengthSquared), cell);
    }

    final ceilingY = g.top - g.ballDiameter / 2;
    if (start.dy >= ceilingY && end.dy <= ceilingY) {
      consider((ceilingY - start.dy) / segment.dy, null);
    }
    return first;
  }

  List<Offset> _trajectory(Offset local, BoardGeometry g) {
    final initial = _velocity(local, g);
    if (initial == null) return const [];
    var velocity = initial;
    var point = g.launcher;
    final path = <Offset>[point];
    for (var step = 0; step < 600; step++) {
      var nextPoint = point + velocity;
      if (nextPoint.dx < g.wallLeft || nextPoint.dx > g.wallRight) {
        path.add(point);
        velocity = Offset(-velocity.dx, velocity.dy);
        nextPoint = point + velocity;
      }
      final collision = _firstCollision(point, nextPoint, g);
      if (collision != null) {
        path.add(collision.position);
        return path;
      }
      point = nextPoint;
      if (step.isEven) path.add(point);
    }
    return path;
  }

  void _updateAim(Offset point, BoardGeometry g) {
    if (finished ||
        paused ||
        rowWarning ||
        rowAnimating ||
        colorBlastAnimating ||
        bombLaunching ||
        rocketLaunching ||
        flight != null) {
      return;
    }
    aimInput = point;
    _pendingAimPoint = point;
    _pendingAimGeometry = g;
    if (_aimUpdateScheduled) return;
    _aimUpdateScheduled = true;
    // A drag can produce more pointer events than the display can draw. Keep
    // only the latest point and calculate the dotted guide once per frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aimUpdateScheduled = false;
      final sampledPoint = _pendingAimPoint;
      final sampledGeometry = _pendingAimGeometry;
      if (!mounted || sampledPoint == null || sampledGeometry == null) return;
      if (finished || paused || rowWarning || rowAnimating || flight != null) {
        return;
      }
      if (_lastAimSample != null &&
          (_lastAimSample! - sampledPoint).distanceSquared < 25) {
        return;
      }
      _lastAimSample = sampledPoint;
      setState(() {
        aimPath = _trajectory(sampledPoint, sampledGeometry);
      });
    });
  }

  void _stopFlightTicker() {
    if (_flightTicker.isActive) _flightTicker.stop();
    _lastFlightTick = null;
    _flightVelocity = null;
    _flightGeometry = null;
  }

  void _tickFlight(Duration elapsed) {
    if (!mounted) return;
    if (paused) {
      _lastFlightTick = elapsed;
      return;
    }
    final previous = flight;
    final baseVelocity = _flightVelocity;
    final g = _flightGeometry;
    final previousTick = _lastFlightTick;
    _lastFlightTick = elapsed;
    if (previous == null || baseVelocity == null || g == null) {
      _stopFlightTicker();
      return;
    }
    // The old 16ms simulation step is preserved, but it now follows the
    // device's actual frame timing. Clamp a resumed frame to avoid a visible
    // jump after an interruption.
    final frameScale = previousTick == null
        ? 1.0
        : ((elapsed - previousTick).inMicroseconds / 16000.0).clamp(.5, 2.0);
    var velocity = baseVelocity * frameScale;
    setState(() {
      shotTrail.insert(0, previous);
      if (shotTrail.length > 14) shotTrail.removeLast();
      for (final spark in shotSparks) {
        spark.position += spark.velocity * frameScale;
        spark.velocity += Offset(0, .18 * frameScale);
        spark.life -= .055 * frameScale;
      }
      shotSparks.removeWhere((spark) => spark.life <= 0);
      var point = previous + velocity;
      if (point.dx < g.wallLeft || point.dx > g.wallRight) {
        velocity = Offset(-velocity.dx, velocity.dy);
        point = previous + velocity;
      }
      final collision = _firstCollision(previous, point, g);
      if (collision != null) {
        _stopFlightTicker();
        flight = null;
        shotTrail.clear();
        final firedColor = flyingColor ?? current;
        final firedBomb = flyingBomb;
        final firedRocket = flyingRocket;
        flyingColor = null;
        flyingBomb = false;
        flyingRocket = false;
        if (firedBomb) {
          _explodeBomb(collision.position, g);
        } else if (firedRocket) {
          _explodeRocket(collision.position, g, collision.cell);
        } else {
          _attach(
            collision.position,
            g,
            firedColor,
            collided: collision.cell,
            velocity: velocity,
          );
        }
      } else {
        flight = point;
        _flightVelocity = velocity / frameScale;
      }
    });
  }

  Future<void> _swapNextCandy() async {
    if (finished ||
        paused ||
        rowWarning ||
        rowAnimating ||
        colorBlastAnimating ||
        bombLaunching ||
        rocketLaunching ||
        flight != null) {
      return;
    }
    final usingFreeSwap = freeSwaps > 0;
    if (!usingFreeSwap &&
        !await widget.model.useBooster(BoosterType.extraSwap)) {
      if (mounted) {
        setState(
          () => praise = widget.model.isBoosterUnlocked(BoosterType.extraSwap)
              ? 'Buy an Extra Swap in the Booster Shop!'
              : 'Extra Swap unlocks at Level ${widget.model.boosterUnlockLevel(BoosterType.extraSwap)}.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      final previousCurrent = current;
      current = next;
      next = previousCurrent;
      if (usingFreeSwap) freeSwaps--;
      praise = usingFreeSwap
          ? 'Free swap used! Extra Swaps are in the shop.'
          : 'Sweet extra swap! Aim your next shot.';
    });
    if (widget.model.haptics) HapticFeedback.selectionClick();
  }

  Future<void> _selectBooster(BoosterType type) async {
    if (finished ||
        paused ||
        rowWarning ||
        rowAnimating ||
        colorBlastAnimating ||
        bombLaunching ||
        rocketLaunching ||
        flight != null ||
        !widget.model.isBoosterUnlocked(type) ||
        widget.model.boosterCount(type) == 0) {
      return;
    }
    if (type == BoosterType.goldenAim) {
      if (await widget.model.useBooster(type) && mounted) {
        setState(() {
          goldenAimShots = 3;
          activeBooster = null;
          praise = 'Golden aim is ready for 3 shots!';
        });
      }
      return;
    }
    if (type == BoosterType.colorBlast) {
      setState(() {
        activeBooster = BoosterType.colorBlast;
        praise = 'Choose a candy colour!';
      });
      final selectedColor = await _showColorBlastPicker();
      if (!mounted) return;
      if (selectedColor == null) {
        setState(() {
          activeBooster = null;
          praise = 'Aim for a sweet match!';
        });
      } else {
        await _activateColorBlast(selectedColor);
      }
      return;
    }
    setState(() {
      activeBooster = activeBooster == type ? null : type;
      praise = activeBooster == null
          ? 'Aim for a sweet match!'
          : type == BoosterType.bomb
          ? 'Bomb ready! Aim and shoot.'
          : type == BoosterType.rocket
          ? 'Rocket ready! Aim and shoot.'
          : 'Tap a candy to use ${type.label}!';
    });
  }

  Future<void> _showBoosterPicker(List<BoosterType> boosters) async {
    if (boosters.isEmpty ||
        finished ||
        paused ||
        rowWarning ||
        rowAnimating ||
        colorBlastAnimating ||
        bombLaunching ||
        rocketLaunching ||
        flight != null) {
      return;
    }
    final chosen = await showDialog<BoosterType>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CHOOSE BOOSTER'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: boosters
              .map(
                (type) => ListTile(
                  leading: Text(
                    type.emoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                  title: Text(type.label),
                  trailing: Text('×${widget.model.boosterCount(type)}'),
                  onTap: () => Navigator.pop(context, type),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (chosen != null && mounted) await _selectBooster(chosen);
  }

  Future<CandyColor?> _showColorBlastPicker() {
    final colors = board
        .where((cell) => !cell.isBomb && !cell.isMystery)
        .map((cell) => cell.color)
        .toSet()
        .toList();
    if (colors.isEmpty) return Future.value(null);
    return showDialog<CandyColor>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('CHOOSE A COLOR'),
        content: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: colors
              .map(
                (color) => InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => Navigator.pop(context, color),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: CandyBall(color: color, size: 52),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _activateColorBlast(CandyColor color) async {
    final geometry = activeGeometry;
    if (geometry == null) {
      if (mounted) setState(() => activeBooster = null);
      return;
    }
    final targets = board
        .where((cell) => cell.color == color && !cell.isBomb && !cell.isMystery)
        .toList();
    if (targets.isEmpty ||
        !await widget.model.useBooster(BoosterType.colorBlast) ||
        !mounted) {
      if (mounted) setState(() => activeBooster = null);
      return;
    }
    setState(() {
      colorBlastAnimating = true;
      colorBlastTargets
        ..clear()
        ..addAll(targets.map((cell) => cell.key));
      activeBooster = null;
      aimPath = const [];
      praise = 'COLOR BLAST!';
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    setState(() {
      final mysteryReward = _claimMysteryRewards(targets);
      _showPop(targets, geometry);
      board.removeWhere(targets.contains);
      cleared += targets.length;
      yellowCleared += targets
          .where((cell) => cell.color == CandyColor.lemon)
          .length;
      combo++;
      score += targets.length * 15 + 150;
      praise = mysteryReward ?? 'COLOR BLAST! +${targets.length * 15 + 150}';
      final dropReward = _dropFloating(geometry, pointsPerCandy: 20);
      if (dropReward != null) praise = dropReward;
      if (widget.model.sound) _playPopSound(math.max(6, targets.length));
      if (widget.model.haptics) HapticFeedback.heavyImpact();
      if (_objectiveDone) _finish(true);
    });
    await Future<void>.delayed(const Duration(milliseconds: 470));
    if (mounted) {
      setState(() {
        colorBlastTargets.clear();
        colorBlastAnimating = false;
      });
    }
  }

  Future<void> _useTargetedBooster(Offset point, BoardGeometry g) async {
    final booster = activeBooster;
    if (booster == null ||
        board.isEmpty ||
        rowWarning ||
        rowAnimating ||
        colorBlastAnimating ||
        bombLaunching ||
        rocketLaunching ||
        finished ||
        paused) {
      return;
    }
    final target = board.reduce(
      (closest, cell) =>
          (g.position(cell) - point).distance <
              (g.position(closest) - point).distance
          ? cell
          : closest,
    );
    if ((g.position(target) - point).distance > g.ballDiameter * 1.8) {
      praise = 'Tap a candy!';
      return;
    }
    if (!await widget.model.useBooster(booster) || !mounted) return;
    setState(() {
      final removed = switch (booster) {
        BoosterType.bomb =>
          board
              .where(
                (cell) =>
                    (g.position(cell) - g.position(target)).distance <
                    g.ballDiameter * 1.65,
              )
              .toList(),
        BoosterType.megaBomb =>
          board
              .where(
                (cell) =>
                    (g.position(cell) - g.position(target)).distance <
                    g.ballDiameter * 2.55,
              )
              .toList(),
        BoosterType.lightning =>
          board.where((cell) => cell.row == target.row).toList(),
        BoosterType.rainbow => _colorGroup(target, g),
        BoosterType.colorBlast => const <CandyCell>[],
        BoosterType.rocket => const <CandyCell>[],
        BoosterType.goldenAim => const <CandyCell>[],
        BoosterType.extraSwap => const <CandyCell>[],
      };
      final mysteryReward = _claimMysteryRewards(removed);
      _showPop(removed, g);
      board.removeWhere(removed.contains);
      cleared += removed.length;
      score += removed.length * 15;
      activeBooster = null;
      praise = mysteryReward ?? '${booster.label} popped ${removed.length}!';
      final dropReward = _dropFloating(g);
      if (dropReward != null) praise = dropReward;
      if (widget.model.sound) {
        SoundService.instance.playPop(candyCount: removed.length);
      }
      if (widget.model.haptics) HapticFeedback.mediumImpact();
      if (_objectiveDone) _finish(true);
    });
  }

  List<CandyCell> _colorGroup(CandyCell target, BoardGeometry g) {
    final result = <CandyCell>[];
    final pending = <CandyCell>[target];
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      if (result.contains(cell)) continue;
      result.add(cell);
      for (final neighbor in _neighbors(cell)) {
        if (!neighbor.isBomb &&
            (neighbor.color == target.color || neighbor.isMystery) &&
            !result.contains(neighbor)) {
          pending.add(neighbor);
        }
      }
    }
    return result;
  }

  Future<void> _shoot(Offset point, BoardGeometry g) async {
    if (finished ||
        paused ||
        rowWarning ||
        rowAnimating ||
        colorBlastAnimating ||
        (activeBooster != null &&
            activeBooster != BoosterType.bomb &&
            activeBooster != BoosterType.rocket) ||
        flight != null) {
      return;
    }
    final initial = _velocity(point, g);
    if (initial == null) return;
    final isBombShot = activeBooster == BoosterType.bomb;
    final isRocketShot = activeBooster == BoosterType.rocket;
    if (isBombShot || isRocketShot) {
      if (isBombShot ? bombLaunching : rocketLaunching) return;
      if (isBombShot) {
        bombLaunching = true;
      } else {
        rocketLaunching = true;
      }
      final used = await widget.model.useBooster(
        isBombShot ? BoosterType.bomb : BoosterType.rocket,
      );
      if (isBombShot) {
        bombLaunching = false;
      } else {
        rocketLaunching = false;
      }
      if (!mounted || !used) {
        if (mounted) {
          setState(
            () => praise = isBombShot ? 'No Bombs left!' : 'No Rockets left!',
          );
        }
        return;
      }
    }
    if (widget.model.sound) SoundService.instance.playShoot();
    var velocity = initial;
    setState(() {
      final firedColor = current;
      if (!isBombShot && !isRocketShot && goldenAimShots > 0) {
        goldenAimShots--;
      }
      aimPath = const [];
      aimInput = null;
      _lastAimSample = null;
      flyingColor = firedColor;
      flyingBomb = isBombShot;
      flyingRocket = isRocketShot;
      if (isBombShot || isRocketShot) {
        activeBooster = null;
      } else {
        current = next;
        next =
            widget.config.colors[random.nextInt(widget.config.colors.length)];
      }
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
    _flightVelocity = velocity;
    _flightGeometry = g;
    _lastFlightTick = null;
    _flightTicker.start();
  }

  CandyCell? _attachmentFor(
    Offset impact,
    BoardGeometry g,
    CandyColor firedColor, {
    CandyCell? collided,
    required Offset velocity,
  }) {
    // Allow the final legal snap to reach the danger line. The board is then
    // frozen immediately with that candy still visible behind Game Over;
    // never delete it just because it caused the loss.
    final maxRow = math.max(0, ((g.dangerLine - g.top) / g.rowStep).ceil());
    final coordinates = <(int row, int col)>[];
    if (collided == null) {
      // Ceiling contact: only top-row cells are valid places to attach.
      for (var col = 0; col < _columnsForRow(0); col++) {
        coordinates.add((0, col));
      }
    } else {
      final offsetRow = (collided.row + gridPhase).isOdd;
      final diagonalColumn = offsetRow ? collided.col + 1 : collided.col - 1;
      coordinates.addAll([
        (collided.row, collided.col - 1),
        (collided.row, collided.col + 1),
        (collided.row - 1, collided.col),
        (collided.row - 1, diagonalColumn),
        (collided.row + 1, collided.col),
        (collided.row + 1, diagonalColumn),
      ]);
    }

    final occupied = board.map((cell) => cell.key).toSet();
    final options = coordinates
        .where(
          (cell) =>
              cell.$1 >= 0 &&
              cell.$1 <= maxRow &&
              cell.$2 >= 0 &&
              cell.$2 < _columnsForRow(cell.$1),
        )
        .map((cell) => CandyCell(cell.$1, cell.$2, firedColor))
        .where((cell) => !occupied.contains(cell.key))
        .toSet()
        .toList();
    if (options.isEmpty) return null;
    // Small finger variations around a true centre shot must not make the
    // candy alternate between the left and right hex slot. Treat a narrow
    // centre corridor as vertical and resolve it consistently on the board
    // centre line. Deliberate angled shots still retain their left/right aim.
    final nearVerticalAim = velocity.dx.abs() <= velocity.dy.abs() * .045;
    final snapImpact = nearVerticalAim
        ? Offset(g.launcher.dx, impact.dy)
        : impact;
    options.sort((a, b) {
      final aPosition = g.position(a);
      final bPosition = g.position(b);
      final distanceDifference =
          (aPosition - snapImpact).distanceSquared -
          (bPosition - snapImpact).distanceSquared;
      if (distanceDifference.abs() > .01) {
        return distanceDifference < 0 ? -1 : 1;
      }
      // Only true geometric ties reach here. Use the travel direction so
      // left and right shots cannot always resolve toward one fixed column.
      if (!nearVerticalAim && velocity.dx.abs() > .01) {
        return velocity.dx < 0
            ? aPosition.dx.compareTo(bPosition.dx)
            : bPosition.dx.compareTo(aPosition.dx);
      }
      // A vertical shot prefers the candidate closest to the board centre.
      final aCenterDistance = (aPosition.dx - g.launcher.dx).abs();
      final bCenterDistance = (bPosition.dx - g.launcher.dx).abs();
      if ((aCenterDistance - bCenterDistance).abs() > .01) {
        return aCenterDistance.compareTo(bCenterDistance);
      }
      return a.key.compareTo(b.key);
    });
    return options.first;
  }

  /// Hex-grid distance derived from the staggered row/column coordinates.
  /// This is intentionally independent of pixel positions and animation.
  double _gridDistance(CandyCell first, CandyCell second) {
    double axialQ(CandyCell cell) {
      final offset = (cell.row + gridPhase).isOdd ? .5 : 0.0;
      return cell.col + offset - cell.row * .5;
    }

    final firstQ = axialQ(first);
    final secondQ = axialQ(second);
    final dq = firstQ - secondQ;
    final dr = (first.row - second.row).toDouble();
    final ds = -dq - dr;
    return math.max(dq.abs(), math.max(dr.abs(), ds.abs()));
  }

  List<CandyCell> _bombBlast(CandyCell impact, double radius) {
    final destroyed = <CandyCell>{};
    final triggeredBombs = <String>{};
    final pending = <CandyCell>[impact];

    while (pending.isNotEmpty) {
      final center = pending.removeLast();
      // A projectile starts a blast at any candy. Board bomb candies start
      // another blast only once, preventing an infinite chain.
      if (center.isBomb && !triggeredBombs.add(center.key)) continue;
      final inRadius = board
          .where((cell) => _gridDistance(center, cell) <= radius + .001)
          .toList();
      destroyed.addAll(inRadius);
      for (final bomb in inRadius.where((cell) => cell.isBomb)) {
        if (!triggeredBombs.contains(bomb.key)) pending.add(bomb);
      }
    }
    return destroyed.toList();
  }

  void _explodeBomb(Offset impact, BoardGeometry g) {
    if (board.isEmpty) {
      _countShotForIncomingRow();
      return;
    }
    final target = board.reduce(
      (closest, cell) =>
          (g.position(cell) - impact).distance <
              (g.position(closest) - impact).distance
          ? cell
          : closest,
    );
    bombExplosion = g.position(target);
    bombController.forward(from: 0);
    final removed = _bombBlast(target, widget.config.bombRadius);
    shots--;

    if (removed.isEmpty) {
      combo = 0;
      praise = 'Bomb missed!';
      _countShotForIncomingRow();
      return;
    }

    final mysteryReward = _claimMysteryRewards(removed);
    _showPop(removed, g);
    board.removeWhere(removed.contains);
    cleared += removed.length;
    yellowCleared += removed
        .where((cell) => cell.color == CandyColor.lemon)
        .length;
    combo++;
    score += removed.length * 15 + math.max(0, combo - 1) * 15;
    final dropReward = _dropFloating(g, pointsPerCandy: 20);
    final totalCleared = removed.length;
    praise =
        mysteryReward ??
        (totalCleared >= 10
            ? 'CANDY AVALANCHE!'
            : totalCleared >= 6
            ? 'SWEET BLAST!'
            : 'BOOM! +${removed.length * 15}');
    if (dropReward != null) praise = dropReward;
    if (widget.model.sound) _playPopSound(math.max(6, removed.length));
    if (widget.model.haptics) HapticFeedback.heavyImpact();

    if (_objectiveDone) {
      _finish(true);
    } else if (shots <= 0) {
      _finish(false);
    } else if (_dangerReached(g)) {
      praise = 'DANGER ZONE! Try again!';
      _finish(false);
    }
  }

  void _explodeRocket(Offset impact, BoardGeometry g, CandyCell? collided) {
    if (board.isEmpty) return;
    final target =
        collided ??
        board.reduce(
          (closest, cell) =>
              (g.position(cell) - impact).distance <
                  (g.position(closest) - impact).distance
              ? cell
              : closest,
        );
    final removed = board.where((cell) => cell.row == target.row).toList();
    if (removed.isEmpty) return;

    rocketBlastY = g.position(target).dy;
    rocketController.forward(from: 0);
    shots--;
    _showPop(removed, g);
    board.removeWhere(removed.contains);
    cleared += removed.length;
    yellowCleared += removed
        .where((cell) => cell.color == CandyColor.lemon)
        .length;
    combo++;
    score += removed.length * 20 + math.max(0, combo - 1) * 20;
    praise = removed.length >= 6 ? 'ROCKET BLAST!' : 'Rocket cleared a row!';
    final dropReward = _dropFloating(g, pointsPerCandy: 30);
    if (dropReward != null) praise = dropReward;
    if (widget.model.sound) _playPopSound(math.max(6, removed.length));
    if (widget.model.haptics) HapticFeedback.heavyImpact();
    if (_objectiveDone) {
      _finish(true);
    } else if (shots <= 0) {
      _finish(false);
    } else if (_dangerReached(g)) {
      praise = 'DANGER ZONE! Try again!';
      _finish(false);
    }
  }

  void _attach(
    Offset impact,
    BoardGeometry g,
    CandyColor firedColor, {
    CandyCell? collided,
    required Offset velocity,
  }) {
    final added = _attachmentFor(
      impact,
      g,
      firedColor,
      collided: collided,
      velocity: velocity,
    );
    shots--;
    if (added == null) {
      praise = 'DANGER ZONE! Try again!';
      _finish(false);
      return;
    }
    board.add(added);
    // Danger is checked before matching or floating-candy logic. This keeps
    // the exact loss-making formation on screen rather than popping/removing
    // any candies after the line has been crossed.
    if (_dangerReached(g)) {
      praise = 'DANGER ZONE! Try again!';
      _finish(false);
      return;
    }
    final group = <CandyCell>[];
    final pending = <CandyCell>[added];
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      if (group.contains(cell)) continue;
      group.add(cell);
      for (final neighbor in _neighbors(cell)) {
        if (!neighbor.isBomb &&
            (neighbor.color == added.color || neighbor.isMystery) &&
            !group.contains(neighbor)) {
          pending.add(neighbor);
        }
      }
    }
    final matched = group.length >= 3;
    if (matched) {
      final mysteryReward = _claimMysteryRewards(group);
      _showPop(group, g);
      _playPopSound(group.length);
      board.removeWhere(group.contains);
      cleared += group.length;
      if (added.color == CandyColor.lemon) yellowCleared += group.length;
      combo++;
      score += group.length * 10 + math.max(0, combo - 1) * 10;
      praise =
          mysteryReward ??
          (combo > 1 ? 'Combo x$combo! Amazing!' : 'POP! Great shot!');
      final dropReward = _dropFloating(g);
      if (dropReward != null) praise = dropReward;
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
    } else if (_dangerReached(g)) {
      praise = 'DANGER ZONE! Try again!';
      _finish(false);
    } else {
      if (!matched) _countShotForIncomingRow();
    }
  }

  void _countShotForIncomingRow() {
    if (!widget.config.newRowEnabled || rowWarning || rowAnimating) return;
    rowShotCounter++;
    if (rowShotCounter < widget.config.newRowInterval) return;
    _queueIncomingRow();
  }

  List<CandyCell> _generateCandyRow() {
    final columns = _columnsForRow(0, phase: gridPhase - 1);
    final configuredSize = widget.config.newRowSize;
    final size =
        (configuredSize == 0 ? columns : configuredSize.clamp(1, columns))
            .toInt();
    final firstColumn = (columns - size) ~/ 2;

    return List<CandyCell>.generate(size, (index) {
      final col = firstColumn + index;
      return CandyCell(
        0,
        col,
        widget.config.colors[(rowsEntered + col) % widget.config.colors.length],
        isMystery:
            widget.config.newRowSpecialChance > 0 &&
            random.nextDouble() < widget.config.newRowSpecialChance,
      );
    });
  }

  void _queueIncomingRow() {
    if (finished || rowWarning || rowAnimating) return;
    final geometry = activeGeometry;
    // Do not insert a row that would make the board cross the fixed danger
    // boundary. This prevents visual overlap with the shooter controls.
    if (geometry != null && _wouldReachDangerAfterIncomingRow(geometry)) {
      setState(() => praise = 'TOO CLOSE! Clear some candies!');
      _finish(false);
      return;
    }
    incomingRow
      ..clear()
      ..addAll(_generateCandyRow());
    setState(() {
      rowWarning = true;
      aimPath = const [];
      praise = 'CEILING DROP!';
    });
    rowTimer?.cancel();
    rowTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || finished) return;
      setState(() {
        movingBoard
          ..clear()
          ..addAll(board);
        // Commit the logical ceiling movement before rendering it. Gameplay is
        // locked during this animation, so every system sees one consistent
        // staggered grid while the old positions glide to their new rows.
        board
          ..clear()
          ..addAll(incomingRow)
          ..addAll(
            movingBoard.map(
              (cell) => CandyCell(
                cell.row + 1,
                cell.col,
                cell.color,
                isMystery: cell.isMystery,
                isBomb: cell.isBomb,
              ),
            ),
          );
        rowWarning = false;
        rowAnimating = true;
      });
      rowController.forward(from: 0);
    });
  }

  void _settleIncomingRow() {
    setState(() {
      incomingRow.clear();
      movingBoard.clear();
      rowAnimating = false;
      rowShotCounter = 0;
      rowsEntered++;
      gridPhase--;
      praise = 'Fresh candy row! Keep popping!';
      if (widget.model.haptics) HapticFeedback.lightImpact();
      final geometry = activeGeometry;
      if (geometry != null && _dangerReached(geometry)) {
        praise = 'TOO CLOSE! Try again!';
        _finish(false);
      }
    });
  }

  bool _dangerReached(BoardGeometry g) => board.any(
    (cell) => g.position(cell).dy + g.ballDiameter / 2 >= g.dangerLine,
  );

  bool _wouldReachDangerAfterIncomingRow(BoardGeometry g) => board.any(
    (cell) =>
        g
                .position(
                  CandyCell(
                    cell.row + 1,
                    cell.col,
                    cell.color,
                    isMystery: cell.isMystery,
                    isBomb: cell.isBomb,
                  ),
                  phase: gridPhase - 1,
                )
                .dy +
            g.ballDiameter / 2 >=
        g.dangerLine,
  );

  Future<void> _showRowTutorial() async {
    if (!mounted || finished) return;
    setState(() => paused = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('NEW CHALLENGE! 🍬'),
        content: const Text('New candies can now enter from the top!'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => paused = false);
    await widget.model.markNewRowTutorialSeen();
  }

  Future<void> _showChallengeIntro() async {
    if (!mounted || finished) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.config.challengeTitle!),
        content: Text(
          'Clear ${widget.config.target} candies in ${widget.config.shots} shots!',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('LET\'S GO!'),
          ),
        ],
      ),
    );
  }

  String? _dropFloating(BoardGeometry g, {int pointsPerCandy = 15}) {
    final connected = <CandyCell>[];
    final pending = board.where((cell) => cell.row == 0).toList();
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      if (connected.contains(cell)) continue;
      connected.add(cell);
      for (final neighbor in _neighbors(cell)) {
        if (!connected.contains(neighbor)) pending.add(neighbor);
      }
    }
    final dropped = board.where((cell) => !connected.contains(cell)).toList();
    if (dropped.isNotEmpty) {
      final mysteryReward = _claimMysteryRewards(dropped);
      _showDrop(dropped, g);
      board.removeWhere(dropped.contains);
      cleared += dropped.length;
      yellowCleared += dropped
          .where((cell) => cell.color == CandyColor.lemon)
          .length;
      score += dropped.length * pointsPerCandy;
      return mysteryReward ?? 'Sweet drop +${dropped.length * pointsPerCandy}!';
    }
    return null;
  }

  String? _claimMysteryRewards(Iterable<CandyCell> removed) {
    final mysteries = removed.where((cell) => cell.isMystery).toList();
    if (mysteries.isEmpty) return null;
    final rewards = <String>[];
    for (final _ in mysteries) {
      switch (random.nextInt(5)) {
        case 0:
          final coinsWon = random.nextBool() ? 25 : 50;
          widget.model.grantMysteryReward(coinsWon: coinsWon);
          rewards.add('+$coinsWon COINS');
        case 1:
          widget.model.grantMysteryReward(booster: BoosterType.bomb);
          rewards.add('BOMB');
        case 2:
          widget.model.grantMysteryReward(booster: BoosterType.rainbow);
          rewards.add('RAINBOW');
        case 3:
          score += 100;
          rewards.add('+100 BONUS');
        case 4:
          combo += 2;
          score += 30;
          rewards.add('COMBO +2');
      }
    }
    return 'MYSTERY: ${rewards.join(' + ')}!';
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

  void _showDrop(List<CandyCell> candies, BoardGeometry g) {
    dropEffects
      ..clear()
      ..addAll(
        candies.asMap().entries.map(
          (entry) => DropEffect(
            position: g.position(entry.value),
            color: entry.value.color,
            size: g.ballDiameter,
            delay: entry.key * .045,
          ),
        ),
      );
    dropController.forward(from: 0);
  }

  void _playPopSound(int candyCount) {
    if (!widget.model.sound) return;
    SoundService.instance.playPop(candyCount: candyCount);
  }

  bool get _objectiveDone => widget.config.objective == ObjectiveType.clear
      ? cleared >= widget.config.target
      : board.isEmpty;

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
      completedChapter = await widget.model.finishLevel(
        widget.config.id,
        score,
        _earnedStars,
      );
      chapterComplete = completedChapter != null;
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
      _stopFlightTicker();
      widget.onExit();
    } else if (action == 'restart') {
      setState(_newLevel);
    } else {
      setState(() => paused = false);
    }
  }

  @override
  void dispose() {
    _flightTicker.dispose();
    rowTimer?.cancel();
    launchController.dispose();
    popController.dispose();
    dropController.dispose();
    rowController.dispose();
    bombController.dispose();
    rocketController.dispose();
    super.dispose();
  }

  Offset _displayPosition(CandyCell cell, BoardGeometry g) {
    if (!rowAnimating) return g.position(cell);
    final target = g.position(
      CandyCell(
        cell.row + 1,
        cell.col,
        cell.color,
        isMystery: cell.isMystery,
        isBomb: cell.isBomb,
      ),
      phase: gridPhase - 1,
    );
    return Offset.lerp(
      g.position(cell),
      target,
      Curves.easeOut.transform(rowController.value),
    )!;
  }

  Widget _boardCandy(CandyCell cell, double size) {
    final candy = cell.isBomb
        ? BombCandy(size: size)
        : cell.isMystery
        ? MysteryCandy(size: size)
        : CandyBall(color: cell.color, size: size);
    if (!colorBlastTargets.contains(cell.key)) return candy;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: candy),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: cell.color.color.withValues(alpha: .9),
                      blurRadius: 14,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GradientScaffold(
    playfield: true,
    child: SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
                child: GameTopHud(
                  level: widget.config.id,
                  score: score,
                  stars: _earnedStars,
                  coins: widget.model.coins,
                  onExit: widget.onExit,
                  onPause: _showPause,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: GameStatusCard(
                        icon: Icons.track_changes_rounded,
                        label: widget.config.objective == ObjectiveType.clear
                            ? 'Clear goal'
                            : 'Clear all',
                        value: widget.config.objective == ObjectiveType.clear
                            ? '$cleared / ${widget.config.target}'
                            : '${board.length} left',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GameStatusCard(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Shots',
                        value: '$shots',
                      ),
                    ),
                    if (widget.config.newRowEnabled) ...[
                      const SizedBox(width: 8),
                      MissCounterIndicator(
                        misses: rowShotCounter,
                        threshold: widget.config.newRowInterval,
                        dropping: rowWarning || rowAnimating,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final g = BoardGeometry(
                      constraints.biggest,
                      gridPhase: gridPhase,
                    );
                    activeGeometry = g;
                    final candySize = g.ballDiameter;
                    final availableBoosters = BoosterType.values
                        .where(
                          (type) =>
                              type != BoosterType.extraSwap &&
                              widget.model.isBoosterUnlocked(type) &&
                              widget.model.boosterCount(type) > 0,
                        )
                        .toList();
                    final shownBooster =
                        activeBooster ??
                        (availableBoosters.isEmpty
                            ? null
                            : availableBoosters.first);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          _updateAim(details.localPosition, g),
                      onTapUp: (details) =>
                          activeBooster == null ||
                              activeBooster == BoosterType.bomb ||
                              activeBooster == BoosterType.rocket
                          ? _shoot(details.localPosition, g)
                          : _useTargetedBooster(details.localPosition, g),
                      onPanStart: (details) =>
                          _updateAim(details.localPosition, g),
                      onPanUpdate: (details) =>
                          _updateAim(details.localPosition, g),
                      onPanEnd: (_) {
                        if (aimInput != null) _shoot(aimInput!, g);
                      },
                      child: RepaintBoundary(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: AimPainter(path: aimPath),
                              ),
                            ),
                            Positioned(
                              left: g.wallLeft,
                              right: g.size.width - g.wallRight,
                              top: g.dangerLine - 17,
                              child: IgnorePointer(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: const Color(0xffff6b9b),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfff6538a),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xffffb6d1),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Text(
                                        'DANGER ZONE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          letterSpacing: .4,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: const Color(0xffff6b9b),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedBuilder(
                              animation: rowController,
                              builder: (_, __) => Stack(
                                children: [
                                  ...(rowAnimating ? movingBoard : board).map((
                                    cell,
                                  ) {
                                    final position = _displayPosition(cell, g);
                                    return Positioned(
                                      left: position.dx - candySize / 2,
                                      top: position.dy - candySize / 2,
                                      child: _boardCandy(cell, candySize),
                                    );
                                  }),
                                  if (rowAnimating)
                                    ...incomingRow.map((cell) {
                                      final target = g.position(
                                        cell,
                                        phase: gridPhase - 1,
                                      );
                                      final progress = Curves.easeOut.transform(
                                        rowController.value,
                                      );
                                      final position = Offset.lerp(
                                        target - Offset(0, g.rowStep),
                                        target,
                                        progress,
                                      )!;
                                      return Positioned(
                                        left: position.dx - candySize / 2,
                                        top: position.dy - candySize / 2,
                                        child: _boardCandy(cell, candySize),
                                      );
                                    }),
                                ],
                              ),
                            ),
                            ...dropEffects.map(
                              (effect) => Positioned(
                                left: effect.position.dx - effect.size / 2,
                                top: effect.position.dy - effect.size / 2,
                                child: IgnorePointer(
                                  child: FallingCandyEffect(
                                    effect: effect,
                                    animation: dropController,
                                  ),
                                ),
                              ),
                            ),
                            if (rowWarning || rowAnimating)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: math.max(4, g.top - 12),
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfff65371),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Text(
                                        'CEILING DROP!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                            if (bombExplosion != null)
                              Positioned(
                                left: bombExplosion!.dx - candySize * 2,
                                top: bombExplosion!.dy - candySize * 2,
                                child: IgnorePointer(
                                  child: BombBlastEffect(
                                    size: candySize * 4,
                                    animation: bombController,
                                  ),
                                ),
                              ),
                            if (rocketBlastY != null)
                              Positioned(
                                left: g.wallLeft,
                                right: g.size.width - g.wallRight,
                                top: rocketBlastY! - candySize * .5,
                                child: IgnorePointer(
                                  child: RocketRowBlastEffect(
                                    height: candySize,
                                    animation: rocketController,
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
                                      color:
                                          (flyingBomb
                                                  ? const Color(0xff3d3146)
                                                  : flyingRocket
                                                  ? const Color(0xffff7a55)
                                                  : (flyingColor ?? current)
                                                        .color)
                                              .withValues(alpha: fade * .55),
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
                                  child: flyingBomb
                                      ? BombCandy(size: candySize)
                                      : flyingRocket
                                      ? RocketCandy(size: candySize)
                                      : CandyBall(
                                          color: flyingColor ?? current,
                                          size: candySize,
                                        ),
                                ),
                              ),
                            Positioned(
                              left: 24,
                              right: 24,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xff9b5ad0,
                                  ).withValues(alpha: .9),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xffffb3d1),
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  praise,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: g.launcher.dx - candySize * .68,
                              bottom: 72,
                              child: AnimatedBuilder(
                                animation: launchController,
                                builder: (_, child) {
                                  final recoil =
                                      math.sin(
                                        launchController.value * math.pi,
                                      ) *
                                      9;
                                  return Transform.translate(
                                    offset: Offset(0, recoil),
                                    child: Transform.scale(
                                      scale:
                                          1 +
                                          math.sin(
                                                launchController.value *
                                                    math.pi,
                                              ) *
                                              .055,
                                      child: child,
                                    ),
                                  );
                                },
                                child: LollipopLauncher(
                                  color: current,
                                  size: candySize * 1.36,
                                  isBomb: activeBooster == BoosterType.bomb,
                                  isRocket: activeBooster == BoosterType.rocket,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 14,
                              bottom: 88,
                              child: CandySlotCard(
                                label: 'NEXT',
                                onTap: _swapNextCandy,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CandyBall(
                                      color: next,
                                      size: candySize * .72,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      freeSwaps > 0
                                          ? 'FREE SWAP'
                                          : 'SWAPS ×${widget.model.extraSwapBoosters}',
                                      style: const TextStyle(
                                        color: Color(0xfff6538a),
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              bottom: 88,
                              child: BoosterSlotCard(
                                type: shownBooster,
                                count: shownBooster == null
                                    ? 0
                                    : widget.model.boosterCount(shownBooster),
                                selected: activeBooster == shownBooster,
                                onTap: shownBooster == null
                                    ? null
                                    : () =>
                                          _showBoosterPicker(availableBoosters),
                              ),
                            ),
                            if (finished && !showFullScreenResultOverlay)
                              ResultOverlay(
                                won: won,
                                candiesCleared: cleared,
                                stars: _earnedStars,
                                score: score,
                                coinsEarned: won ? 15 + _earnedStars * 10 : 0,
                                goal:
                                    widget.config.objective ==
                                        ObjectiveType.clear
                                    ? 'Reach ${widget.config.target} candies'
                                    : 'Clear all the candies',
                                chapterName: chapterComplete
                                    ? completedChapter!.name.toUpperCase()
                                    : null,
                                chapterReward: chapterComplete
                                    ? '${completedChapter!.reward.emoji} ${completedChapter!.reward.label.toUpperCase()} ×${completedChapter!.rewardAmount}\n🪙 +${completedChapter!.coinReward} COINS'
                                    : null,
                                onPrimary: won
                                    ? chapterComplete
                                          ? () async {
                                              await widget.model
                                                  .claimChapterReward(
                                                    completedChapter!,
                                                  );
                                              widget.onExit();
                                            }
                                          : widget.onNext
                                    : () => setState(_newLevel),
                                onReplay: () => setState(_newLevel),
                                onSecondary: widget.onExit,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (finished && showFullScreenResultOverlay)
            ResultOverlay(
              won: won,
              candiesCleared: cleared,
              stars: _earnedStars,
              score: score,
              coinsEarned: won ? 15 + _earnedStars * 10 : 0,
              goal: widget.config.objective == ObjectiveType.clear
                  ? 'Reach ${widget.config.target} candies'
                  : 'Clear all the candies',
              chapterName: chapterComplete
                  ? completedChapter!.name.toUpperCase()
                  : null,
              chapterReward: chapterComplete
                  ? '${completedChapter!.reward.label.toUpperCase()} x${completedChapter!.rewardAmount}\n+${completedChapter!.coinReward} COINS'
                  : null,
              onPrimary: won
                  ? chapterComplete
                        ? () async {
                            await widget.model.claimChapterReward(
                              completedChapter!,
                            );
                            widget.onExit();
                          }
                        : widget.onNext
                  : () => setState(_newLevel),
              onReplay: () => setState(_newLevel),
              onSecondary: widget.onExit,
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
    required this.score,
    required this.coinsEarned,
    required this.goal,
    this.chapterName,
    this.chapterReward,
    required this.onPrimary,
    required this.onReplay,
    required this.onSecondary,
  });

  final bool won;
  final int candiesCleared;
  final int stars;
  final int score;
  final int coinsEarned;
  final String goal;
  final String? chapterName;
  final String? chapterReward;
  final VoidCallback onPrimary;
  final VoidCallback onReplay;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xba27305e),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeOutBack,
        builder: (_, progress, child) => Opacity(
          opacity: progress.clamp(0, 1),
          child: Transform.scale(
            scale: .76 + progress * .24,
            alignment: Alignment.center,
            child: child,
          ),
        ),
        child: LayoutBuilder(
          builder: (_, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, constraints.maxHeight - 20),
              ),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.fromLTRB(18, 94, 18, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xfffffcf5),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: const Color(0xffffd06b),
                          width: 3,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66002667),
                            offset: Offset(0, 8),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            won ? 'Amazing!' : 'GAME OVER!',
                            style: TextStyle(
                              color: won
                                  ? const Color(0xff7245a2)
                                  : const Color(0xff8154c7),
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            chapterName != null
                                ? '$chapterName - CHAPTER COMPLETE'
                                : won
                                ? 'You cleared the level successfully!'
                                : 'The candy reached the danger zone.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xff695064),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (won) ...[
                            _ResultInfoCard(
                              label: 'SCORE',
                              value: '$score',
                              icon: Icons.auto_awesome_rounded,
                              color: const Color(0xffffbd42),
                            ),
                            const SizedBox(height: 6),
                            _ResultInfoCard(
                              label: 'LEVEL REWARD',
                              value: '+$coinsEarned COINS',
                              icon: Icons.monetization_on_rounded,
                              color: const Color(0xffffae24),
                              compact: true,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xfffff1d0),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xffffd27d),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xff5eaf25),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'GOAL\n$goal',
                                      style: const TextStyle(
                                        color: Color(0xff755240),
                                        fontSize: 12,
                                        height: 1.2,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.sentiment_satisfied_alt_rounded,
                                    color: Color(0xffff779f),
                                    size: 52,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$candiesCleared candies cleared',
                                    style: const TextStyle(
                                      color: Color(0xff5d465d),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (chapterReward != null) ...[
                            const SizedBox(height: 9),
                            Text(
                              chapterReward!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xff684e67),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          PrimaryButton(
                            label: won
                                ? chapterName != null
                                      ? 'CLAIM REWARD'
                                      : 'NEXT LEVEL'
                                : 'TRY AGAIN',
                            onTap: onPrimary,
                          ),
                          if (won) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _ResultActionButton(
                                    icon: Icons.replay_rounded,
                                    label: 'REPLAY',
                                    color: const Color(0xff397dde),
                                    onTap: onReplay,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ResultActionButton(
                                    icon: Icons.home_rounded,
                                    label: 'HOME',
                                    color: const Color(0xffa559ce),
                                    onTap: onSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ] else
                            TextButton(
                              onPressed: onSecondary,
                              child: const Text(
                                'BACK TO MAP',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      // Keep the whole three-star row clear above the ribbon.
                      // This prevents the bottom points of the stars from being
                      // visually covered on shorter Android displays.
                      top: -7,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _ResultStar(active: stars >= 1, size: 48),
                          Transform.translate(
                            offset: const Offset(0, -5),
                            child: _ResultStar(active: stars >= 2, size: 62),
                          ),
                          _ResultStar(active: stars >= 3, size: 48),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 43,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xffff799c), Color(0xffe9487d)],
                          ),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: const Color(0xffffc6d9),
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x663e235f),
                              offset: Offset(0, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Text(
                          chapterName != null
                              ? 'CHAPTER COMPLETE!'
                              : 'LEVEL COMPLETE!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            letterSpacing: .2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget legacyBuild(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xaa27305e),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xffffd7e4), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chapterName != null
                    ? '🎉 CHAPTER COMPLETE!'
                    : won
                    ? 'LEVEL COMPLETE!'
                    : 'Almost there!',
                style: TextStyle(
                  color: won
                      ? const Color(0xffe75a84)
                      : const Color(0xff8154c7),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                chapterName != null
                    ? '$chapterName\n10 LEVELS COMPLETE'
                    : won
                    ? 'Awesome! You made it sweet.'
                    : 'Try again \u2014 you are close!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff4d3c54),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
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
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (chapterReward != null) ...[
                const SizedBox(height: 10),
                Text(
                  chapterReward!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xff684e67),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                label: won
                    ? chapterName != null
                          ? 'CLAIM REWARD'
                          : 'NEXT LEVEL'
                    : 'TRY AGAIN',
                onTap: onPrimary,
              ),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  won ? 'LEVEL MAP' : 'BACK TO MAP',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ResultStar extends StatelessWidget {
  const _ResultStar({required this.active, required this.size});

  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.star_rounded,
    color: active ? const Color(0xffffc32f) : const Color(0xffffe7ab),
    size: size,
    shadows: active
        ? const [Shadow(color: Color(0x88ca7112), offset: Offset(0, 4))]
        : null,
  );
}

class _ResultInfoCard extends StatelessWidget {
  const _ResultInfoCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: compact ? 7 : 8),
    decoration: BoxDecoration(
      color: const Color(0xffffe7ae),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xffe6b561), width: 1.5),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xff80552f),
            fontSize: 11,
            letterSpacing: .5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: compact ? 20 : 17),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: const Color(0xff5a3279),
                fontSize: compact ? 18 : 25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ResultActionButton extends StatelessWidget {
  const _ResultActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x5539236e),
            offset: Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.model, required this.onBack});

  final AppModel model;
  final VoidCallback onBack;

  Widget collectionRewardHub(BuildContext context) {
    final stars = model.stars.fold<int>(0, (sum, value) => sum + value);
    final collectionScore = stars + model.unlocked * 3;
    return GradientScaffold(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  RoundIcon(Icons.arrow_back_rounded, onBack),
                  const Spacer(),
                  CoinPill(coins: model.coins),
                ],
              ),
            ),
            const CollectionTitleRibbon(),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 7, 22, 10),
              child: Text(
                'Keep playing to collect sweet launcher skins!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff654486),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                children: [
                  CollectionSpinHero(
                    canSpin: model.canLuckySpin,
                    prizes: model.luckySpinPrizes,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => LuckySpinDialog(model: model),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CollectionBoosterSummary(model: model),
                  const SizedBox(height: 15),
                  CollectionRewardCard(
                    name: 'Classic Pop',
                    color: CandyColor.strawberry,
                    progress: collectionScore.clamp(0, 30),
                    goal: 30,
                    unlocked: true,
                  ),
                  const SizedBox(height: 12),
                  CollectionRewardCard(
                    name: 'Lollipop',
                    color: CandyColor.lemon,
                    progress: collectionScore.clamp(0, 60),
                    goal: 60,
                    unlocked: model.unlocked >= 4,
                  ),
                  const SizedBox(height: 12),
                  CollectionRewardCard(
                    name: 'Mint Swirl',
                    color: CandyColor.mint,
                    progress: collectionScore.clamp(0, 90),
                    goal: 90,
                    unlocked: model.unlocked >= 7,
                  ),
                  const SizedBox(height: 12),
                  CollectionRewardCard(
                    name: 'Rainbow Glow',
                    color: CandyColor.blueberry,
                    progress: collectionScore.clamp(0, 120),
                    goal: 120,
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

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PageHeader(title: 'SETTINGS', onBack: onBack),
          StreamBuilder(
            stream: model.auth.authState,
            builder: (context, snapshot) {
              final user = snapshot.data;
              final signedIn = user != null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            color: Color(0xfff6538a),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ACCOUNT',
                            style: TextStyle(
                              color: Color(0xff654486),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        signedIn
                            ? (user.email ?? 'Signed in player')
                            : 'Playing as a guest',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: signedIn
                            ? OutlinedButton.icon(
                                onPressed: () => _confirmLogout(context),
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('LOG OUT'),
                              )
                            : FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          AuthScreen(onSignedIn: onBack),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('SIGN IN / CREATE ACCOUNT'),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HowToPlayScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.help_outline_rounded),
                  label: const Text('HOW TO PLAY'),
                ),
                const SizedBox(height: 10),
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

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign back in whenever you like.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('LOG OUT'),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await model.auth.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are now playing as a guest.')),
        );
      }
    }
  }
}

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: Column(
        children: [
          PageHeader(
            title: 'HOW TO PLAY',
            onBack: () => Navigator.of(context).pop(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Text(
              'Pop candies, collect rewards, and clear every level!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
              children: const [
                HowToPlayStep(
                  number: '1',
                  icon: Icons.ads_click_rounded,
                  title: 'AIM AND SHOOT',
                  text:
                      'Drag from the launcher to aim. The dotted guide shows where your candy will land.',
                ),
                HowToPlayStep(
                  number: '2',
                  icon: Icons.bubble_chart_rounded,
                  title: 'MATCH 3 OR MORE',
                  text:
                      'Join three or more candies of the same colour to pop them. Bigger pops make bigger combos!',
                ),
                HowToPlayStep(
                  number: '3',
                  icon: Icons.swap_horiz_rounded,
                  title: 'SWAP THE NEXT CANDY',
                  text:
                      'Tap NEXT to swap the shooter candy. Each level has one free swap; use Extra Swap tokens after that.',
                ),
                HowToPlayStep(
                  number: '4',
                  icon: Icons.auto_awesome_rounded,
                  title: 'USE BOOSTERS',
                  text:
                      'Bomb and Golden Aim help when the board gets tricky. More boosters unlock as you progress.',
                ),
                HowToPlayStep(
                  number: '5',
                  icon: Icons.warning_amber_rounded,
                  title: 'STAY ABOVE THE DANGER LINE',
                  text:
                      'From Level 11, new rows may enter from the top. Clear candies before they reach the danger zone.',
                ),
                HowToPlayStep(
                  number: '6',
                  icon: Icons.question_mark_rounded,
                  title: 'FIND MYSTERY CANDY',
                  text:
                      'From Level 51, pop a purple ? candy for a surprise: coins, boosters, a score bonus, or a combo boost.',
                ),
                HowToPlayStep(
                  number: '7',
                  icon: Icons.emoji_events_rounded,
                  title: 'CLEAR THE LEVEL',
                  text:
                      'Finish the level goal before your shots run out. Earn stars, coins, boosters, and climb the ranks!',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class HowToPlayStep extends StatelessWidget {
  const HowToPlayStep({
    super.key,
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  final String number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xffffd363),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xff654486),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: const Color(0xfff6538a), size: 21),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xff654486),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(text, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) =>
      SettingsScreen(model: model, onBack: onBack).collectionRewardHub(context);

  Widget legacyBuild(BuildContext context) => GradientScaffold(
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
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => LuckySpinDialog(model: model),
            ),
            icon: const Icon(Icons.casino_rounded),
            label: const Text('LUCKY SPIN'),
          ),
          Text(
            'Boosters  💣 ${model.bombBoosters}   🌈 ${model.rainbowBoosters}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
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

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({
    super.key,
    required this.model,
    required this.onBack,
    required this.onSignIn,
  });

  final AppModel model;
  final VoidCallback onBack;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => _buildPublicGlobal(context);

  Widget legacyBuild(BuildContext context) {
    final user = model.auth.currentUser;
    final canViewPrivateBoard = user != null;
    if (!canViewPrivateBoard) return _buildPublicGlobal(context);
    return GradientScaffold(
      child: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: 'LEADERBOARD',
              onBack: onBack,
              trailing: CoinPill(coins: model.coins),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Panel(
                child: Row(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xffffb725),
                      size: 38,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'THIS WEEK',
                            style: TextStyle(
                              color: Color(0xff654486),
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Your best completed-level score counts.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showSignInPrompt())
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Panel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: Color(0xfff6538a),
                          size: 52,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'SIGN IN TO JOIN',
                          style: TextStyle(
                            color: Color(0xff654486),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create an account to submit scores and see this week’s Candy Shooter ranks.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: onSignIn,
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('GO TO SIGN IN'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: StreamBuilder<List<WeeklyLeaderboardEntry>>(
                  stream: model.leaderboard.watchTop(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const _LeaderboardMessage(
                        icon: Icons.cloud_off_rounded,
                        title: 'LEADERBOARD UNAVAILABLE',
                        message: 'Please check your connection and try again.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final entries = snapshot.data!;
                    return StreamBuilder<WeeklyLeaderboardEntry?>(
                      stream: model.leaderboard.watchPlayer(user.id),
                      builder: (context, playerSnapshot) {
                        final ownEntry = playerSnapshot.data;
                        final visiblePlayer = entries.any(
                          (entry) => entry.uid == user.id,
                        );
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          children: [
                            if (entries.isEmpty)
                              const _LeaderboardMessage(
                                icon: Icons.auto_awesome_rounded,
                                title: 'BE THE FIRST!',
                                message:
                                    'Finish a level to set this week’s first score.',
                              )
                            else
                              ...entries.indexed.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: LeaderboardRankCard(
                                    rank: item.$1 + 1,
                                    entry: item.$2,
                                    isCurrentPlayer: item.$2.uid == user.id,
                                  ),
                                ),
                              ),
                            if (ownEntry != null && !visiblePlayer) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                                child: Text(
                                  'YOUR WEEKLY BEST',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              LeaderboardRankCard(
                                rank: null,
                                entry: ownEntry,
                                isCurrentPlayer: true,
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicGlobal(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: Column(
        children: [
          PageHeader(
            title: 'GLOBAL RANKS',
            onBack: onBack,
            trailing: CoinPill(coins: model.coins),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Panel(
              child: Row(
                children: [
                  Icon(
                    Icons.public_rounded,
                    color: Color(0xffffb725),
                    size: 38,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WORLDWIDE PROGRESS',
                          style: TextStyle(
                            color: Color(0xff654486),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Ranked by level, then stars, then best score.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (model.auth.currentUser == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login_rounded),
                label: const Text('SIGN IN TO JOIN THE RANKS'),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Your completed levels update this board automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<PublicLeaderboardEntry>>(
              stream: model.leaderboard.watchGlobalProgress(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _LeaderboardMessage(
                    icon: Icons.cloud_off_rounded,
                    title: 'LEADERBOARD UNAVAILABLE',
                    message: 'Please check your connection and try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return const _LeaderboardMessage(
                    icon: Icons.auto_awesome_rounded,
                    title: 'BE THE FIRST!',
                    message:
                        'Sign in and finish a level to join the global ranks.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (_, index) =>
                      PublicLeaderboardRankCard(entry: entries[index]),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  bool _showSignInPrompt() => model.auth.currentUser == null;
}

class _LeaderboardMessage extends StatelessWidget {
  const _LeaderboardMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xfff6538a), size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff654486),
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class LeaderboardRankCard extends StatelessWidget {
  const LeaderboardRankCard({
    super.key,
    required this.rank,
    required this.entry,
    required this.isCurrentPlayer,
  });

  final int? rank;
  final WeeklyLeaderboardEntry entry;
  final bool isCurrentPlayer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: isCurrentPlayer
          ? const Color(0xffffde79)
          : Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isCurrentPlayer
            ? const Color(0xffffb725)
            : const Color(0xffffd5eb),
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22003583),
          offset: Offset(0, 3),
          blurRadius: 0,
        ),
      ],
    ),
    child: Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(
            rank == null ? 'YOU' : '#$rank',
            style: const TextStyle(
              color: Color(0xff654486),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (rank != null && rank! <= 3)
          Icon(
            rank == 1 ? Icons.workspace_premium_rounded : Icons.star_rounded,
            color: rank == 1
                ? const Color(0xffffb725)
                : const Color(0xfff6538a),
            size: 23,
          )
        else
          const Icon(Icons.person_rounded, color: Color(0xff8d76aa), size: 23),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            isCurrentPlayer ? 'You' : entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff4e385a),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
        const Icon(
          Icons.emoji_events_rounded,
          color: Color(0xffffb725),
          size: 19,
        ),
        const SizedBox(width: 4),
        Text(
          '${entry.score}',
          style: const TextStyle(
            color: Color(0xff654486),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
}

class PublicLeaderboardRankCard extends StatelessWidget {
  const PublicLeaderboardRankCard({super.key, required this.entry});

  final PublicLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffffd5eb), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22003583),
          offset: Offset(0, 3),
          blurRadius: 0,
        ),
      ],
    ),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            '#${entry.rank}',
            style: const TextStyle(
              color: Color(0xff654486),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Icon(
          entry.rank == 1
              ? Icons.workspace_premium_rounded
              : Icons.person_rounded,
          color: entry.rank == 1
              ? const Color(0xffffb725)
              : const Color(0xff8d76aa),
          size: 24,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff4e385a),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'LEVEL ${entry.levelReached}  •  ${entry.totalStars} STARS',
                style: const TextStyle(
                  color: Color(0xff8d76aa),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.emoji_events_rounded,
          color: Color(0xffffb725),
          size: 19,
        ),
        const SizedBox(width: 4),
        Text(
          '${entry.score}',
          style: const TextStyle(
            color: Color(0xff654486),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
}

class BoosterShopScreen extends StatelessWidget {
  const BoosterShopScreen({
    super.key,
    required this.model,
    required this.onBack,
  });

  final AppModel model;
  final VoidCallback onBack;

  static const offers = <ShopOffer>[
    ShopOffer(
      type: BoosterType.bomb,
      price: 100,
      icon: Icons.local_fire_department_rounded,
      color: Color(0xff75536c),
      description: 'Pop candies in a small area.',
    ),
    ShopOffer(
      type: BoosterType.rainbow,
      price: 150,
      icon: Icons.auto_awesome_rounded,
      color: Color(0xff7b5bd1),
      description: 'Pop every candy of one colour.',
    ),
    ShopOffer(
      type: BoosterType.lightning,
      price: 200,
      icon: Icons.bolt_rounded,
      color: Color(0xffffad22),
      description: 'Clear a whole candy row.',
    ),
    ShopOffer(
      type: BoosterType.colorBlast,
      price: 225,
      icon: Icons.color_lens_rounded,
      color: Color(0xffa66bdd),
      description: 'Choose a colour and pop every matching candy.',
    ),
    ShopOffer(
      type: BoosterType.rocket,
      price: 250,
      icon: Icons.rocket_launch_rounded,
      color: Color(0xffff795b),
      description: 'Aim a rocket to clear its whole row.',
    ),
    ShopOffer(
      type: BoosterType.goldenAim,
      price: 100,
      icon: Icons.gps_fixed_rounded,
      color: Color(0xfff6538a),
      description: 'Show a precise guide for 3 shots.',
    ),
    ShopOffer(
      type: BoosterType.extraSwap,
      price: 75,
      icon: Icons.swap_horiz_rounded,
      color: Color(0xff58aeed),
      description: 'Swap the shooter and next candy again.',
    ),
  ];

  @override
  Widget build(BuildContext context) => GradientScaffold(
    child: SafeArea(
      child: Column(
        children: [
          PageHeader(
            title: 'BOOSTER SHOP',
            onBack: onBack,
            trailing: CoinPill(coins: model.coins),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Panel(
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_bag_rounded,
                    color: Color(0xfff6538a),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SWEET POWER-UPS',
                          style: TextStyle(
                            color: Color(0xff654486),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Spend coins earned while popping candies.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final visibleOffers = offers
                    .where((offer) => model.isBoosterUnlocked(offer.type))
                    .toList();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: visibleOffers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final offer = visibleOffers[index];
                    return ShopOfferCard(
                      offer: offer,
                      count: model.boosterCount(offer.type),
                      unlocked: true,
                      unlockLevel: model.boosterUnlockLevel(offer.type),
                      affordable: model.coins >= offer.price,
                      onBuy: () async {
                        final bought = await model.buyBooster(
                          offer.type,
                          offer.price,
                        );
                        if (!context.mounted) return;
                        if (bought) {
                          await showPurchaseSuccess(context, offer);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'You need ${offer.price} coins for ${offer.type.label}.',
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showPurchaseSuccess(BuildContext context, ShopOffer offer) {
  final navigator = Navigator.of(context, rootNavigator: true);
  Future<void>.delayed(const Duration(milliseconds: 1050), () {
    if (navigator.canPop()) navigator.pop();
  });
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Purchase complete',
    barrierColor: Colors.black.withValues(alpha: .18),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => Center(
      child: Material(
        color: Colors.transparent,
        child: _PurchaseSuccessCard(offer: offer),
      ),
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
        child: child,
      ),
    ),
  );
}

class _PurchaseSuccessCard extends StatelessWidget {
  const _PurchaseSuccessCard({required this.offer});

  final ShopOffer offer;

  @override
  Widget build(BuildContext context) => Container(
    width: 224,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    decoration: BoxDecoration(
      color: const Color(0xfffffcf7),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: const Color(0xffffcf59), width: 3),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66002667),
          offset: Offset(0, 7),
          blurRadius: 0,
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: offer.color.withValues(alpha: .18),
            shape: BoxShape.circle,
          ),
          child: Icon(offer.icon, color: offer.color, size: 42),
        ),
        const SizedBox(height: 10),
        const Text(
          'SWEET!',
          style: TextStyle(
            color: Color(0xfff6538a),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${offer.type.label} added!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff654486),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '-${offer.price} coins',
          style: const TextStyle(
            color: Color(0xffd64d72),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class ShopOffer {
  const ShopOffer({
    required this.type,
    required this.price,
    required this.icon,
    required this.color,
    required this.description,
  });

  final BoosterType type;
  final int price;
  final IconData icon;
  final Color color;
  final String description;
}

class ShopOfferCard extends StatelessWidget {
  const ShopOfferCard({
    super.key,
    required this.offer,
    required this.count,
    required this.unlocked,
    required this.unlockLevel,
    required this.affordable,
    required this.onBuy,
  });

  final ShopOffer offer;
  final int count;
  final bool unlocked;
  final int unlockLevel;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) => Panel(
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: offer.color.withValues(alpha: .16),
            shape: BoxShape.circle,
          ),
          child: Icon(offer.icon, color: offer.color, size: 31),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offer.type.label,
                style: const TextStyle(
                  color: Color(0xff654486),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(offer.description, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 5),
              Text(
                unlocked ? 'YOU HAVE ×$count' : 'UNLOCKS AT LEVEL $unlockLevel',
                style: const TextStyle(
                  color: Color(0xfff6538a),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: unlocked && affordable ? onBuy : null,
          style: FilledButton.styleFrom(
            backgroundColor: unlocked
                ? const Color(0xfff6538a)
                : const Color(0xffb9afca),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unlocked ? 'BUY' : 'LOCKED',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                unlocked ? '${offer.price}' : 'LV $unlockLevel',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class LuckySpinDialog extends StatefulWidget {
  const LuckySpinDialog({super.key, required this.model});
  final AppModel model;
  @override
  State<LuckySpinDialog> createState() => _LuckySpinDialogState();
}

class _LuckySpinDialogState extends State<LuckySpinDialog>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  LuckySpinReward? reward;
  double _targetAngle = math.pi * 12;

  Future<void> _spin() async {
    if (!widget.model.canLuckySpin || controller.isAnimating) return;
    final won = await widget.model.luckySpin();
    if (won == null || !mounted) return;
    // End with the selected prize beneath the fixed pointer.
    setState(() {
      _targetAngle = math.pi * 12 - won.index * math.pi * 2 / won.segmentCount;
    });
    controller.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (mounted) setState(() => reward = won);
  }

  @override
  Widget build(BuildContext context) => LuckySpinLayout(
    turns: controller,
    targetAngle: _targetAngle,
    prizes: widget.model.luckySpinPrizes,
    canSpin: widget.model.canLuckySpin,
    reward: reward,
    onSpin: _spin,
    onClose: () => Navigator.pop(context),
  );

  Widget legacyBuild(BuildContext context) => AlertDialog(
    title: const Text('🎡 LUCKY SPIN', textAlign: TextAlign.center),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: controller,
          builder: (_, child) => Transform.rotate(
            angle: controller.value * math.pi * 8,
            child: child,
          ),
          child: Container(
            width: 170,
            height: 170,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xffffd24b),
                  Color(0xfff6538a),
                  Color(0xff8b5bd3),
                  Color(0xff55d69a),
                  Color(0xffffd24b),
                ],
              ),
            ),
            child: const Text(
              '🪙\n💣  🌈\n⚡',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          reward == null
              ? (widget.model.canLuckySpin
                    ? 'One free spin today!'
                    : 'Come back tomorrow!')
              : 'YOU GOT: ${reward!.label}!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: reward != null || !widget.model.canLuckySpin
            ? () => Navigator.pop(context)
            : _spin,
        child: Text(
          reward != null || !widget.model.canLuckySpin ? 'DONE' : 'SPIN',
        ),
      ),
    ],
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class LuckySpinLayout extends StatelessWidget {
  const LuckySpinLayout({
    super.key,
    required this.turns,
    required this.targetAngle,
    required this.prizes,
    required this.canSpin,
    required this.reward,
    required this.onSpin,
    required this.onClose,
  });

  final Animation<double> turns;
  final double targetAngle;
  final List<LuckySpinPrize> prizes;
  final bool canSpin;
  final LuckySpinReward? reward;
  final VoidCallback onSpin;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff5f4bb5), Color(0xff9e73dd), Color(0xfff58fbd)],
          ),
          border: Border.all(color: const Color(0xffffc7dc), width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x660b195d),
              offset: Offset(0, 10),
              blurRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: LuckySpinBackgroundPainter()),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ),
                    const LuckySpinRibbon(),
                    const SizedBox(height: 7),
                    const Text(
                      'Spin the wheel and win sweet rewards!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (_, constraints) => LuckySpinWheel(
                        size: math.min(constraints.maxWidth, 365),
                        turns: turns,
                        targetAngle: targetAngle,
                        prizes: prizes,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        reward != null
                            ? 'YOU WON: ${reward!.label}!'
                            : canSpin
                            ? '1 FREE SPIN DAILY'
                            : 'YOUR FREE SPIN IS READY TOMORROW',
                        key: ValueKey(reward ?? canSpin),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: reward != null
                              ? const Color(0xfffff080)
                              : Colors.white,
                          fontSize: reward != null ? 19 : 13,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(
                              color: Color(0x5500337e),
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 235,
                      height: 58,
                      child: FilledButton(
                        onPressed: reward != null || !canSpin
                            ? onClose
                            : onSpin,
                        style: FilledButton.styleFrom(
                          backgroundColor: reward != null || !canSpin
                              ? const Color(0xff805ca7)
                              : const Color(0xff62bf2e),
                          foregroundColor: Colors.white,
                          elevation: 5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                            side: const BorderSide(
                              color: Color(0xffd7ff9d),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          reward != null || !canSpin ? 'DONE' : 'SPIN',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 17,
                          color: Color(0xffffe783),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          canSpin
                              ? 'Free spin available now!'
                              : 'Resets at midnight',
                          style: const TextStyle(
                            color: Color(0xffffe783),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LuckySpinRibbon extends StatelessWidget {
  const LuckySpinRibbon({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: -12,
        child: Transform.rotate(
          angle: -.16,
          child: Container(
            width: 42,
            height: 38,
            color: const Color(0xffd62d78),
          ),
        ),
      ),
      Positioned(
        right: -12,
        child: Transform.rotate(
          angle: .16,
          child: Container(
            width: 42,
            height: 38,
            color: const Color(0xffd62d78),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xfff34e8b),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xffffa7c4), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55003383),
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: Color(0xffffe259), size: 23),
            SizedBox(width: 7),
            Text(
              'LUCKY SPIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
                shadows: [
                  Shadow(color: Color(0x660f286d), offset: Offset(0, 3)),
                ],
              ),
            ),
            SizedBox(width: 7),
            Icon(Icons.star_rounded, color: Color(0xffffe259), size: 23),
          ],
        ),
      ),
    ],
  );
}

class LuckySpinWheel extends StatelessWidget {
  const LuckySpinWheel({
    super.key,
    required this.size,
    required this.turns,
    required this.prizes,
    this.targetAngle = 0,
  });

  final double size;
  final Animation<double> turns;
  final List<LuckySpinPrize> prizes;
  final double targetAngle;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ...List.generate(12, (index) {
          final angle = -math.pi / 2 + index * math.pi * 2 / 12;
          final radius = size * .475;
          return Positioned(
            left: size / 2 + math.cos(angle) * radius - 5,
            top: size / 2 + math.sin(angle) * radius - 5,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xfffff09d),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0xffffd75c), blurRadius: 7)],
              ),
            ),
          );
        }),
        AnimatedBuilder(
          animation: turns,
          builder: (_, child) => Transform.rotate(
            angle: Curves.easeOutCubic.transform(turns.value) * targetAngle,
            child: child,
          ),
          child: SizedBox.square(
            dimension: size * .9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: LuckyWheelPainter(segmentCount: prizes.length),
                  ),
                ),
                for (var index = 0; index < prizes.length; index++)
                  _LuckyWheelPrizeLabel(
                    prize: prizes[index],
                    index: index,
                    segmentCount: prizes.length,
                    diameter: size * .9,
                    turns: turns,
                    targetAngle: targetAngle,
                  ),
                Container(
                  width: size * .22,
                  height: size * .22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xffffd3e0),
                        Color(0xfff6538a),
                        Color(0xffc73378),
                      ],
                    ),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66003383),
                        offset: Offset(0, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.casino_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: Icon(
            Icons.location_on_rounded,
            color: const Color(0xffffd84a),
            size: size * .18,
          ),
        ),
      ],
    ),
  );
}

class _LuckyWheelPrizeLabel extends StatelessWidget {
  const _LuckyWheelPrizeLabel({
    required this.prize,
    required this.index,
    required this.segmentCount,
    required this.diameter,
    required this.turns,
    required this.targetAngle,
  });

  final LuckySpinPrize prize;
  final int index;
  final int segmentCount;
  final double diameter;
  final Animation<double> turns;
  final double targetAngle;

  @override
  Widget build(BuildContext context) {
    final angle = -math.pi / 2 + index * math.pi * 2 / segmentCount;
    final radius = diameter * .315;
    final labelSize = diameter * .19;
    return Positioned(
      left: diameter / 2 + math.cos(angle) * radius - labelSize / 2,
      top: diameter / 2 + math.sin(angle) * radius - labelSize / 2,
      child: SizedBox(
        width: labelSize,
        height: labelSize,
        child: AnimatedBuilder(
          animation: turns,
          builder: (_, child) => Transform.rotate(
            // The wheel moves the label's position, while this inverse turn
            // keeps its text and icon facing the player.
            angle: -Curves.easeOutCubic.transform(turns.value) * targetAngle,
            child: child,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(prize.icon, color: Colors.white, size: labelSize * .55),
                Text(
                  prize.wheelLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: math.max(8, diameter * .037),
                    height: .98,
                    fontWeight: FontWeight.w900,
                    shadows: const [
                      Shadow(color: Color(0x88003383), offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LuckyWheelPainter extends CustomPainter {
  const LuckyWheelPainter({required this.segmentCount});

  final int segmentCount;

  static const _colors = [
    Color(0xff9552da),
    Color(0xff228ed4),
    Color(0xffffc62c),
    Color(0xffef598d),
    Color(0xff12aaa8),
    Color(0xff63b932),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final slice = math.pi * 2 / segmentCount;
    final wedge = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < segmentCount; index++) {
      wedge.color = _colors[index % _colors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 - slice / 2 + index * slice,
        slice,
        true,
        wedge,
      );
    }
    final divider = Paint()
      ..color = Colors.white.withValues(alpha: .82)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < segmentCount; index++) {
      final angle = -math.pi / 2 - slice / 2 + index * slice;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        divider,
      );
    }
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..shader = const LinearGradient(
        colors: [Color(0xffffb5d3), Color(0xffe43780), Color(0xffffb5d3)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 3, rim);
    canvas.drawCircle(
      center,
      radius + 5,
      Paint()
        ..color = const Color(0xfff6538a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
  }

  @override
  bool shouldRepaint(covariant LuckyWheelPainter oldDelegate) =>
      oldDelegate.segmentCount != segmentCount;
}

class LuckySpinBackgroundPainter extends CustomPainter {
  const LuckySpinBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sparkle = Paint()..color = Colors.white.withValues(alpha: .23);
    for (final point in [
      Offset(size.width * .12, size.height * .19),
      Offset(size.width * .87, size.height * .29),
      Offset(size.width * .18, size.height * .73),
      Offset(size.width * .8, size.height * .82),
    ]) {
      canvas.drawCircle(point, 2.5, sparkle);
      canvas.drawLine(
        point - const Offset(7, 0),
        point + const Offset(7, 0),
        sparkle,
      );
      canvas.drawLine(
        point - const Offset(0, 7),
        point + const Offset(0, 7),
        sparkle,
      );
    }
    final hill = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width * .2,
        size.height * .78,
        size.width * .48,
        size.height,
      )
      ..quadraticBezierTo(
        size.width * .77,
        size.height * .74,
        size.width,
        size.height * .87,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0x445fc848));
  }

  @override
  bool shouldRepaint(covariant LuckySpinBackgroundPainter oldDelegate) => false;
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
  const LollipopLauncher({
    super.key,
    required this.color,
    required this.size,
    this.isBomb = false,
    this.isRocket = false,
  });

  final CandyColor color;
  final double size;
  final bool isBomb;
  final bool isRocket;

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
          child: isBomb
              ? BombCandy(size: size * .82)
              : isRocket
              ? RocketCandy(size: size * .86)
              : CustomPaint(painter: CandySwirlPainter()),
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
  Widget build(BuildContext context) {
    final highlight = Color.lerp(color.color, Colors.white, .72)!;
    final light = Color.lerp(color.color, Colors.white, .28)!;
    final shade = Color.lerp(color.color, Colors.black, .34)!;
    final rim = math.max(1.0, size * .045);

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-.4, -.52),
                  radius: 1.03,
                  colors: [highlight, light, color.color, shade],
                  stops: const [.0, .22, .64, 1],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .9),
                  width: rim,
                ),
                boxShadow: [
                  BoxShadow(
                    color: shade.withValues(alpha: .58),
                    offset: Offset(0, size * .08),
                    blurRadius: size * .025,
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(size * .115),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .23),
                      width: math.max(1, size * .025),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: size * .17,
              top: size * .12,
              child: Transform.rotate(
                angle: -.48,
                child: Container(
                  width: size * .28,
                  height: size * .12,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(size),
                  ),
                ),
              ),
            ),
            CustomPaint(
              size: Size.square(size * .56),
              painter: CandyMarkPainter(color),
            ),
            Positioned(
              right: size * .13,
              bottom: size * .15,
              child: Container(
                width: size * .11,
                height: size * .11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MysteryCandy extends StatelessWidget {
  const MysteryCandy({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffb779f2), Color(0xff6f4ac5)],
      ),
      border: Border.all(color: Colors.white, width: math.max(1, size * .045)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66593a9c),
          offset: Offset(0, 3),
          blurRadius: 0,
        ),
      ],
    ),
    child: Text(
      '?',
      style: TextStyle(
        color: Colors.white,
        fontSize: size * .62,
        height: 1,
        fontWeight: FontWeight.w900,
        shadows: const [Shadow(color: Color(0x66000000), offset: Offset(0, 2))],
      ),
    ),
  );
}

class BombCandy extends StatelessWidget {
  const BombCandy({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: size * .82,
          height: size * .82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-.35, -.38),
              colors: [Color(0xff7b6683), Color(0xff3d3146), Color(0xff1f1727)],
            ),
            border: Border.all(
              color: Colors.white,
              width: math.max(1, size * .045),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55003583),
                offset: Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
        ),
        Positioned(
          top: size * .01,
          right: size * .08,
          child: Transform.rotate(
            angle: .45,
            child: Container(
              width: size * .18,
              height: size * .32,
              decoration: BoxDecoration(
                color: const Color(0xfff5b43d),
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
        ),
        Positioned(
          top: -size * .12,
          right: -size * .04,
          child: Icon(
            Icons.auto_awesome_rounded,
            color: const Color(0xffffd353),
            size: size * .3,
          ),
        ),
      ],
    ),
  );
}

class RocketCandy extends StatelessWidget {
  const RocketCandy({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Transform.rotate(
      angle: -.78,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size * .44,
            height: size * .82,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xffffe776),
                  Color(0xffff875e),
                  Color(0xffe95178),
                ],
              ),
              borderRadius: BorderRadius.circular(size),
              border: Border.all(
                color: Colors.white,
                width: math.max(1, size * .04),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44003583),
                  offset: Offset(0, 2),
                  blurRadius: 0,
                ),
              ],
            ),
          ),
          Positioned(
            top: size * .04,
            child: Icon(
              Icons.change_history_rounded,
              color: const Color(0xffffd353),
              size: size * .36,
            ),
          ),
          Positioned(
            bottom: -size * .12,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: const Color(0xffffd353),
              size: size * .34,
            ),
          ),
        ],
      ),
    ),
  );
}

class RocketRowBlastEffect extends StatelessWidget {
  const RocketRowBlastEffect({
    super.key,
    required this.height,
    required this.animation,
  });

  final double height;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, __) {
      final progress = Curves.easeOut.transform(animation.value);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      return Opacity(
        opacity: opacity,
        child: SizedBox(
          height: height,
          child: Center(
            child: Container(
              height: height * (.14 + progress * .18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: const LinearGradient(
                  colors: [
                    Color(0x00ffde66),
                    Color(0xffffe66d),
                    Color(0xffffffff),
                    Color(0xffff8a55),
                    Color(0x00ff6f63),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xaaffad3d),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class BombBlastEffect extends StatelessWidget {
  const BombBlastEffect({
    super.key,
    required this.size,
    required this.animation,
  });

  final double size;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, __) {
      final progress = Curves.easeOut.transform(animation.value);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final diameter = size * (.22 + progress * .82);
      return SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: opacity,
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xffffd353),
                    width: math.max(2, size * .055),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xffff8b50).withValues(alpha: .6),
                      blurRadius: size * .26,
                      spreadRadius: size * .05,
                    ),
                  ],
                ),
              ),
            ),
            ...List<Widget>.generate(8, (index) {
              final angle = index * math.pi / 4;
              final distance = size * (.06 + progress * .38);
              return Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(math.cos(angle), math.sin(angle)) * distance,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: index.isEven
                        ? const Color(0xffffd353)
                        : const Color(0xffff7a55),
                    size: size * .14,
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
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

class FallingCandyEffect extends StatelessWidget {
  const FallingCandyEffect({
    super.key,
    required this.effect,
    required this.animation,
  });

  final DropEffect effect;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, __) {
      final progress =
          ((animation.value - effect.delay) / math.max(.01, 1 - effect.delay))
              .clamp(0.0, 1.0);
      final fall = Curves.easeIn.transform(progress);
      return Opacity(
        opacity: (1 - fall * .72).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset((fall - .5) * effect.size * .3, fall * 155),
          child: Transform.rotate(
            angle: fall * .55,
            child: CandyBall(color: effect.color, size: effect.size),
          ),
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
        final swirl = Paint()
          ..color = Colors.white.withValues(alpha: .92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .14
          ..strokeCap = StrokeCap.round;
        final outer = Rect.fromLTWH(
          size.width * .08,
          size.height * .08,
          size.width * .84,
          size.height * .84,
        );
        canvas.drawArc(outer, -.35, math.pi * 1.62, false, swirl);
        canvas.drawArc(
          Rect.fromCenter(
            center: center + Offset(size.width * .04, size.height * .02),
            width: size.width * .43,
            height: size.height * .43,
          ),
          math.pi * .15,
          math.pi * 1.65,
          false,
          swirl,
        );
      case CandyColor.grape:
        for (final offset in const [
          Offset(0, -.24),
          Offset(.23, -.06),
          Offset(.14, .2),
          Offset(-.14, .2),
          Offset(-.23, -.06),
        ]) {
          canvas.drawCircle(
            center + Offset(offset.dx * size.width, offset.dy * size.height),
            size.width * .155,
            paint,
          );
        }
        canvas.drawCircle(
          center,
          size.width * .11,
          Paint()..color = color.color.withValues(alpha: .75),
        );
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
    child: Pressable(
      onTap: onTap,
      pressedScale: .96,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xfff65080),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0xffa62f59),
              offset: Offset(0, 5),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 27, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
          ],
        ),
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

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    required this.borderRadius,
    this.pressedScale = .94,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _pressed ? widget.pressedScale : 1,
    duration: const Duration(milliseconds: 90),
    curve: Curves.easeOutCubic,
    child: Material(
      color: Colors.transparent,
      borderRadius: widget.borderRadius,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        borderRadius: widget.borderRadius,
        child: widget.child,
      ),
    ),
  );
}

class RoundIcon extends StatelessWidget {
  const RoundIcon(this.icon, this.onTap, {super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
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

class CoinPill extends StatefulWidget {
  const CoinPill({super.key, required this.coins});

  final int coins;

  @override
  State<CoinPill> createState() => _CoinPillState();
}

class _CoinPillState extends State<CoinPill> {
  late int _previousCoins = widget.coins;

  @override
  void didUpdateWidget(covariant CoinPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coins != widget.coins) _previousCoins = oldWidget.coins;
  }

  @override
  Widget build(BuildContext context) {
    final changed = _previousCoins != widget.coins;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$_previousCoins:${widget.coins}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (_, progress, __) {
        final visibleCoins =
            (_previousCoins + (widget.coins - _previousCoins) * progress)
                .round();
        final bounce = changed ? math.sin(progress * math.pi) * .13 : 0.0;
        final gaining = widget.coins > _previousCoins;
        return Transform.scale(
          scale: 1 + bounce,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: changed
                    ? (gaining
                          ? const Color(0xff69c94e)
                          : const Color(0xfff47b98))
                    : const Color(0xffffd25b),
                width: 2,
              ),
              boxShadow: changed
                  ? [
                      BoxShadow(
                        color:
                            (gaining
                                    ? const Color(0xff69c94e)
                                    : const Color(0xfff47b98))
                                .withValues(alpha: .36 * (1 - progress)),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.monetization_on_rounded,
                  color: gaining && changed
                      ? const Color(0xff5fb63f)
                      : const Color(0xffffb725),
                  size: 19,
                ),
                const SizedBox(width: 4),
                Text(
                  '$visibleCoins',
                  style: const TextStyle(
                    color: Color(0xff9d6a19),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
  Widget build(BuildContext context) => Pressable(
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
  Widget build(BuildContext context) => Pressable(
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

class GameTopHud extends StatelessWidget {
  const GameTopHud({
    super.key,
    required this.level,
    required this.score,
    required this.stars,
    required this.coins,
    required this.onExit,
    required this.onPause,
  });

  final int level;
  final int score;
  final int stars;
  final int coins;
  final VoidCallback onExit;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff5e2e9b), Color(0xff8d54c6)],
      ),
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: const Color(0xffbd8bea), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x55002e75),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Row(
      children: [
        _GameHudRoundButton(icon: Icons.arrow_back_rounded, onTap: onExit),
        const SizedBox(width: 5),
        _GameHudTile(label: 'LEVEL', value: '$level', width: 50),
        const SizedBox(width: 5),
        Expanded(
          child: Container(
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff482576).withValues(alpha: .78),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'SCORE',
                  style: TextStyle(
                    color: Color(0xffffe36b),
                    fontSize: 9,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$score',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(
                    3,
                    (index) => Icon(
                      Icons.star_rounded,
                      color: index < stars
                          ? const Color(0xffffcf3e)
                          : const Color(0xff79549f),
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 5),
        _GameCoinCounter(coins: coins),
        const SizedBox(width: 5),
        _GameHudRoundButton(icon: Icons.pause_rounded, onTap: onPause),
      ],
    ),
  );
}

class _GameHudRoundButton extends StatelessWidget {
  const _GameHudRoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xffff4f85),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xffffc0d5), width: 2),
      ),
      child: Icon(icon, color: Colors.white, size: 25),
    ),
  );
}

class _GameHudTile extends StatelessWidget {
  const _GameHudTile({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xff482576).withValues(alpha: .78),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xffffd8ec),
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _GameCoinCounter extends StatefulWidget {
  const _GameCoinCounter({required this.coins});

  final int coins;

  @override
  State<_GameCoinCounter> createState() => _GameCoinCounterState();
}

class _GameCoinCounterState extends State<_GameCoinCounter> {
  late int _previousCoins = widget.coins;

  @override
  void didUpdateWidget(covariant _GameCoinCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coins != widget.coins) _previousCoins = oldWidget.coins;
  }

  @override
  Widget build(BuildContext context) {
    final changed = _previousCoins != widget.coins;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$_previousCoins:${widget.coins}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (_, progress, __) {
        final visibleCoins =
            (_previousCoins + (widget.coins - _previousCoins) * progress)
                .round();
        return Transform.scale(
          scale: 1 + (changed ? math.sin(progress * math.pi) * .11 : 0),
          child: Container(
            width: 76,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: changed
                    ? (widget.coins > _previousCoins
                          ? const Color(0xff69c94e)
                          : const Color(0xfff47b98))
                    : const Color(0xffffd14c),
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xffffb523),
                  size: 20,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$visibleCoins',
                      style: const TextStyle(
                        color: Color(0xff8d571a),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GameStatusCard extends StatelessWidget {
  const GameStatusCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .93),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffffd7ed), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33003583),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xff7949ad), size: 26),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff654486),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xfff6538a),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Compact miss indicator for the descending-ceiling mechanic. It deliberately
/// stays small so it does not compete with the objective and shots HUD cards.
class MissCounterIndicator extends StatelessWidget {
  const MissCounterIndicator({
    super.key,
    required this.misses,
    required this.threshold,
    required this.dropping,
  });

  final int misses;
  final int threshold;
  final bool dropping;

  @override
  Widget build(BuildContext context) {
    final safeThreshold = math.max(1, threshold);
    return Container(
      width: 86,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xfffff8fc).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffffd7ed), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22003583),
            offset: Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dropping ? 'DROP!' : 'MISSES',
            style: const TextStyle(
              color: Color(0xff654486),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 3,
            children: List<Widget>.generate(safeThreshold, (index) {
              final filled = !dropping && index < misses;
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: filled
                      ? const Color(0xfff6538a)
                      : const Color(0xffffdce9),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xffff9fbe), width: .8),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class CandySlotCard extends StatelessWidget {
  const CandySlotCard({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffffb3d1), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff654486),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    ),
  );
}

class BoosterSlotCard extends StatelessWidget {
  const BoosterSlotCard({
    super.key,
    required this.type,
    required this.count,
    required this.selected,
    this.onTap,
  });

  final BoosterType? type;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 66,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xffffdc68)
            : Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffffb3d1), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type?.label ?? 'BOOST',
            style: const TextStyle(
              color: Color(0xff654486),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(type?.emoji ?? '🎁', style: const TextStyle(fontSize: 22)),
          Text(
            selected ? 'READY ×$count' : '×$count',
            style: const TextStyle(
              color: Color(0xfff6538a),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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

class CollectionTitleRibbon extends StatelessWidget {
  const CollectionTitleRibbon({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: 24,
        child: Transform.rotate(
          angle: -.12,
          child: Container(
            width: 44,
            height: 38,
            color: const Color(0xffd8357c),
          ),
        ),
      ),
      Positioned(
        right: 24,
        child: Transform.rotate(
          angle: .12,
          child: Container(
            width: 44,
            height: 38,
            color: const Color(0xffd8357c),
          ),
        ),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 42),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xfff6538a),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xffffb6d1), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44003583),
              offset: Offset(0, 5),
              blurRadius: 0,
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: Color(0xffffd353), size: 25),
            SizedBox(width: 8),
            Text(
              'COLLECTION',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
                shadows: [
                  Shadow(color: Color(0x66003583), offset: Offset(0, 3)),
                ],
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.star_rounded, color: Color(0xffffd353), size: 25),
          ],
        ),
      ),
    ],
  );
}

class CollectionSpinHero extends StatelessWidget {
  const CollectionSpinHero({
    super.key,
    required this.canSpin,
    required this.prizes,
    required this.onTap,
  });

  final bool canSpin;
  final List<LuckySpinPrize> prizes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    pressedScale: .98,
    borderRadius: BorderRadius.circular(26),
    child: Container(
      height: 258,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33ffffff), Color(0x22ffb1d0)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 4, bottom: 32, child: LollipopDecoration(size: 56)),
          Positioned(right: 4, bottom: 32, child: LollipopDecoration(size: 60)),
          Positioned(
            top: 0,
            child: LuckySpinWheel(
              size: 200,
              turns: const AlwaysStoppedAnimation<double>(0),
              prizes: prizes,
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 7,
            child: Container(
              height: 57,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xfff6538a),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xffffb5cf), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44003583),
                    offset: Offset(0, 5),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.casino_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'LUCKY SPIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (canSpin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff65bd30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'FREE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class CollectionBoosterSummary extends StatelessWidget {
  const CollectionBoosterSummary({super.key, required this.model});

  final AppModel model;

  static const _displayOrder = <BoosterType>[
    BoosterType.bomb,
    BoosterType.goldenAim,
    BoosterType.rainbow,
    BoosterType.lightning,
    BoosterType.colorBlast,
    BoosterType.rocket,
    BoosterType.megaBomb,
  ];

  IconData _iconFor(BoosterType type) => switch (type) {
    BoosterType.bomb || BoosterType.megaBomb => Icons.warning_amber_rounded,
    BoosterType.rainbow => Icons.brightness_5_rounded,
    BoosterType.lightning => Icons.bolt_rounded,
    BoosterType.colorBlast => Icons.color_lens_rounded,
    BoosterType.rocket => Icons.rocket_launch_rounded,
    BoosterType.goldenAim => Icons.gps_fixed_rounded,
    BoosterType.extraSwap => Icons.swap_horiz_rounded,
  };

  Color _colorFor(BoosterType type) => switch (type) {
    BoosterType.bomb || BoosterType.megaBomb => const Color(0xff3d3146),
    BoosterType.rainbow => const Color(0xfff6538a),
    BoosterType.lightning => const Color(0xffffbd2f),
    BoosterType.colorBlast => const Color(0xffa66bdd),
    BoosterType.rocket => const Color(0xffff795b),
    BoosterType.goldenAim => const Color(0xffffad22),
    BoosterType.extraSwap => const Color(0xff58aeed),
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffffd7ed), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33003583),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xff9a66d8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'BOOSTERS',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (_, constraints) {
            final boosters = _displayOrder
                .where(model.isBoosterUnlocked)
                .toList();
            final columns = boosters.length <= 2 ? boosters.length : 3;
            const spacing = 8.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: spacing,
              runSpacing: 10,
              children: [
                for (final type in boosters)
                  SizedBox(
                    width: itemWidth,
                    child: CollectionBoosterStat(
                      icon: _iconFor(type),
                      color: _colorFor(type),
                      label: type.label,
                      count: model.boosterCount(type),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class CollectionBoosterStat extends StatelessWidget {
  const CollectionBoosterStat({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 27),
      Text(
        '$count',
        style: const TextStyle(
          color: Color(0xff654486),
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xff8a778d),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class CollectionRewardCard extends StatelessWidget {
  const CollectionRewardCard({
    super.key,
    required this.name,
    required this.color,
    required this.progress,
    required this.goal,
    required this.unlocked,
  });

  final String name;
  final CandyColor color;
  final int progress;
  final int goal;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final ratio = (progress / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.color.withValues(alpha: .42), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33003583),
            offset: Offset(0, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.color.withValues(alpha: .16),
              shape: BoxShape.circle,
              border: Border.all(color: color.color, width: 3),
            ),
            child: CandyBall(color: color, size: 55),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toUpperCase(),
                  style: TextStyle(
                    color: color.color,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Collect stars and clear levels!',
                  style: TextStyle(
                    color: Color(0xff715f78),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      unlocked ? 'COLLECTED' : 'KEEP PLAYING',
                      style: TextStyle(
                        color: color.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$progress / $goal',
                      style: const TextStyle(
                        color: Color(0xff654486),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 9,
                    backgroundColor: const Color(0xffeee8f0),
                    valueColor: AlwaysStoppedAnimation(color.color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            unlocked ? Icons.card_giftcard_rounded : Icons.lock_rounded,
            color: unlocked ? const Color(0xffffb52c) : const Color(0xff9b919b),
            size: 36,
          ),
        ],
      ),
    );
  }
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
