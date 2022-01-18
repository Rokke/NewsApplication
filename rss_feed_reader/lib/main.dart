import 'dart:io';

import 'package:desktop_window/desktop_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/network.dart';
import 'package:rss_feed_reader/screens/home.dart';

Future<void> _startLogger(String filepath) async {
  Logger.root.level = kDebugMode ? Level.FINEST : Level.FINE;
  Logger.root.onRecord.listen((event) async {
    debugPrint('${'[${event.loggerName}] ${event.level} ${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}:${event.time.second.toString().padLeft(2, '0')},${event.time.millisecond} ${event.message}'}${event.error == null ? '' : ', ERR: ${event.error}'}');
    if (Platform.isWindows && filepath.isNotEmpty) {
      try {
        final fs = File('$filepath\\rss_monitor_debug.log');
        fs.writeAsString(
          '[${event.loggerName}] ${event.level} ${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}:${event.time.second.toString().padLeft(2, '0')},${event.time.millisecond} ${event.message}\n${event.error != null ? " ${event.error}\n" : ""}',
          mode: FileMode.append,
        );
      } catch (err) {
        debugPrint('log error: $err');
      }
    } else {
      debugPrint('[${event.loggerName}] ${event.level} ${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}:${event.time.second.toString().padLeft(2, '0')},${event.time.millisecond} ${event.message}\n${event.error != null ? " ${event.error}\n" : ""}');
    }
  });
}

Future<void> main() async {
  final appConfig = ApplicationConfiguration();
  await appConfig.initialize();
  await _startLogger(appConfig.logFilepath);
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) DesktopWindow.setWindowSize(const Size(1200, 1100));
  runApp(
    ProviderScope(
      overrides: [providerConfig.overrideWithValue(appConfig)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.deepPurple, brightness: Brightness.dark, appBarTheme: AppBarTheme(backgroundColor: Colors.deepPurple[900]), cardColor: Colors.blue[900]),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
