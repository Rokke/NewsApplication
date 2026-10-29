import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:news_client_application/models/frame_decoder.dart';
import 'package:news_client_application/models/socket_response.dart';
import 'package:news_client_application/providers/config_provider.dart';

const socketHeadHello = 'CONNECTED:';
const socketVersion = '1.0';
// The server's last message when a device from another address took it over: don't reconnect, or the two push each other off
const codeAlreadyConnected = -99;
const _initialRetryMs = 2000;
const _maxRetryMs = 300000; // 5 minutes

final providerSocket = Provider((ref) {
  final log = Logger('providerSocket');
  final config = ref.watch(providerConfig);
  final addresses = <String>[config.socketServerInternal, config.socketServerExternal].where((a) => a.isNotEmpty).toList();
  log.info('Config changed - addresses: $addresses');
  final socket = SocketProvider(serverAddresses: addresses, secret: config.socketSecret);
  // Also when disconnected: a pending retry timer would otherwise keep the old instance connecting
  ref.onDispose(socket.dispose);
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
  final _decoder = FrameDecoder();
  String? connectedAddress;
  int port;
  String _serverVersion = '';
  bool _exit = false;
  // Set by codeAlreadyConnected: no reconnecting until reconnect() is called
  bool _serverInUse = false;
  String? inUseBy; // the address of the device that has the server
  int _consecutiveFailures = 0;
  int _currentRetryMs = _initialRetryMs;
  final StreamController<SocketResponse> _streamController = StreamController();
  Timer? _timer;
  Stream<SocketResponse> get stream => _streamController.stream;
  Socket? _client;
  String get serverVersion => _serverVersion;

  void _scheduleConnect(int delayMs) {
    if (_exit || _serverInUse) return;
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
    if (_exit) {
      // Disposed while connecting (Settings saved): drop the connection instead of handshaking on it
      _client?.destroy();
      _client = null;
      return;
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

  void _resetBackoff() {
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
    if (status.value == SocketStatus.waiting) {
      final utfString = utf8.decode(data, allowMalformed: true);
      if (utfString.startsWith(socketHeadHello)) {
        _serverVersion = utfString.split(socketHeadHello).last;
        _log.info('Server greeting received - version: $_serverVersion, sending auth response');
        final authResponse = '$socketHeadHello$socketVersion.$_secret';
        _log.info('Sending auth: "${authResponse.replaceRange(authResponse.length - 3, authResponse.length, '***')}" (${authResponse.length} chars)');
        _client!.write(authResponse);
        _client!.flush().then((_) => _log.fine('Auth response flushed'));
        status.value = SocketStatus.connected;
        _log.info('Handshake complete - connected to $connectedAddress');
        _resetBackoff();
      } else {
        _log.severe('Invalid server greeting: "${utfString.substring(0, utfString.length.clamp(0, 100))}"');
        _closeConnection();
      }
    } else {
      try {
        final frames = _decoder.add(data);
        _log.fine('Read ${data.length} bytes: ${frames.length} frame(s), ${_decoder.buffered} characters waiting');
        for (final json in frames) {
          // A frame can end the connection (codeAlreadyConnected); the rest of this read belongs to it
          if (_client == null) break;
          _parseData(json);
        }
      } catch (e, stackTrace) {
        _log.severe('Data parse error', e, stackTrace);
        _closeConnection();
      }
    }
  }

  void _parseData(String frame) {
    final json = jsonDecode(frame) as Map<String, dynamic>;
    if (json['code'] == codeAlreadyConnected) {
      // Before SocketResponse.fromJson, which would throw on the missing counts
      _onServerInUse(json['data']);
      return;
    }
    final response = SocketResponse.fromJson(json);
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

  void _onServerInUse(Object? otherAddress) {
    _log.warning('Server is in use by another device ($otherAddress), not reconnecting');
    inUseBy = otherAddress?.toString();
    _serverInUse = true;
    disconnect();
  }

  /// Takes the server back after codeAlreadyConnected; the other device is then told to stop in turn.
  void reconnect() {
    _log.info('Reconnecting on request (server was in use by ${inUseBy ?? "?"})');
    _serverInUse = false;
    inUseBy = null;
    _resetBackoff();
    _scheduleConnect(0);
  }

  void clientSendData(Map<String, dynamic> json) {
    assert(_client != null, 'Trying to send when no connected clients');
    final strSend = jsonEncode(json);
    _log.fine('Sending command: ${json['command']}');
    _client?.write(strSend);
    _client?.flush();
  }

  void _closeConnection() {
    _log.info(_serverInUse ? 'Connection closed, not retrying: the server is in use by another device' : 'Connection closed, will retry');
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
    // destroy() alone: close() throws while the handshake's flush is still pending, e.g. when Settings are saved
    _client?.destroy();
    _client = null;
    _serverVersion = '';
    // A frame cut off with the connection must not swallow the first frame of the next one
    _decoder.reset();
    status.value = _serverInUse ? SocketStatus.serverInUse : SocketStatus.disconnected;
  }
}

enum SocketStatus { disconnected, connected, connectedRunning, connectedNotRunning, waiting, serverInUse }
