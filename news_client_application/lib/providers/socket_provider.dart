import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:news_client_application/models/socket_response.dart';
import 'package:news_client_application/providers/config_provider.dart';

const socketHeadHello = 'CONNECTED:';
const socketVersion = '1.0';

final providerSocket = Provider((ref) {
  final config = ref.watch(providerConfig);
  debugPrint('changed config: ${config.socketServerInternal}');
  final addresses = [config.socketServerInternal, config.socketServerExternal].where((a) => a.isNotEmpty).toList();
  final socket = SocketProvider(serverAddresses: addresses, secret: config.socketSecret, autoConnectTimer: 60000);
  ref.onDispose(() {
    if (!socket.isDisconnected) socket.dispose();
  });
  return socket;
});

class SocketProvider {
  final String _secret;
  SocketProvider({required this.serverAddresses, required String secret, this.port = kDebugMode ? 3344 : 3344, this.autoConnectTimer = 50000}) : _secret = secret {
    assert(autoConnectTimer == 0 || autoConnectTimer > 1000, 'The autoConnectTimer must be >= 1000ms');
    _autoConnectTimer = autoConnectTimer;
    if (isValid) _autoConnect();
  }
  bool get isValid => serverAddresses.isNotEmpty && _secret.isNotEmpty;
  bool get isConnected => status.value == SocketStatus.connected || status.value == SocketStatus.connectedNotRunning || status.value == SocketStatus.connectedRunning;
  bool get isDisconnected => status.value == SocketStatus.disconnected;
  ValueNotifier<SocketStatus> status = ValueNotifier(SocketStatus.disconnected);
  List<String> serverAddresses;
  int indexServerTest = 0;
  int dataLength = 0;
  String dataToParse = '';
  String? connectedAddress;
  late int _autoConnectTimer;
  int autoConnectTimer, port;
  String _serverVersion = '';
  bool exit = false, waitAfterDisconnect = false;
  final StreamController<SocketResponse> _streamController = StreamController();
  Timer? _timer;
  Stream<SocketResponse> get stream => _streamController.stream;
  Socket? _client;
  String get serverVersion => _serverVersion;
  Future<void> _autoConnect() async {
    if (!exit && _autoConnectTimer > 0) {
      if (waitAfterDisconnect || !await connect()) {
        waitAfterDisconnect = false;
        _timer = Timer(Duration(milliseconds: _autoConnectTimer), _autoConnect);
      }
    }
  }

  Future<bool> connect() async {
    _autoConnectTimer = 0;
    if (_client == null) {
      connectedAddress = null;
      try {
        debugPrint('connect: $serverAddresses, $_secret, $port');
        status.value = SocketStatus.waiting;
        try {
          if (indexServerTest >= serverAddresses.length) indexServerTest = 0;
          _client = await Socket.connect(serverAddresses[indexServerTest++], port, timeout: const Duration(milliseconds: 5400));
        } on SocketException catch (err) {
          debugPrint('SocketConnection error: $port, $err, $_client');
        }
        if (_client != null) {
          connectedAddress = serverAddresses[indexServerTest - 1];
          debugPrint('connected: $connectedAddress');
          _client!.listen(_onData, onDone: _onDone, onError: _onError);
          return true;
        }
      } catch (err) {
        debugPrint('Err connecting: $err');
      }
    }
    status.value = SocketStatus.disconnected;
    _autoConnectTimer = indexServerTest >= serverAddresses.length ? autoConnectTimer : 1000;
    _autoConnect();
    return false;
  }

  void _onError(Object error) {
    debugPrint('onError: $error');
    disconnect();
    _autoConnect();
  }

  void _onData(List<int> data) {
    debugPrint('onData init: ${data.length} bytes-${status.value}');
    final utfString = utf8.decode(data);
    if (status.value == SocketStatus.waiting) {
      if (utfString.startsWith(socketHeadHello)) {
        _serverVersion = utfString.split(socketHeadHello).last;
        _client!.write('$socketHeadHello$socketVersion.$_secret');
        _client!.flush();
        status.value = SocketStatus.connected;
      } else {
        debugPrint('Invalid server greeting: "$utfString"');
        _closeConnection();
      }
    } else {
      try {
        if (dataLength == 0) {
          final index = utfString.indexOf(':');
          if (index < 0) {
            debugPrint('_onData: invalid message format (no colon separator)');
            _closeConnection();
            return;
          }
          dataLength = int.parse(utfString.substring(0, index));
          debugPrint('_onData new: $dataLength bytes');
          dataToParse = utfString.substring(index + 1);
        } else {
          debugPrint('_onData continue');
          dataToParse += utf8.decode(data);
        }
        if (dataToParse.length == dataLength) {
          dataLength = 0;
          _parseData();
        } else {
          debugPrint('_onData will continue: $dataLength - ${dataToParse.length}');
        }
      } catch (e) {
        debugPrint('_onData parse error: $e');
        dataLength = 0;
        dataToParse = '';
        _closeConnection();
      }
    }
  }

  void _parseData() {
    final utfString = dataToParse;
    debugPrint('parse!');
    final response = SocketResponse.fromJson(jsonDecode(utfString));
    if (response.running == true) {
      status.value = SocketStatus.connectedRunning;
    } else if (response.running == false) {
      status.value = SocketStatus.connectedNotRunning;
    }
    _streamController.sink.add(response);
  }

  void clientSendData(Map<String, dynamic> json) {
    assert(_client != null, 'Trying to send when no connected clients');
    final strSend = jsonEncode(json);
    debugPrint('_clientSendData: $strSend');
    _client?.write(strSend);
    _client?.flush();
  }

  void _closeConnection() {
    waitAfterDisconnect = true;
    disconnect();
    _autoConnect();
  }

  void _onDone() {
    debugPrint('onDone');
    _closeConnection();
  }

  void dispose() {
    exit = true;
    _streamController.close();
    disconnect();
  }

  void disconnect() {
    debugPrint('disconnect');
    _timer?.cancel();
    _timer = null;
    _client?.close();
    _client?.destroy();
    _client = null;
    _serverVersion = '';
    debugPrint('disconnected');
    status.value = SocketStatus.disconnected;
  }
}

enum SocketStatus { disconnected, connected, connectedRunning, connectedNotRunning, waiting }
