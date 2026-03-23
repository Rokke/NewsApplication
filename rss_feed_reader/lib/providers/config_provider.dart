import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

final providerConfig = ChangeNotifierProvider<ApplicationConfiguration>((ref) => throw Exception('Must be existing ApplicationConfiguration()'));

class ApplicationConfiguration extends ChangeNotifier {
  final _log = Logger('ApplicationConfiguration');
  late String socketServerInternal, socketServerExternal, socketSecret, logFilepath;
  late Size _windowSize;
  late Offset _windowPosition;
  late double _firstPercentage;
  int _lastWindowOffsetChange = 0, _lastPercentageChange = 0;
  ApplicationConfiguration();
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    socketServerInternal = prefs.getString('socketInternal') ?? '';
    socketServerExternal = prefs.getString('socketExternal') ?? '';
    socketSecret = prefs.getString('socketSecret') ?? '';
    final size = prefs.getString('windowSize');
    _windowSize = size != null ? Size(double.parse(size.split(',')[0]), double.parse(size.split(',')[1])) : Size(900, 1024);
    final position = prefs.getString('windowPosition');
    _windowPosition = position != null ? Offset(double.parse(position.split(',')[0]), double.parse(position.split(',')[1])) : Offset(10, 10);
    _firstPercentage = prefs.getDouble('firstPercentage') ?? 0.5;
    logFilepath = prefs.getString('logFilepath') ?? (kDebugMode ? 'D:\\Temp' : '');
  }

  Size get windowSize => _windowSize;
  Offset get windowPosition => _windowPosition;
  List<double> get percentages => [_firstPercentage, 1 - _firstPercentage];
  Future<void> updateSettings({String? socketServerInternal, String? socketServerExternal, String? socketSecret, String? logFilepath}) async {
    final prefs = await SharedPreferences.getInstance();
    if (socketServerInternal != null && socketServerInternal != this.socketServerInternal) prefs.setString('socketInternal', this.socketServerInternal = socketServerInternal);
    if (socketServerExternal != null && socketServerExternal != this.socketServerExternal) prefs.setString('socketExternal', this.socketServerExternal = socketServerExternal);
    if (socketSecret != null && socketSecret != this.socketSecret) prefs.setString('socketSecret', this.socketSecret = socketSecret);
    if (logFilepath != null && logFilepath != this.logFilepath) prefs.setString('logFilepath', this.logFilepath = logFilepath);
    notifyListeners();
  }

  // Future<void> updateWindowSize(Size size) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   prefs.setString('windowSize', '${size.width},${size.height}');
  //   _windowSize = size;
  // }
  Future<void> updatePercentage(double percentage) async {
    _firstPercentage = percentage;
    final myChange = _lastPercentageChange = DateTime.now().millisecondsSinceEpoch;
    Future.delayed(Duration(seconds: 2), () async {
      if (_lastPercentageChange == myChange) {
        final prefs = await SharedPreferences.getInstance();
        prefs.setDouble('firstPercentage', _firstPercentage);
        _log.info('updatePercentage($percentage)');
      }
    });
  }

  void checkWindowSize() {
    if (!kIsWeb && Platform.isWindows) {
      () async {
        final currentSize = await windowManager.getSize();
        final currentPosition = await windowManager.getPosition();
        bool hasChanged = false;
        if (_windowSize != currentSize) {
          _windowSize = currentSize;
          hasChanged = true;
        }
        if (_windowPosition != currentPosition) {
          _windowPosition = currentPosition;
          hasChanged = true;
        }
        if (hasChanged) {
          final myChangeTime = _lastWindowOffsetChange = DateTime.now().millisecondsSinceEpoch;
          Future.delayed(Duration(seconds: 1), () async {
            if (myChangeTime == _lastWindowOffsetChange) {
              final prefs = await SharedPreferences.getInstance();
              prefs.setString('windowSize', '${_windowSize.width},${_windowSize.height}');
              prefs.setString('windowPosition', '${_windowPosition.dx},${_windowPosition.dy}');
              _log.info('checkWindowSize()-Saving window size: $_windowSize, position: $_windowPosition');
            }
          });
        }
      }();
    }
  }

  @override
  String toString() => 'ApplicationConfiguration($socketServerInternal,$socketServerExternal,$logFilepath)';
}
