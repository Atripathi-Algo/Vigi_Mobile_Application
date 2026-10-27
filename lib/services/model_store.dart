import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// The model files K can run, from OpenBMB's own GGUF repository (Apache-2.0).
enum BrainVariant {
  /// Smallest and the default: llama.cpp repacks Q4_K tensors into fast dot-product kernels on a phone CPU.
  q4km('Q4_K_M', 'MiniCPM5-1B-Q4_K_M.gguf', 688000000, 'Recommended. Smallest, fastest, small quality loss.'),

  /// Near-lossless; larger and slower. Use it if the accuracy check shows Q4_K_M misses.
  q8('Q8_0', 'MiniCPM5-1B-Q8_0.gguf', 1150000000, 'Highest accuracy. About 1.7x the size and slower.');

  const BrainVariant(this.label, this.fileName, this.approxBytes, this.note);

  final String label;
  final String fileName;
  final int approxBytes;
  final String note;

  String get url => 'https://huggingface.co/openbmb/MiniCPM5-1B-GGUF/resolve/main/$fileName';

  String get sizeText => approxBytes >= 1000000000 ? '${(approxBytes / 1e9).toStringAsFixed(2)} GB' : '${(approxBytes / 1e6).round()} MB';
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lets the UI stop a download. The partial file is kept so the next attempt resumes where this one stopped.
class DownloadControl {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Where the model files live, and downloading them (resumable, user-started, over plain HTTPS).
class ModelStore {
  ModelStore({Directory? dir, http.Client? client})
      : _dir = dir,
        _client = client;

  final Directory? _dir;
  final http.Client? _client;

  Future<Directory> _models() async {
    final Directory d = _dir ?? Directory('${(await getApplicationSupportDirectory()).path}/models');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(BrainVariant v) async => File('${(await _models()).path}/${v.fileName}');

  Future<File> _part(BrainVariant v) async => File('${(await _models()).path}/${v.fileName}.part');

  /// Path of the finished file, or null if it is not downloaded.
  Future<String?> installedPath(BrainVariant v) async {
    final File f = await _file(v);
    return await f.exists() && await f.length() > 1000000 ? f.path : null;
  }

  /// Bytes already downloaded of an unfinished file.
  Future<int> partialBytes(BrainVariant v) async {
    final File p = await _part(v);
    return await p.exists() ? await p.length() : 0;
  }

  Future<void> delete(BrainVariant v) async {
    for (final File f in <File>[await _file(v), await _part(v)]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// Downloads [v], resuming a partial file. [onProgress] gets bytes so far and the total. Completes when the
  /// file is whole and starts with the GGUF magic; throws [ModelDownloadException] otherwise. A cancelled
  /// download returns normally and keeps its partial file.
  Future<void> download(BrainVariant v, {void Function(int got, int total)? onProgress, DownloadControl? control}) async {
    final http.Client c = _client ?? http.Client();
    try {
      final File part = await _part(v);
      int have = await part.exists() ? await part.length() : 0;
      final http.Request req = http.Request('GET', Uri.parse(v.url))..headers['user-agent'] = 'VIGIL-Android';
      if (have > 0) req.headers['range'] = 'bytes=$have-';
      final http.StreamedResponse res = await c.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 && res.statusCode != 206) throw ModelDownloadException('The download server answered HTTP ${res.statusCode}.');
      final bool resumed = res.statusCode == 206;
      if (!resumed) have = 0; // the server ignored the range: start again
      final int total = _totalFrom(res, have, resumed);
      final IOSink sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      int got = have;
      try {
        await for (final List<int> chunk in res.stream) {
          if (control?.cancelled ?? false) {
            await sink.flush();
            await sink.close();
            return;
          }
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw ModelDownloadException('The download stopped at $got of $total bytes. Try again to resume.');
      final RandomAccessFile raf = await part.open();
      final List<int> magic = await raf.read(4);
      await raf.close();
      if (String.fromCharCodes(magic) != 'GGUF') {
        await part.delete();
        throw const ModelDownloadException('The downloaded file is not a GGUF model.');
      }
      final File out = await _file(v);
      if (await out.exists()) await out.delete();
      await part.rename(out.path);
    } on TimeoutException {
      throw const ModelDownloadException('The download server did not answer. Check the connection and try again.');
    } on SocketException catch (e) {
      throw ModelDownloadException('No connection: ${e.message}. Try again to resume.');
    } on http.ClientException catch (e) {
      throw ModelDownloadException('Connection problem: ${e.message}. Try again to resume.');
    } finally {
      if (_client == null) c.close();
    }
  }

  static int _totalFrom(http.StreamedResponse res, int have, bool resumed) {
    final String? range = res.headers['content-range']; // bytes 100-999/1000
    if (range != null) {
      final int? t = int.tryParse(range.split('/').last);
      if (t != null) return t;
    }
    final int len = res.contentLength ?? -1;
    return len < 0 ? 0 : (resumed ? have + len : len);
  }
}
