import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final providerConfig = ChangeNotifierProvider<ApplicationConfiguration>((ref) => throw Exception('Must be existing ApplicationConfiguration()'));

class ApplicationConfiguration extends ChangeNotifier {
  late String socketServerInternal, socketServerExternal, socketSecret, logFilepath;
  ApplicationConfiguration();
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    socketServerInternal = prefs.getString('socketInternal') ?? '';
    socketServerExternal = prefs.getString('socketExternal') ?? '';
    socketSecret = prefs.getString('socketSecret') ?? '';
    logFilepath = prefs.getString('logFilepath') ?? (kDebugMode ? 'D:\\Temp' : '');
  }

  Future<void> updateSettings({String? socketServerInternal, String? socketServerExternal, String? socketSecret, String? logFilepath}) async {
    final prefs = await SharedPreferences.getInstance();
    if (socketServerInternal != null && socketServerInternal != this.socketServerInternal) prefs.setString('socketInternal', this.socketServerInternal = socketServerInternal);
    if (socketServerExternal != null && socketServerExternal != this.socketServerExternal) prefs.setString('socketExternal', this.socketServerExternal = socketServerExternal);
    if (socketSecret != null && socketSecret != this.socketSecret) prefs.setString('socketSecret', this.socketSecret = socketSecret);
    if (logFilepath != null && logFilepath != this.logFilepath) prefs.setString('logFilepath', this.logFilepath = logFilepath);
    notifyListeners();
  }
}
