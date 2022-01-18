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
  NetworkInterface.list().then((value) {
    for (var interface in value) {
      debugPrint('== Interface: ${interface.name} ==');
      for (var addr in interface.addresses) {
        debugPrint('${addr.address} ${addr.host} ${addr.isLoopback} ${addr.rawAddress} ${addr.type.name}');
      }
    }
  });
  final config = ref.watch(providerConfig);
  debugPrint('changed config: ${config.socketServerInternal}');
  final socket = SocketProvider(serverAddresses: [config.socketServerInternal, config.socketServerExternal], secret: config.socketSecret, autoConnectTimer: 10000);
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
  _autoConnect() async {
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
        debugPrint('connect: $serverAddresses, $_secret');
        status.value = SocketStatus.waiting;
        try {
          if (indexServerTest >= serverAddresses.length) indexServerTest = 0;
          _client = await Socket.connect(serverAddresses[indexServerTest++], port, timeout: const Duration(milliseconds: 2400));
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

  _onError(error) {
    debugPrint('onError: $error');
    disconnect();
    _autoConnect();
  }

  _onData(List<int> data) {
    // Completer<String>().complete(utfString);
    debugPrint('onData init: ${data.length} bytes-${status.value}');
    final utfString = utf8.decode(data);
    // debugPrint('onData init: $utfString');
    if (status.value == SocketStatus.waiting) {
      // final utfString = utf8.decode(data);
      if (utfString.startsWith(socketHeadHello)) {
        _serverVersion = utfString.split(socketHeadHello).last;
        _client!.write('$socketHeadHello:$socketVersion.$_secret');
        _client!.flush();
        status.value = SocketStatus.connected;
      } else {
        debugPrint('Invalid client request: "$utfString" != "$socketHeadHello"');
        _closeConnection();
      }
    } else {
      if (dataLength == 0) {
        final index = utfString.indexOf(':');
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
    }
  }

  _parseData() {
    final utfString = dataToParse;
    // debugPrint('_parseData($utfString), $status');
    // if (status.value == SocketStatus.WAITING) {
    //   if (utfString.startsWith('$_SOCKET_HEADHELLO')) {
    //     _serverVersion = utfString.split('$_SOCKET_HEADHELLO').last;
    //     _client!.write('$_SOCKET_HEADHELLO:$_SOCKET_VERSION.SOMESUpERSECRET KEY');
    //     _client!.flush();
    //     status.value = SocketStatus.CONNECTED;
    //   } else {
    //     debugPrint('Invalid client request: "$utfString" != "$_SOCKET_HEADHELLO"');
    //     _closeConnection();
    //   }
    // } else {
    debugPrint('parse!');
    // debugPrint('OBJ: ${jsonDecode(utfString)}');
    final response = SocketResponse.fromJson(jsonDecode(utfString));
    if (response.running == true) {
      status.value = SocketStatus.connectedRunning;
    } else if (response.running == false) {
      status.value = SocketStatus.connectedNotRunning;
    }
    _streamController.sink.add(response);
    // }
  }

  clientSendData(Map<String, dynamic> json) {
    assert(_client != null, 'Trying to send when no connected clients');
    final strSend = jsonEncode(json);
    debugPrint('_clientSendData: $strSend');
    _client?.write(strSend);
  }

  _closeConnection() {
    waitAfterDisconnect = true;
    disconnect();
    _autoConnect();
  }

  _onDone() {
    debugPrint('onDone');
    _closeConnection();
  }

  void dispose() {
    exit = true;
    _streamController.close();
    disconnect();
  }

  disconnect() {
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
