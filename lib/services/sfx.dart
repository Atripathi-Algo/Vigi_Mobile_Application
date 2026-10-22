import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The in-app sound effects. All are original, synthesized by tools/gen_sounds.py.
enum Sfx {
  /// A light click: tab changes, un-checking.
  tick,

  /// Struck metal and a sonar ping: something cleared or saved.
  clear,

  /// Grapple whoosh into a clink: engaging Deep Ops, arming sleep.
  engage,

  /// Two sub-bass hits and a ping: a session ends, standing down.
  pulse,

  /// Low double buzz: aborting.
  deny,

  /// Drone swell into a visor ping: first launch.
  boot,

  /// Cold droplet: water logged.
  water,
}

/// Plays short effects with low latency. Respects the user's switch and volume in
/// Loadout, mixes with whatever music is playing, and stays silent in silent mode.
abstract final class SfxService {
  static bool enabled = true;
  static double volume = 0.6;
  static final Map<Sfx, AudioPool> _pools = <Sfx, AudioPool>{};
  static bool _ready = false;

  static const List<double> _levels = <double>[0.3, 0.6, 1.0];

  static Future<void> init() async {
    if (_ready) return;
    try {
      await AudioPlayer.global.setAudioContext(AudioContextConfig(
        route: AudioContextConfigRoute.system,
        focus: AudioContextConfigFocus.mixWithOthers,
        respectSilence: true,
        stayAwake: false,
      ).build());
      for (final Sfx s in Sfx.values) {
        _pools[s] = await AudioPool.createFromAsset(path: 'audio/sfx_${s.name}.wav', maxPlayers: 2, playerMode: PlayerMode.lowLatency);
      }
      _ready = true;
    } catch (e) {
      debugPrint('Sound effects unavailable: $e');
    }
  }

  /// [level] is 0 (low), 1 (medium) or 2 (high).
  static void configure({required bool on, required int level}) {
    enabled = on;
    volume = _levels[level.clamp(0, _levels.length - 1)];
  }

  static void play(Sfx s) {
    if (!enabled || !_ready) return;
    _pools[s]?.start(volume: volume).then((_) {}, onError: (Object e) => debugPrint('Sfx ${s.name} failed: $e'));
  }
}
