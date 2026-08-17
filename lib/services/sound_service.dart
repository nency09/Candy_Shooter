import 'package:audioplayers/audioplayers.dart';

/// Lightweight pool so rapid candy pops can overlap instead of cutting off.
class SoundService {
  SoundService._();

  static final instance = SoundService._();
  static const _popAsset = 'sounds/dragon_bubble_pop.mp3';
  static const _noMatchAsset = 'sounds/universfield_bubble_pop.mp3';
  static const _shootAsset = 'sounds/candy_pop.wav';

  final _players = List<AudioPlayer>.generate(4, (_) => AudioPlayer());
  var _nextPlayer = 0;

  void playShoot() => _play(_shootAsset, volume: .28);

  void playPop({required int candyCount}) {
    final volume = candyCount >= 6 ? .9 : candyCount >= 4 ? .78 : .68;
    _play(_popAsset, volume: volume);
  }

  void playNoMatch() => _play(_noMatchAsset, volume: .62);

  void _play(String asset, {required double volume}) {
    final player = _players[_nextPlayer++ % _players.length];
    player.play(AssetSource(asset), volume: volume).catchError((_) {});
  }
}
