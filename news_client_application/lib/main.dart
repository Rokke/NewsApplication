import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:news_client_application/home.dart';
import 'package:news_client_application/providers/config_provider.dart';

void main() async {
  final appConfig = ApplicationConfiguration();
  await appConfig.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [providerConfig.overrideWithValue(appConfig)],
    child: MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'New',
      theme: ThemeData(primarySwatch: Colors.blue),
      darkTheme: ThemeData(primarySwatch: Colors.deepPurple, brightness: Brightness.dark, appBarTheme: AppBarTheme(backgroundColor: Colors.deepPurple[900]), bottomAppBarColor: Colors.deepPurple[900]),
      themeMode: ThemeMode.dark,
      home: HomePage(),
    );
  }
}
