import 'package:shared_preferences/shared_preferences.dart';

class ProgressService {
  static const _unlocked = 'unlocked';
  static const _coins = 'coins';
  static const _stars = 'stars';
  static const _scores = 'scores';
  static const _sound = 'sound';
  static const _music = 'music';
  static const _haptics = 'haptics';

  Future<Map<String, Object>> load() async {
    final p = await SharedPreferences.getInstance();
    return {
      'unlocked': p.getInt(_unlocked) ?? 1,
      'coins': p.getInt(_coins) ?? 125,
      'stars': p.getStringList(_stars) ?? List.filled(10, '0'),
      'scores': p.getStringList(_scores) ?? List.filled(10, '0'),
      'sound': p.getBool(_sound) ?? true,
      'music': p.getBool(_music) ?? true,
      'haptics': p.getBool(_haptics) ?? true,
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
    ]);
  }
}
