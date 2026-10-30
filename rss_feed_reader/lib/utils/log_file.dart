import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Rotating log file. Writes go through one queue, so a rotation never
/// overlaps a write, and the file is rotated while the app runs whenever it
/// grows past [maxBytes]: `name.log` -> `name.1.log` ... `name.<maxFiles-1>.log`.
class RotatingLogFile {
  final String directory;
  final String baseName;
  final int maxBytes;
  final int maxFiles;
  IOSink? _sink;
  int _size = 0;
  Future<void> _queue = Future.value();
  bool _closed = false;

  RotatingLogFile(this.directory, {this.baseName = 'rss_feed_reader', this.maxBytes = 5 * 1024 * 1024, this.maxFiles = 5});

  String get path => p.join(directory, '$baseName.log');
  String _rotatedPath(int n) => p.join(directory, '$baseName.$n.log');

  Future<void> open() => _enqueue(() async {
        await Directory(directory).create(recursive: true);
        final file = File(path);
        _size = await file.exists() ? await file.length() : 0;
        if (_size >= maxBytes) await _rotate();
        _openSink();
      });

  void _openSink() => _sink = File(path).openWrite(mode: FileMode.append);

  Future<void> _rotate() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    for (var n = maxFiles - 1; n >= 1; n--) {
      final from = File(n == 1 ? path : _rotatedPath(n - 1));
      if (!await from.exists()) continue;
      final to = File(_rotatedPath(n));
      if (await to.exists()) await to.delete();
      await from.rename(to.path);
    }
    _size = 0;
  }

  /// Queues [line]; returns when it has been handed to the file.
  Future<void> writeln(String line) => _enqueue(() async {
        if (_closed) return;
        if (_size >= maxBytes) {
          await _rotate();
          _openSink();
        }
        final sink = _sink;
        if (sink == null) return;
        sink.writeln(line);
        _size += line.length + 2;
      });

  Future<void> flush() => _enqueue(() async => await _sink?.flush());

  Future<void> close() => _enqueue(() async {
        _closed = true;
        await _sink?.flush();
        await _sink?.close();
        _sink = null;
      });

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((Object err) {
      // Never let one failed write stop all later ones.
      stderr.writeln('log file error: $err');
    });
    _queue = next;
    return next;
  }
}

/// The app's log file, fed from `Logger.root`.
class AppLog {
  static RotatingLogFile? _file;

  static String _format(LogRecord event) {
    final t = event.time;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)},${t.millisecond.toString().padLeft(3, '0')} [${event.loggerName}] ${event.level} ${event.message}'
        '${event.error == null ? '' : ', ERR: ${event.error}'}${event.stackTrace == null ? '' : '\n${event.stackTrace}'}';
  }

  static Future<void> start(String directory, {Level level = Level.FINE}) async {
    Logger.root.level = level;
    if (directory.isNotEmpty) {
      final file = RotatingLogFile(directory);
      try {
        await file.open();
        _file = file;
      } catch (err) {
        debugPrint('AppLog.start($directory) failed: $err');
      }
    }
    Logger.root.onRecord.listen((event) {
      final logText = _format(event);
      debugPrint(logText);
      _file?.writeln(logText);
    });
  }

  /// Logs [reason] and flushes the file; call before the process exits.
  static Future<void> shutdown(String reason) async {
    Logger('App').info('exit: $reason');
    await _file?.close();
    _file = null;
  }
}
