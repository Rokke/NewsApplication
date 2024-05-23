import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/network.dart';
import 'package:rss_feed_reader/screens/home.dart';
import 'package:window_manager/window_manager.dart';

late final IOSink? _sink;
Future<void> _startLogger(String filepath) async {
  final fs = File('$filepath\\rss_monitor.log');
  if (fs.existsSync()) {
    if (fs.lengthSync() > 100 * 1024) {
      final backupFile = File('$filepath\\rss_monitor_backup.log');
      if (backupFile.existsSync()) backupFile.deleteSync();
      fs.rename('$filepath\\rss_monitor_backup.log');
    }
  }
  _sink = fs.openWrite(mode: FileMode.append);
  Logger.root.level = kDebugMode ? Level.FINEST : Level.FINE;
  Logger.root.onRecord.listen((event) async {
    final logText =
        '${'${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}:${event.time.second.toString().padLeft(2, '0')},${event.time.millisecond} [${event.loggerName}] ${event.level} ${event.message}'}${event.error == null ? '' : ', ERR: ${event.error}'}';
    debugPrint(logText);
    if (Platform.isWindows && _sink != null) {
      try {
        _sink!.writeln(logText);
      } catch (err) {
        debugPrint('log error: $err');
      }
      // } else {
      //   debugPrint(
      //       '${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}:${event.time.second.toString().padLeft(2, '0')},${event.time.millisecond} [${event.loggerName}] ${event.level} ${event.message}\n${event.error != null ? " ${event.error}\n" : ""}');
    }
  });
}

Future<void> main() async {
  final appConfig = ApplicationConfiguration();
  await appConfig.initialize();
  await _startLogger(appConfig.logFilepath);
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  // if (Platform.isWindows) DesktopWindow.setWindowSize(const Size(1000, 1300));
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    });
  }
  runApp(
    ProviderScope(
      overrides: [providerConfig.overrideWith((ref) => appConfig)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple, brightness: Brightness.dark, appBarTheme: AppBarTheme(backgroundColor: Colors.deepPurple[900]), cardColor: Colors.blue[900]),
      darkTheme: ThemeData.from(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark), useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
