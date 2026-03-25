import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final providerConfig = ChangeNotifierProvider<ApplicationConfiguration>((ref) => throw Exception('Must be existing ApplicationConfiguration()'));

class ApplicationConfiguration extends ChangeNotifier {
  final _log = Logger('ApplicationConfiguration');
  late String socketServerInternal, socketServerExternal, socketSecret, logFilepath;
  ApplicationConfiguration();
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    socketServerInternal = prefs.getString('socketInternal') ?? '';
    socketServerExternal = prefs.getString('socketExternal') ?? '';
    socketSecret = prefs.getString('socketSecret') ?? '';
    logFilepath = prefs.getString('logFilepath') ?? ((kDebugMode && Platform.isWindows) ? 'D:\\Temp' : '');
    _log.info('Loaded - internal: $socketServerInternal, external: $socketServerExternal, hasSecret: ${socketSecret.isNotEmpty}');
  }

  Future<void> updateSettings({String? socketServerInternal, String? socketServerExternal, String? socketSecret, String? logFilepath}) async {
    final prefs = await SharedPreferences.getInstance();
    if (socketServerInternal != null && socketServerInternal != this.socketServerInternal) prefs.setString('socketInternal', this.socketServerInternal = socketServerInternal);
    if (socketServerExternal != null && socketServerExternal != this.socketServerExternal) prefs.setString('socketExternal', this.socketServerExternal = socketServerExternal);
    if (socketSecret != null && socketSecret != this.socketSecret) prefs.setString('socketSecret', this.socketSecret = socketSecret);
    if (logFilepath != null && logFilepath != this.logFilepath) prefs.setString('logFilepath', this.logFilepath = logFilepath);
    _log.info('Settings updated - internal: ${this.socketServerInternal}, external: ${this.socketServerExternal}, hasSecret: ${this.socketSecret.isNotEmpty}');
    notifyListeners();
  }
}
