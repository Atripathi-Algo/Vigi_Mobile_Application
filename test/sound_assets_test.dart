import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/services/sfx.dart';

/// Parses a PCM WAV file: returns (sampleRate, channels, bitsPerSample, samples as -1..1).
({int rate, int channels, int bits, List<double> samples}) readWav(File f) {
  final ByteData d = ByteData.sublistView(f.readAsBytesSync());
  expect(String.fromCharCodes(d.buffer.asUint8List(0, 4)), 'RIFF');
  expect(String.fromCharCodes(d.buffer.asUint8List(8, 4)), 'WAVE');
  int pos = 12;
  int rate = 0, channels = 0, bits = 0;
  List<double> samples = <double>[];
  while (pos + 8 <= d.lengthInBytes) {
    final String id = String.fromCharCodes(d.buffer.asUint8List(d.offsetInBytes + pos, 4));
    final int size = d.getUint32(pos + 4, Endian.little);
    if (id == 'fmt ') {
      expect(d.getUint16(pos + 8, Endian.little), 1, reason: 'PCM');
      channels = d.getUint16(pos + 10, Endian.little);
      rate = d.getUint32(pos + 12, Endian.little);
      bits = d.getUint16(pos + 22, Endian.little);
    } else if (id == 'data') {
      samples = <double>[for (int i = 0; i < size ~/ 2; i++) d.getInt16(pos + 8 + i * 2, Endian.little) / 32768.0];
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  return (rate: rate, channels: channels, bits: bits, samples: samples);
}

void checkSound(File f, {required double maxSeconds}) {
  expect(f.existsSync(), isTrue, reason: '${f.path} is missing');
  final w = readWav(f);
  expect(w.channels, 1, reason: '${f.path} should be mono');
  expect(w.bits, 16, reason: '${f.path} should be 16-bit');
  expect(w.rate, 32000);
  final double secs = w.samples.length / w.rate;
  expect(secs, inInclusiveRange(0.05, maxSeconds), reason: '${f.path} is ${secs.toStringAsFixed(2)} s');
  final double peak = w.samples.map((double x) => x.abs()).reduce((double a, double b) => a > b ? a : b);
  expect(peak, lessThan(0.97), reason: '${f.path} clips (peak $peak)');
  expect(peak, greaterThan(0.3), reason: '${f.path} is too quiet (peak $peak)');
  // Faded ends: nothing should start or stop with a click.
  expect(w.samples.first.abs(), lessThan(0.02), reason: '${f.path} starts with a click');
  expect(w.samples.last.abs(), lessThan(0.02), reason: '${f.path} ends with a click');
  final double mean = w.samples.reduce((double a, double b) => a + b) / w.samples.length;
  expect(mean.abs(), lessThan(0.01), reason: '${f.path} has a DC offset');
}

/// How long each sound may be, from the design's sound table (seconds).
const Map<String, double> _fxMax = <String, double>{'tick': 0.1, 'clear': 0.25, 'engage': 0.75, 'pulse': 1.0, 'deny': 0.3, 'boot': 1.8, 'water': 0.3};
const Map<String, double> _alertMax = <String, double>{'k_critical': 1.4, 'k_ops': 0.4, 'k_sleep': 2.3, 'k_brief': 2.6, 'k_soft': 0.7};

void main() {
  test('every in-app effect has a valid WAV asset, as short as the design says', () {
    for (final Sfx s in Sfx.values) {
      checkSound(File('assets/audio/sfx_${s.name}.wav'), maxSeconds: _fxMax[s.name]!);
    }
  });

  test('every notification channel sound exists, is valid, and has a copy for the Loadout previews', () {
    for (final MapEntry<String, double> e in _alertMax.entries) {
      checkSound(File('android/app/src/main/res/raw/${e.key}.wav'), maxSeconds: e.value);
      checkSound(File('assets/audio/${e.key}.wav'), maxSeconds: e.value);
    }
  });

  test('the sounds are not the old ones, and nothing refers to them', () {
    expect(Directory('assets/audio').listSync().map((FileSystemEntity f) => f.path), everyElement(isNot(contains('bat_'))));
    expect(Directory('android/app/src/main/res/raw').listSync().map((FileSystemEntity f) => f.path), everyElement(isNot(contains('bat_'))));
    expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync(), contains('@raw/k_*'));
    expect(File('lib/services/notifications.dart').readAsStringSync(), isNot(contains('bat_')));
  });

  test('the effects folder is declared as an asset', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/audio/'));
  });

  test('a cold start is the longest sound, and quiet sounds are quiet', () {
    final double boot = readWav(File('assets/audio/sfx_boot.wav')).samples.length / 32000;
    for (final Sfx s in Sfx.values) {
      if (s == Sfx.boot) continue;
      expect(readWav(File('assets/audio/sfx_${s.name}.wav')).samples.length / 32000, lessThan(boot));
    }
    expect(readWav(File('android/app/src/main/res/raw/k_soft.wav')).samples.length / 32000, lessThan(1.0));
  });
}
