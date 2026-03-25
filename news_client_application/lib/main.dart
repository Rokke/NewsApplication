import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:news_client_application/home.dart';
import 'package:news_client_application/providers/config_provider.dart';
import 'package:news_client_application/providers/log_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = Logger('main');

  final logService = LogService();
  await logService.initialize();
  log.info('App starting');

  final appConfig = ApplicationConfiguration();
  await appConfig.initialize();
  log.info('Config loaded - serverInternal: ${appConfig.socketServerInternal}, serverExternal: ${appConfig.socketServerExternal}');

  runApp(ProviderScope(
    overrides: [
      providerConfig.overrideWith((ref) => appConfig),
      logServiceProvider.overrideWithValue(logService),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'New',
      theme: ThemeData(primarySwatch: Colors.blue),
      darkTheme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(backgroundColor: Colors.deepPurple[900]),
        bottomAppBarTheme: BottomAppBarTheme.of(context).copyWith(color: Colors.deepPurple[900]),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}
