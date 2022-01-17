// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// final providerApplicationConfiguration = StateProvider<ApplicationConfiguration>((ref) {
//   return ApplicationConfiguration();
// });

// class ApplicationConfiguration extends StateNotifier<ApplicationState> {
//   String _secret = '';
//   ApplicationConfiguration() : super(ApplicationState.loading) {
//     SharedPreferences.getInstance().then(_loaded);
//   }
//   String get secret => _secret;

//   void _loaded(SharedPreferences prefs) {
//     _secret = prefs.getString('MY_SECRET') ?? '';
//     state = ApplicationState.ready;
//   }

//   Future<bool> updateSettings(String secret) async {
//     final prefs = await SharedPreferences.getInstance();
//     prefs.setString('MY_SECRET', secret);
//     return true;
//   }
// }

// enum ApplicationState { loading, ready }
