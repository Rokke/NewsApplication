import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_client_application/providers/socket_provider.dart';

/// What the fake server does once a client has authenticated.
enum _OnAuth { sendInUse, close, stayConnected }

/// A loopback stand-in for the desktop app: greets, waits for the auth, then does what [onAuth] says.
class _FakeServer {
  _FakeServer._(this._server, this.onAuth) {
    _server.listen(_accept);
  }
  static Future<_FakeServer> start(_OnAuth onAuth) async {
    // Loopback only, so Windows Firewall doesn't prompt; port 0 picks a free one
    final server = _FakeServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), onAuth);
    addTearDown(server._close);
    return server;
  }

  final ServerSocket _server;
  final _sockets = <Socket>[];
  _OnAuth onAuth;
  int connections = 0;
  int get port => _server.port;

  void _accept(Socket socket) {
    connections++;
    _sockets.add(socket);
    var received = '';
    socket.listen((data) {
      received += utf8.decode(data);
      if (!received.endsWith('.secret')) return;
      switch (onAuth) {
        case _OnAuth.sendInUse:
          final json = jsonEncode({'code': codeAlreadyConnected, 'data': '192.168.1.20'});
          socket.add(utf8.encode('${json.length}:$json'));
          socket.close();
        case _OnAuth.close:
          socket.close();
        case _OnAuth.stayConnected:
          break;
      }
    }, onError: (_) {});
    socket.done.then((_) {}, onError: (_) {});
    socket.write('$socketHeadHello$socketVersion');
  }

  Future<void> _close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

SocketProvider _createClient(int port) {
  final client = SocketProvider(serverAddresses: ['127.0.0.1'], secret: 'secret', port: port);
  addTearDown(client.dispose);
  return client;
}

/// Waits for something the client does asynchronously.
Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition not met within ${timeout.inSeconds} s');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('stops reconnecting after codeAlreadyConnected', () async {
    final server = await _FakeServer.start(_OnAuth.sendInUse);
    final client = _createClient(server.port);

    await _until(() => client.status.value == SocketStatus.serverInUse);
    expect(client.inUseBy, '192.168.1.20');
    // Past the 2 s retry, which the control test below shows does happen after a plain close
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(server.connections, 1);
    expect(client.status.value, SocketStatus.serverInUse);
  });

  test('reconnects when the server just closes', () async {
    final server = await _FakeServer.start(_OnAuth.close);
    _createClient(server.port);

    await _until(() => server.connections == 2);
  });

  test('reconnect() connects again', () async {
    final server = await _FakeServer.start(_OnAuth.sendInUse);
    final client = _createClient(server.port);
    await _until(() => client.status.value == SocketStatus.serverInUse);

    server.onAuth = _OnAuth.stayConnected;
    client.reconnect();
    await _until(() => server.connections == 2);
    await _until(() => client.status.value == SocketStatus.connected);
    expect(client.inUseBy, isNull);
  });
}
