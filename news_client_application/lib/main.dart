import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:news_client_application/home.dart';
import 'package:news_client_application/providers/config_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appConfig = ApplicationConfiguration();
  await appConfig.initialize();
  runApp(ProviderScope(overrides: [providerConfig.overrideWith((ref) => appConfig)], child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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
