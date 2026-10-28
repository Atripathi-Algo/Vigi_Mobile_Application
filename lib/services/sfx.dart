import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The in-app sound effects, in a thunder family. All are original, synthesized by tools/gen_thunder.py.
enum Sfx {
  /// Spark: a tiny static tick for taps, tab changes, un-checking.
  tick,

  /// Strike: a clean crack for something cleared or saved.
  clear,

  /// Charge: a rising electric hum into a snap, for engaging Deep Ops or waking K.
  engage,

  /// Rumble: a soft low thunder pulse under K while it thinks, and when a session ends.
  pulse,

  /// Fizzle: a short dull zap for denied or invalid.
  deny,

  /// Thunderclap: a full clap with a rolling tail, on a cold start only.
  boot,

  /// Droplet and a faint crackle: water logged.
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
      // One sound failing to load must not silence the rest.
      for (final Sfx s in Sfx.values) {
        try {
          _pools[s] = await AudioPool.createFromAsset(path: 'audio/sfx_${s.name}.wav', maxPlayers: 2, playerMode: PlayerMode.lowLatency);
        } catch (e) {
          debugPrint('Sound ${s.name} did not load: $e');
        }
      }
      _ready = _pools.isNotEmpty;
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
    final AudioPool? pool = _pools[s];
    if (pool == null) {
      preview('sfx_${s.name}', volume: volume);
      return;
    }
    // If the low-latency pool cannot start, fall back to a normal player.
    pool.start(volume: volume).then((_) {}, onError: (Object e) {
      debugPrint('Sfx ${s.name} failed: $e');
      preview('sfx_${s.name}', volume: volume);
    });
  }

  static AudioPlayer? _previewPlayer;

  /// Plays `assets/audio/[asset].wav` once on the media stream, whatever the effects switch says. This is what
  /// the Loadout previews use, so they are audible at media volume even when the effect pools or notification
  /// channels are not. Returns a message when playback fails, null when it started.
  static Future<String?> preview(String asset, {double volume = 1}) async {
    try {
      final AudioPlayer? old = _previewPlayer;
      _previewPlayer = null;
      if (old != null) {
        await old.stop();
        await old.dispose();
      }
      final AudioPlayer p = AudioPlayer();
      _previewPlayer = p;
      await p.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers, respectSilence: false).build());
      await p.setReleaseMode(ReleaseMode.stop);
      await p.play(AssetSource('audio/$asset.wav'), volume: volume);
      return null;
    } catch (e) {
      debugPrint('Preview $asset failed: $e');
      return 'Could not play the sound: ${e.toString().split('\n').first}';
    }
  }
}
