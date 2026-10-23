import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceState { idle, listening, thinking, speaking }

/// Text as a speech engine should read it: symbols and units spelled out, markdown dropped.
String speakable(String text) {
  String s = text;
  s = s.replaceAll(RegExp(r'[*_`#>]+'), '');
  s = s.replaceAllMapped(RegExp(r'₹\s*([\d,]+(?:\.\d+)?)'), (Match m) => '${m[1]!.replaceAll(',', '')} rupees');
  s = s.replaceAllMapped(RegExp(r'(\d)\s*ml\b', caseSensitive: false), (Match m) => '${m[1]} millilitres');
  s = s.replaceAllMapped(RegExp(r'(\d)\s*L\b'), (Match m) => '${m[1]} litres');
  s = s.replaceAllMapped(RegExp(r'(\d)\s*[–\-]\s*(\d)'), (Match m) => '${m[1]} to ${m[2]}');
  s = s.replaceAll('×', ' versus ').replaceAll('→', ' to ').replaceAll('·', ',').replaceAll('•', ',').replaceAll('…', '...');
  s = s.replaceAll(RegExp(r'\s*\n+\s*'), '. ').replaceAll(RegExp(r'\s{2,}'), ' ');
  return s.trim();
}

/// Speech in and out, using the phone's own engines: Android's speech recognition for listening and its
/// text-to-speech voices for speaking. Both are free; the phone's recogniser may use the network unless an
/// offline language pack is installed.
class VoiceService extends ChangeNotifier {
  VoiceService();

  static final VoiceService instance = VoiceService();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  /// What has been heard so far in the current utterance.
  String partial = '';

  /// Why voice is unavailable or just failed, or null.
  String? error;

  /// 0..1 loudness of the microphone while listening.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  bool _sttReady = false;
  bool _ttsReady = false;
  void Function(String text)? _onFinal;
  bool _delivered = false;
  Completer<void>? _speaking;

  void _set(VoiceState s) {
    if (_state == s) return;
    _state = s;
    if (s != VoiceState.listening) level.value = 0;
    notifyListeners();
  }

  void setThinking(bool on) {
    if (on) {
      _set(VoiceState.thinking);
    } else if (_state == VoiceState.thinking) {
      _set(VoiceState.idle);
    }
  }

  Future<bool> _initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    } catch (e) {
      _sttReady = false;
      error = 'Speech recognition failed to start: ${e.toString().split('\n').first}';
    }
    if (!_sttReady) error ??= 'Speech recognition is not available. Allow the microphone, and make sure Google speech services are installed.';
    return _sttReady;
  }

  /// Listens for one utterance and calls [onFinal] with it. Returns false (with [error] set) if it cannot start.
  Future<bool> listen(void Function(String text) onFinal, {bool onDevice = false}) async {
    error = null;
    if (_state == VoiceState.listening) return true;
    await stopSpeaking();
    if (!await _initStt()) {
      notifyListeners();
      return false;
    }
    partial = '';
    _delivered = false;
    _onFinal = onFinal;
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: (double db) => level.value = ((db + 2) / 12).clamp(0.0, 1.0),
        listenOptions: SpeechListenOptions(listenFor: const Duration(seconds: 40), pauseFor: const Duration(seconds: 3), partialResults: true, cancelOnError: true, onDevice: onDevice, listenMode: ListenMode.dictation),
      );
    } catch (e) {
      error = 'Could not listen: ${e.toString().split('\n').first}';
      notifyListeners();
      return false;
    }
    _set(VoiceState.listening);
    return true;
  }

  void _onResult(SpeechRecognitionResult r) {
    partial = r.recognizedWords;
    notifyListeners();
    if (r.finalResult) _deliver();
  }

  void _onStatus(String status) {
    // The recogniser stops by itself after a pause; hand over whatever it heard.
    if ((status == 'done' || status == 'notListening') && _state == VoiceState.listening) _deliver();
  }

  void _onError(SpeechRecognitionError e) {
    if (_state != VoiceState.listening) return;
    final bool silent = e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout';
    if (!silent) error = 'Speech recognition error: ${e.errorMsg}';
    _deliver();
  }

  void _deliver() {
    if (_delivered) return;
    _delivered = true;
    final String text = partial.trim();
    final void Function(String)? cb = _onFinal;
    _onFinal = null;
    _set(VoiceState.idle);
    if (text.isNotEmpty) cb?.call(text);
  }

  /// Stops listening and delivers what was heard so far.
  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;
    try {
      await _stt.stop();
    } catch (_) {}
    _deliver();
  }

  /// Stops listening without delivering anything.
  Future<void> cancelListening() async {
    if (_state != VoiceState.listening) return;
    _onFinal = null;
    _delivered = true;
    try {
      await _stt.cancel();
    } catch (_) {}
    _set(VoiceState.idle);
  }

  Future<void> _initTts() async {
    if (_ttsReady) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(0.92);
      // A British voice suits the character; fall back to whatever the phone has.
      final dynamic gb = await _tts.isLanguageAvailable('en-GB');
      await _tts.setLanguage(gb == true || gb == 1 ? 'en-GB' : 'en-US');
      _tts.setCompletionHandler(() => _finishSpeaking());
      _tts.setCancelHandler(() => _finishSpeaking());
      _tts.setErrorHandler((dynamic m) {
        error = 'Spoken replies failed: $m';
        _finishSpeaking();
      });
      _ttsReady = true;
    } catch (e) {
      error = 'Spoken replies are not available: ${e.toString().split('\n').first}';
    }
  }

  void _finishSpeaking() {
    if (_state == VoiceState.speaking) _set(VoiceState.idle);
    final Completer<void>? c = _speaking;
    _speaking = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Reads [text] aloud and completes when it has finished (or was interrupted).
  Future<void> speak(String text) async {
    final String s = speakable(text);
    if (s.isEmpty) return;
    await _initTts();
    if (!_ttsReady) {
      notifyListeners();
      return;
    }
    await cancelListening();
    final Completer<void> done = Completer<void>();
    _speaking = done;
    _set(VoiceState.speaking);
    try {
      await _tts.speak(s);
    } catch (e) {
      error = 'Spoken replies failed: ${e.toString().split('\n').first}';
      _finishSpeaking();
    }
    // With awaitSpeakCompletion the call above returns at the end; the handler covers engines that return early.
    await done.future.timeout(const Duration(seconds: 90), onTimeout: _finishSpeaking);
  }

  Future<void> stopSpeaking() async {
    if (_state != VoiceState.speaking) return;
    try {
      await _tts.stop();
    } catch (_) {}
    _finishSpeaking();
  }

  Future<void> stopAll() async {
    await cancelListening();
    await stopSpeaking();
    if (_state == VoiceState.thinking) _set(VoiceState.idle);
  }
}
