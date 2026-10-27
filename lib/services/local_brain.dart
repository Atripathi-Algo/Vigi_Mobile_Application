import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/cloud_ai.dart';
import '../data/brain_prompt.dart';
import 'local_llm.dart';
import 'model_store.dart';

enum BrainStatus { notInstalled, downloading, ready, loading, busy }

/// K's on-device brain: downloads MiniCPM5-1B, loads it only when needed, answers, and lets go of it again.
///
/// Battery: nothing runs while K is idle. The model is loaded on the first request (or when the microphone opens,
/// so loading overlaps with speaking), is unloaded after a short idle time or when the app has been in the
/// background for a moment, and no service or wake lock is held. Answers are short and schema-constrained.
class LocalBrain extends ChangeNotifier {
  LocalBrain({LocalLlmEngine? engine, ModelStore? store}) : _engine = engine ?? LlamadartEngine(), _store = store ?? ModelStore();

  static final LocalBrain instance = LocalBrain();

  static const String _kEnabled = 'brain_enabled';
  static const String _kVariant = 'brain_variant';
  static const String _kIdle = 'brain_idle_min';
  static const String _kThreads = 'brain_threads';

  final LocalLlmEngine _engine;
  final ModelStore _store;
  SharedPreferences? _prefs;

  bool enabled = true;
  BrainVariant variant = BrainVariant.q4km;

  /// Minutes of silence after which the model is unloaded.
  int idleMinutes = 2;

  /// CPU threads; 0 picks 4, the big cores of a typical phone.
  int threads = 0;

  /// Overrides the idle and background timers (tests).
  @visibleForTesting
  Duration? idleOverride;

  /// How long the app can be in the background before the model is released.
  Duration backgroundGrace = const Duration(seconds: 20);

  String? _path;
  bool _downloading = false;
  bool _loading = false;
  bool _busy = false;
  Timer? _idle;
  Timer? _bgUnload;
  Future<void> _tail = Future<void>.value();

  /// Download progress 0..1 while downloading.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  DownloadControl? _control;
  String? error;

  /// Timings of the last load and answer, for the speed test.
  int? lastLoadMs;
  int? lastFirstTokenMs;
  double? lastTokensPerSecond;

  BrainStatus get status => _downloading
      ? BrainStatus.downloading
      : (_path == null ? BrainStatus.notInstalled : (_busy ? BrainStatus.busy : (_loading ? BrainStatus.loading : BrainStatus.ready)));

  /// True when K can answer on this phone: installed and switched on.
  bool get usable => enabled && _path != null;

  bool get loaded => _engine.loaded;

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    enabled = _prefs!.getBool(_kEnabled) ?? true;
    variant = BrainVariant.values.firstWhere((BrainVariant v) => v.name == _prefs!.getString(_kVariant), orElse: () => BrainVariant.q4km);
    idleMinutes = (_prefs!.getInt(_kIdle) ?? 2).clamp(1, 30);
    threads = _prefs!.getInt(_kThreads) ?? 0;
    await refresh();
  }

  /// Looks again for the model file.
  Future<void> refresh() async {
    _path = await _store.installedPath(variant);
    notifyListeners();
  }

  Future<void> _save() async {
    final SharedPreferences p = _prefs ?? await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setString(_kVariant, variant.name);
    await p.setInt(_kIdle, idleMinutes);
    await p.setInt(_kThreads, threads);
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    if (!v) await unload();
    await _save();
    notifyListeners();
  }

  Future<void> setVariant(BrainVariant v) async {
    if (v == variant) return;
    await unload();
    variant = v;
    await _save();
    await refresh();
  }

  Future<void> setIdleMinutes(int m) async {
    idleMinutes = m;
    await _save();
    _armIdle();
    notifyListeners();
  }

  Future<void> setThreads(int t) async {
    threads = t;
    await unload(); // the next load uses it
    await _save();
    notifyListeners();
  }

  /// Downloads the selected model. Returns an error message, or null on success (or when cancelled).
  Future<String?> download() async {
    if (_downloading) return null;
    _downloading = true;
    error = null;
    progress.value = 0;
    _control = DownloadControl();
    notifyListeners();
    try {
      await _store.download(variant, control: _control, onProgress: (int got, int total) {
        progress.value = total > 0 ? got / total : got / variant.approxBytes;
      });
    } on ModelDownloadException catch (e) {
      error = e.message;
    } finally {
      _downloading = false;
    }
    await refresh();
    return error;
  }

  void cancelDownload() => _control?.cancel();

  Future<int> partialBytes() => _store.partialBytes(variant);

  /// Deletes the downloaded model.
  Future<void> remove() async {
    await unload();
    await _store.delete(variant);
    await refresh();
  }

  Future<void> _ensureLoaded() async {
    if (_engine.loaded) return;
    final String? path = _path;
    if (path == null) throw StateError('not installed');
    _loading = true;
    notifyListeners();
    final Stopwatch sw = Stopwatch()..start();
    try {
      await _engine.load(BrainLoad(path: path, threads: threads == 0 ? 4 : threads));
      lastLoadMs = sw.elapsedMilliseconds;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<T> _serial<T>(Future<T> Function() job) {
    final Completer<T> done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await job());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Loads the model in the background so it is ready when the user finishes speaking.
  Future<void> preload() async {
    if (!usable || _engine.loaded) return;
    try {
      await _serial(() async {
        _idle?.cancel();
        await _ensureLoaded();
        _armIdle();
      });
    } catch (_) {
      // a failed warm-up shows up when the real request is made
    }
  }

  /// Runs the model on [messages] and returns its reply text, or why there is none.
  Future<CloudReply> run(List<BrainTurn> messages, {BrainSampling sampling = const BrainSampling(), Duration timeout = const Duration(seconds: 90)}) {
    if (!usable) {
      return Future<CloudReply>.value(CloudReply.fail(_path == null ? 'K\'s brain is not downloaded yet. Get it in Loadout, K brain.' : 'K\'s brain is switched off.'));
    }
    return _serial(() async {
      _idle?.cancel();
      _busy = true;
      notifyListeners();
      try {
        await _ensureLoaded();
        final StringBuffer out = StringBuffer();
        int pieces = 0;
        final Stopwatch sw = Stopwatch()..start();
        int? firstMs;
        // Consumed in its own future so a stuck generation can be abandoned: cancelling a stream that is not
        // yielding would otherwise wait for it forever.
        final Future<void> consume = () async {
          await for (final String piece in _engine.generate(messages, schema: kBrainSchema, sampling: sampling)) {
            firstMs ??= sw.elapsedMilliseconds;
            out.write(piece);
            pieces++;
          }
        }();
        bool timedOut = false;
        await Future.any(<Future<void>>[
          consume,
          Future<void>.delayed(timeout).then((_) => timedOut = true),
        ]);
        if (timedOut) {
          consume.ignore();
          _engine.cancel();
          // Drop the model so the next request starts clean rather than inheriting a half-finished one.
          try {
            await _engine.unload().timeout(const Duration(seconds: 5));
          } catch (_) {}
          return const CloudReply.fail('K took too long and was stopped.');
        }
        final int ms = sw.elapsedMilliseconds;
        lastFirstTokenMs = firstMs;
        lastTokensPerSecond = pieces > 1 && ms > (firstMs ?? 0) ? (pieces - 1) * 1000 / (ms - (firstMs ?? 0)) : null;
        final String text = out.toString().trim();
        if (text.isEmpty) return const CloudReply.fail('K produced no answer. Try again.');
        return CloudReply.ok(text, model: 'MiniCPM5-1B ${variant.label}');
      } catch (e) {
        // A model that fails to load or run is dropped, so the next try starts clean.
        try {
          await _engine.unload();
        } catch (_) {}
        return CloudReply.fail('K\'s brain failed: ${e.toString().split('\n').first}');
      } finally {
        _busy = false;
        _armIdle();
        notifyListeners();
      }
    });
  }

  /// One request for the assistant: the facts and question go through the prompt builder, then the model.
  Future<CloudReply> ask(BrainFacts facts, String question, List<(bool, String)> history) =>
      run(buildBrainMessages(facts, question, history));

  void _armIdle() {
    _idle?.cancel();
    if (!_engine.loaded) return;
    _idle = Timer(idleOverride ?? Duration(minutes: idleMinutes), () => unload());
  }

  Future<void> unload() async {
    _idle?.cancel();
    if (!_engine.loaded) return;
    // Wait for a running answer to finish rather than pulling the model from under it.
    await _serial(() => _engine.unload());
    notifyListeners();
  }

  /// The app went to the background: let go of the model after a short grace period.
  void onBackground() {
    _bgUnload?.cancel();
    _bgUnload = Timer(idleOverride ?? backgroundGrace, () => unload());
  }

  void onForeground() => _bgUnload?.cancel();
}
