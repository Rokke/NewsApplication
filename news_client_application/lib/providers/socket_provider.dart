import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:news_client_application/models/socket_response.dart';
import 'package:news_client_application/providers/config_provider.dart';

const socketHeadHello = 'CONNECTED:';
const socketVersion = '1.0';
const _initialRetryMs = 2000;
const _maxRetryMs = 300000; // 5 minutes

final providerSocket = Provider((ref) {
  final log = Logger('providerSocket');
  final config = ref.watch(providerConfig);
  final addresses = <String>[config.socketServerInternal, config.socketServerExternal].where((a) => a.isNotEmpty).toList();
  log.info('Config changed - addresses: $addresses');
  final socket = SocketProvider(serverAddresses: addresses, secret: config.socketSecret);
  ref.onDispose(() {
    if (!socket.isDisconnected) socket.dispose();
  });
  return socket;
});

class SocketProvider {
  final _log = Logger('SocketProvider');
  final String _secret;
  SocketProvider({required this.serverAddresses, required String secret, this.port = kDebugMode ? 3344 : 3344}) : _secret = secret {
    if (isValid) {
      _log.info('Initialized - addresses: $serverAddresses, port: $port');
      _scheduleConnect(0);
    } else {
      _log.warning('Not valid - addresses: $serverAddresses, hasSecret: ${_secret.isNotEmpty}');
    }
  }

  bool get isValid => serverAddresses.isNotEmpty && _secret.isNotEmpty;
  bool get isConnected => status.value == SocketStatus.connected || status.value == SocketStatus.connectedNotRunning || status.value == SocketStatus.connectedRunning;
  bool get isDisconnected => status.value == SocketStatus.disconnected;
  ValueNotifier<SocketStatus> status = ValueNotifier(SocketStatus.disconnected);
  List<String> serverAddresses;
  int _addressIndex = 0;
  int dataLength = 0;
  String dataToParse = '';
  String? connectedAddress;
  int port;
  String _serverVersion = '';
  bool _exit = false;
  int _consecutiveFailures = 0;
  int _currentRetryMs = _initialRetryMs;
  final StreamController<SocketResponse> _streamController = StreamController();
  Timer? _timer;
  Stream<SocketResponse> get stream => _streamController.stream;
  Socket? _client;
  String get serverVersion => _serverVersion;

  void _scheduleConnect(int delayMs) {
    if (_exit) return;
    _timer?.cancel();
    if (delayMs <= 0) {
      _tryConnect();
    } else {
      _log.fine('Next connection attempt in ${delayMs}ms (failures: $_consecutiveFailures)');
      _timer = Timer(Duration(milliseconds: delayMs), _tryConnect);
    }
  }

  Future<void> _tryConnect() async {
    if (_exit || _client != null) return;
    connectedAddress = null;

    if (_addressIndex >= serverAddresses.length) {
      _addressIndex = 0;
      // Completed a full cycle through all addresses — apply backoff
      _consecutiveFailures++;
      _currentRetryMs = min(_initialRetryMs * pow(2, _consecutiveFailures - 1).toInt(), _maxRetryMs);
      _log.info('All addresses tried, backing off ${_currentRetryMs}ms (attempt #$_consecutiveFailures)');
      status.value = SocketStatus.disconnected;
      _scheduleConnect(_currentRetryMs);
      return;
    }

    final address = serverAddresses[_addressIndex++];
    _log.info('Connecting to $address:$port ($_addressIndex/${serverAddresses.length})');
    status.value = SocketStatus.waiting;

    try {
      _client = await Socket.connect(address, port, timeout: const Duration(milliseconds: 5400));
    } on SocketException catch (err) {
      _log.warning('Connection failed to $address:$port', err);
    } catch (err, stackTrace) {
      _log.severe('Unexpected connection error', err, stackTrace);
    }

    if (_client != null) {
      connectedAddress = address;
      _log.info('TCP connected to $connectedAddress:$port, awaiting handshake');
      _client!.listen(_onData, onDone: _onDone, onError: _onError);
    } else {
      // Try next address quickly (1s between addresses in same cycle)
      _scheduleConnect(1000);
    }
  }

  void _onConnectionEstablished() {
    _consecutiveFailures = 0;
    _currentRetryMs = _initialRetryMs;
    _addressIndex = 0;
  }

  void _onError(Object error) {
    _log.warning('Socket error', error);
    disconnect();
    _scheduleConnect(_currentRetryMs);
  }

  void _onData(List<int> data) {
    debugPrint('onData: ${data.length} bytes');
    final utfString = utf8.decode(data);
    if (status.value == SocketStatus.waiting) {
      if (utfString.startsWith(socketHeadHello)) {
        _serverVersion = utfString.split(socketHeadHello).last;
        _log.info('Server greeting received - version: $_serverVersion, sending auth response');
        final authResponse = '$socketHeadHello$socketVersion.$_secret';
        _log.info('Sending auth: "${authResponse.replaceRange(authResponse.length - 3, authResponse.length, '***')}" (${authResponse.length} chars)');
        _client!.write(authResponse);
        _client!.flush().then((_) => _log.fine('Auth response flushed'));
        status.value = SocketStatus.connected;
        _log.info('Handshake complete - connected to $connectedAddress');
        _onConnectionEstablished();
      } else {
        _log.severe('Invalid server greeting: "${utfString.substring(0, utfString.length.clamp(0, 100))}"');
        _closeConnection();
      }
    } else {
      try {
        if (dataLength == 0) {
          final index = utfString.indexOf(':');
          if (index < 0) {
            _log.warning('Invalid message format (no colon separator)');
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
      } catch (e, stackTrace) {
        _log.severe('Data parse error', e, stackTrace);
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
      if (status.value != SocketStatus.connectedRunning) {
        _log.info('Server monitoring status: running');
      }
      status.value = SocketStatus.connectedRunning;
    } else if (response.running == false) {
      if (status.value != SocketStatus.connectedNotRunning) {
        _log.info('Server monitoring status: not running');
      }
      status.value = SocketStatus.connectedNotRunning;
    }
    _streamController.sink.add(response);
  }

  void clientSendData(Map<String, dynamic> json) {
    assert(_client != null, 'Trying to send when no connected clients');
    final strSend = jsonEncode(json);
    _log.fine('Sending command: ${json['command']}');
    _client?.write(strSend);
    _client?.flush();
  }

  void _closeConnection() {
    _log.info('Connection closed, will retry');
    disconnect();
    // After a disconnect from established connection, retry quickly first
    _scheduleConnect(_currentRetryMs);
  }

  void _onDone() {
    _log.info('Server closed connection');
    _closeConnection();
  }

  void dispose() {
    _log.info('Disposing');
    _exit = true;
    _streamController.close();
    disconnect();
  }

  void disconnect() {
    _log.info('Disconnecting from ${connectedAddress ?? "none"}');
    _timer?.cancel();
    _timer = null;
    _client?.close();
    _client?.destroy();
    _client = null;
    _serverVersion = '';
    status.value = SocketStatus.disconnected;
  }
}

enum SocketStatus { disconnected, connected, connectedRunning, connectedNotRunning, waiting }
