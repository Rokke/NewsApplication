import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_client_application/providers/socket_provider.dart';

/// What the fake server does once a client has authenticated.
enum _OnAuth { sendInUse, close, stayConnected, sendPartialAndClose, sendFeed, sendTwoFramesAtOnce, sendSplitFrame }

/// A loopback stand-in for the desktop app: greets, waits for the auth, then does what [script] says; connection n
/// follows step n, and the last step repeats.
class _FakeServer {
  _FakeServer._(this._server, this.script) {
    _server.listen(_accept);
  }
  static Future<_FakeServer> start(List<_OnAuth> script) async {
    // Loopback only, so Windows Firewall doesn't prompt; port 0 picks a free one
    final server = _FakeServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), script);
    addTearDown(server._close);
    return server;
  }

  final ServerSocket _server;
  final _sockets = <Socket>[];
  final List<_OnAuth> script;
  int connections = 0;
  int get port => _server.port;

  void _send(Socket socket, Map<String, dynamic> message) => socket.add(_frame(message));

  static List<int> _frame(Map<String, dynamic> message) {
    final json = jsonEncode(message);
    return utf8.encode('${json.length}:$json');
  }

  static Map<String, dynamic> _noFeeds(int articleCount, {String data = 'No feeds'}) =>
      {'code': -1, 'data': data, 'articleCount': articleCount, 'articleIndex': 0, 'tweetCount': 0, 'tweetIndex': 0, 'running': true};

  void _accept(Socket socket) {
    final onAuth = script[min(connections++, script.length - 1)];
    _sockets.add(socket);
    var received = '';
    socket.listen((data) {
      received += utf8.decode(data);
      if (!received.endsWith('.secret')) return;
      switch (onAuth) {
        case _OnAuth.sendInUse:
          _send(socket, {'code': codeAlreadyConnected, 'data': '192.168.1.20'});
          socket.close();
        case _OnAuth.close:
          socket.close();
        case _OnAuth.stayConnected:
          break;
        case _OnAuth.sendPartialAndClose:
          // The start of a frame, like a connection lost in the middle of an article
          socket.add(utf8.encode('500:{"code":1,"data":'));
          socket.close();
        case _OnAuth.sendFeed:
          _send(socket, _noFeeds(0));
        case _OnAuth.sendTwoFramesAtOnce:
          // Two replies in one write, like after a quick double click on delete
          socket.add([..._frame(_noFeeds(1)), ..._frame(_noFeeds(2))]);
        case _OnAuth.sendSplitFrame:
          // One reply in two writes, cut inside the 'æ'
          final bytes = _frame(_noFeeds(3, data: 'Blåbær'));
          final cut = bytes.indexOf(0xC3) + 1;
          socket.add(bytes.sublist(0, cut));
          Future<void>.delayed(const Duration(milliseconds: 200), () => socket.add(bytes.sublist(cut)));
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
    final server = await _FakeServer.start([_OnAuth.sendInUse]);
    final client = _createClient(server.port);

    await _until(() => client.status.value == SocketStatus.serverInUse);
    expect(client.inUseBy, '192.168.1.20');
    // Past the 2 s retry, which the control test below shows does happen after a plain close
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(server.connections, 1);
    expect(client.status.value, SocketStatus.serverInUse);
  });

  test('reconnects when the server just closes', () async {
    final server = await _FakeServer.start([_OnAuth.close]);
    _createClient(server.port);

    await _until(() => server.connections == 2);
  });

  test('reconnect() connects again', () async {
    final server = await _FakeServer.start([_OnAuth.sendInUse, _OnAuth.stayConnected]);
    final client = _createClient(server.port);
    await _until(() => client.status.value == SocketStatus.serverInUse);

    client.reconnect();
    await _until(() => server.connections == 2);
    await _until(() => client.status.value == SocketStatus.connected);
    expect(client.inUseBy, isNull);
  });

  test('a frame cut off by a lost connection does not garble the next connection', () async {
    final server = await _FakeServer.start([_OnAuth.sendPartialAndClose, _OnAuth.sendFeed]);
    final client = _createClient(server.port);

    await _until(() => server.connections == 2);
    await _until(() => client.status.value == SocketStatus.connectedRunning);
  });

  test('two frames in one read both reach the stream', () async {
    final server = await _FakeServer.start([_OnAuth.sendTwoFramesAtOnce]);
    final client = _createClient(server.port);
    final counts = <int>[];
    client.stream.listen((response) => counts.add(response.numberOfArticles));

    await _until(() => counts.length == 2);
    expect(counts, [1, 2]);
    expect(client.status.value, SocketStatus.connectedRunning);
  });

  test('a frame split inside a character is parsed once complete', () async {
    final server = await _FakeServer.start([_OnAuth.sendSplitFrame]);
    final client = _createClient(server.port);
    final counts = <int>[];
    client.stream.listen((response) => counts.add(response.numberOfArticles));

    await _until(() => counts.isNotEmpty);
    expect(counts, [3]);
    expect(server.connections, 1);
  });
}
