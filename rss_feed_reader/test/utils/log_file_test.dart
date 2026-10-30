import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rss_feed_reader/utils/log_file.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('rss_log_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> logFiles() => dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  test('rotates while running and keeps at most maxFiles files', () async {
    final log = RotatingLogFile(dir.path, baseName: 'app', maxBytes: 1000, maxFiles: 5);
    await log.open();
    final line = 'x' * 98;
    for (var i = 0; i < 200; i++) {
      log.writeln('$i $line');
    }
    await log.close();

    expect(logFiles(), ['app.1.log', 'app.2.log', 'app.3.log', 'app.4.log', 'app.log']);
    for (final name in logFiles()) {
      expect(File(p.join(dir.path, name)).lengthSync(), lessThan(1200), reason: name);
    }
    // The newest lines are in the current file.
    expect(File(p.join(dir.path, 'app.log')).readAsStringSync(), contains('199 '));
  });

  test('a file already over the limit is rotated at start', () async {
    File(p.join(dir.path, 'app.log')).writeAsStringSync('y' * 2000);
    final log = RotatingLogFile(dir.path, baseName: 'app', maxBytes: 1000);
    await log.open();
    await log.writeln('fresh');
    await log.close();

    expect(File(p.join(dir.path, 'app.1.log')).lengthSync(), 2000);
    expect(File(p.join(dir.path, 'app.log')).readAsStringSync().trim(), 'fresh');
  });

  test('creates the log folder', () async {
    final nested = p.join(dir.path, 'logs', 'rss_feed_reader');
    final log = RotatingLogFile(nested);
    await log.open();
    await log.writeln('hello');
    await log.close();

    expect(File(p.join(nested, 'rss_feed_reader.log')).existsSync(), isTrue);
  });
}
