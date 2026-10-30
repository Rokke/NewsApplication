import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/network.dart';
import 'package:rss_feed_reader/screens/home.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';
import 'package:rss_feed_reader/utils/log_file.dart';
import 'package:rss_feed_reader/utils/power_events.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _startLogger(String directory) async {
  await AppLog.start(Platform.isWindows ? directory : '', level: kDebugMode ? Level.FINEST : Level.FINE);
  final log = Logger('App');
  final info = await PackageInfo.fromPlatform();
  log.info('start: ${info.appName} ${info.version}+${info.buildNumber}, logs in $directory');
  FlutterError.onError = (details) {
    log.severe('FlutterError: ${details.exceptionAsString()}${details.context == null ? '' : ' (${details.context})'}', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.severe('Uncaught error', error, stack);
    return true;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appConfig = ApplicationConfiguration();
  await appConfig.initialize();
  await _startLogger(appConfig.logDirectory);
  FrameWatch.start();
  if (Platform.isWindows) PowerEvents.start();
  HttpOverrides.global = MyHttpOverrides();
  // if (Platform.isWindows) DesktopWindow.setWindowSize(const Size(1000, 1300));
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setSize(appConfig.windowSize);
      await windowManager.setPosition(appConfig.windowPosition);
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
