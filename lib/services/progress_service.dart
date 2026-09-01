import 'package:shared_preferences/shared_preferences.dart';

class ProgressService {
  static const _unlocked = 'unlocked';
  static const _coins = 'coins';
  static const _stars = 'stars';
  static const _scores = 'scores';
  static const _sound = 'sound';
  static const _music = 'music';
  static const _haptics = 'haptics';
  static const _bombBoosters = 'bombBoosters';
  static const _rainbowBoosters = 'rainbowBoosters';
  static const _lightningBoosters = 'lightningBoosters';
  static const _colorBlastBoosters = 'colorBlastBoosters';
  static const _rocketBoosters = 'rocketBoosters';
  static const _goldenAimBoosters = 'goldenAimBoosters';
  static const _megaBombBoosters = 'megaBombBoosters';
  static const _extraSwapBoosters = 'extraSwapBoosters';
  static const _claimedChapterRewards = 'claimedChapterRewards';
  static const _seenNewRowTutorial = 'seenNewRowTutorial';
  static const _lastLuckySpin = 'lastLuckySpin';
  static const _guestLastLuckySpin = 'guestLastLuckySpin';

  Future<Map<String, Object>> load() async {
    final p = await SharedPreferences.getInstance();
    return {
      'unlocked': p.getInt(_unlocked) ?? 1,
      'coins': p.getInt(_coins) ?? 125,
      'stars': p.getStringList(_stars) ?? List.filled(20, '0'),
      'scores': p.getStringList(_scores) ?? List.filled(20, '0'),
      'sound': p.getBool(_sound) ?? true,
      'music': p.getBool(_music) ?? true,
      'haptics': p.getBool(_haptics) ?? true,
      'bombBoosters': p.getInt(_bombBoosters) ?? 0,
      'rainbowBoosters': p.getInt(_rainbowBoosters) ?? 0,
      'lightningBoosters': p.getInt(_lightningBoosters) ?? 0,
      'colorBlastBoosters': p.getInt(_colorBlastBoosters) ?? 0,
      'rocketBoosters': p.getInt(_rocketBoosters) ?? 0,
      'goldenAimBoosters': p.getInt(_goldenAimBoosters) ?? 0,
      'megaBombBoosters': p.getInt(_megaBombBoosters) ?? 0,
      'extraSwapBoosters': p.getInt(_extraSwapBoosters) ?? 0,
      'claimedChapterRewards':
          p.getStringList(_claimedChapterRewards) ?? const <String>[],
      'seenNewRowTutorial': p.getBool(_seenNewRowTutorial) ?? false,
      'lastLuckySpin': p.getString(_lastLuckySpin) ?? '',
      'guestLastLuckySpin': p.getString(_guestLastLuckySpin) ?? '',
    };
  }

  Future<void> save({
    required int unlocked,
    required int coins,
    required List<int> stars,
    required List<int> scores,
    required bool sound,
    required bool music,
    required bool haptics,
    required int bombBoosters,
    required int rainbowBoosters,
    required int lightningBoosters,
    required int colorBlastBoosters,
    required int rocketBoosters,
    required int goldenAimBoosters,
    required int megaBombBoosters,
    required int extraSwapBoosters,
    required List<int> claimedChapterRewards,
    required bool seenNewRowTutorial,
    required String lastLuckySpin,
  }) async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt(_unlocked, unlocked),
      p.setInt(_coins, coins),
      p.setStringList(_stars, stars.map((x) => '$x').toList()),
      p.setStringList(_scores, scores.map((x) => '$x').toList()),
      p.setBool(_sound, sound),
      p.setBool(_music, music),
      p.setBool(_haptics, haptics),
      p.setInt(_bombBoosters, bombBoosters),
      p.setInt(_rainbowBoosters, rainbowBoosters),
      p.setInt(_lightningBoosters, lightningBoosters),
      p.setInt(_colorBlastBoosters, colorBlastBoosters),
      p.setInt(_rocketBoosters, rocketBoosters),
      p.setInt(_goldenAimBoosters, goldenAimBoosters),
      p.setInt(_megaBombBoosters, megaBombBoosters),
      p.setInt(_extraSwapBoosters, extraSwapBoosters),
      p.setStringList(
        _claimedChapterRewards,
        claimedChapterRewards.map((id) => '$id').toList(),
      ),
      p.setBool(_seenNewRowTutorial, seenNewRowTutorial),
      p.setString(_lastLuckySpin, lastLuckySpin),
    ]);
  }

  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.remove(_unlocked),
      p.remove(_coins),
      p.remove(_stars),
      p.remove(_scores),
      p.remove(_sound),
      p.remove(_music),
      p.remove(_haptics),
      p.remove(_bombBoosters),
      p.remove(_rainbowBoosters),
      p.remove(_lightningBoosters),
      p.remove(_colorBlastBoosters),
      p.remove(_rocketBoosters),
      p.remove(_goldenAimBoosters),
      p.remove(_megaBombBoosters),
      p.remove(_extraSwapBoosters),
      p.remove(_claimedChapterRewards),
      p.remove(_seenNewRowTutorial),
      p.remove(_lastLuckySpin),
    ]);
  }

  /// Guest players have a temporary game session. Keep their accessibility
  /// preferences and the device-level daily-spin cooldown, but remove all
  /// gameplay progress before the next launch.
  Future<void> clearGuestProgress() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.remove(_unlocked),
      p.remove(_coins),
      p.remove(_stars),
      p.remove(_scores),
      p.remove(_bombBoosters),
      p.remove(_rainbowBoosters),
      p.remove(_lightningBoosters),
      p.remove(_colorBlastBoosters),
      p.remove(_rocketBoosters),
      p.remove(_goldenAimBoosters),
      p.remove(_megaBombBoosters),
      p.remove(_extraSwapBoosters),
      p.remove(_claimedChapterRewards),
      p.remove(_seenNewRowTutorial),
    ]);
  }

  Future<void> saveGuestLuckySpin(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_guestLastLuckySpin, value);
  }
}
