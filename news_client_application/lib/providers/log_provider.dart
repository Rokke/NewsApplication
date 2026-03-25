import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final logServiceProvider = Provider<LogService>((ref) => throw Exception('Must be initialized in main'));

class LogService {
  IOSink? _sink;
  String? _logFilePath;

  String? get logFilePath => _logFilePath;

  Future<void> initialize() async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;

    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!logDir.existsSync()) logDir.createSync(recursive: true);

    _logFilePath = '${logDir.path}/news_client.log';
    final file = File(_logFilePath!);

    // Rotate if > 1MB
    if (file.existsSync() && file.lengthSync() > 1024 * 1024) {
      final backup = File('${_logFilePath!}.old');
      if (backup.existsSync()) backup.deleteSync();
      file.renameSync(backup.path);
    }

    _sink = File(_logFilePath!).openWrite(mode: FileMode.append);
    _sink!.writeln('--- Log started ${DateTime.now().toIso8601String()} ---');

    Logger.root.onRecord.listen((record) {
      final line = '${record.time.toIso8601String()} [${record.loggerName}] ${record.level.name} ${record.message}';
      if (kDebugMode) debugPrint(line);
      _sink?.writeln(line);
      if (record.error != null) {
        _sink?.writeln('  Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        _sink?.writeln('  StackTrace: ${record.stackTrace}');
      }
    });
  }

  Future<void> flush() async {
    await _sink?.flush();
  }

  void dispose() {
    _sink?.close();
    _sink = null;
  }
}
