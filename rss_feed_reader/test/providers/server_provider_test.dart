import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/ipchecks.dart';
import 'package:rss_feed_reader/providers/server_provider.dart';

// Short, for the tests about the timeout; the others keep the real 10 s, so a slow machine can't make them flaky
const _shortAuthTimeout = Duration(milliseconds: 300);

/// A free loopback port (loopback only, so Windows Firewall doesn't prompt).
Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

/// sendFeedOnAuth: false, because the first feed would open the real database (D:\Temp\AppDB on the dev machine).
SocketServerHandler _createServer(int port, {Duration authTimeout = const Duration(seconds: 10)}) {
  final container = ProviderContainer(overrides: [providerIPChecks.overrideWithValue(null)]);
  addTearDown(container.dispose);
  return container.read(Provider((ref) => SocketServerHandler(ref, port: port, secret: 'secret', bindAddress: InternetAddress.loopbackIPv4, authTimeout: authTimeout, sendFeedOnAuth: false)));
}

Future<(SocketServerHandler, int)> _startServer({Duration authTimeout = const Duration(seconds: 10)}) async {
  final port = await _freePort();
  final server = _createServer(port, authTimeout: authTimeout);
  addTearDown(server.dispose);
  return (server, port);
}

/// A connected test client that collects the server's greeting and notices when the server drops it.
class _Peer {
  _Peer(this.socket) {
    socket.listen((data) {
      if (!_greeting.isCompleted) _greeting.complete(utf8.decode(data));
    }, onError: (_) => _setClosed(), onDone: _setClosed);
  }
  final Socket socket;
  final _greeting = Completer<String>();
  final _closed = Completer<void>();
  void _setClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }

  Future<String> get greeting => _greeting.future.timeout(const Duration(seconds: 5));
  Future<void> get closed => _closed.future.timeout(const Duration(seconds: 5));
  bool get isClosed => _closed.isCompleted;
  void authenticate({String secret = 'secret'}) => socket.write('$socketHeadHello$socketVersion.$secret');
}

/// Connects once the server listens: it binds asynchronously. [from] picks another loopback source address.
Future<_Peer> _connect(int port, {String? from}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, sourceAddress: from, timeout: const Duration(seconds: 1));
      addTearDown(socket.destroy);
      return _Peer(socket);
    } on SocketException {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// Waits for the server to react to a socket event, which it does asynchronously.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition not met within 5 s');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The log messages written from now on, to check why a connection was dropped.
List<String> _captureLog() {
  final messages = <String>[];
  final subscription = Logger.root.onRecord.listen((record) => messages.add(record.message));
  addTearDown(subscription.cancel);
  return messages;
}

/// SO_LINGER {on, 0 s}: closing then sends a TCP reset instead of a FIN, like a
/// port scanner or a phone dropping off the network.
RawSocketOption _resetOnClose() => Platform.isWindows
    ? RawSocketOption(RawSocketOption.levelSocket, 0x0080, Uint8List.fromList([1, 0, 0, 0])) // u_short l_onoff, l_linger
    : RawSocketOption(RawSocketOption.levelSocket, Platform.isLinux ? 13 : 0x0080, Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0])); // int l_onoff, l_linger

const _hello = '$socketHeadHello$socketVersion';

void main() {
  test('a client resetting its connection does not wedge the server', () async {
    final (server, port) = await _startServer();

    final first = await _connect(port);
    expect(await first.greeting, _hello);
    expect(server.isConnected.value, isFalse, reason: 'not authenticated yet');
    expect(server.clientIP, '?');
    first.authenticate();
    await _until(() => server.isConnected.value == true);
    expect(server.clientIP, '127.0.0.1');
    expect(server.clientVersion, socketVersion);

    first.socket.setRawOption(_resetOnClose());
    first.socket.destroy();
    await _until(() => server.isConnected.value == false);

    final second = await _connect(port);
    expect(await second.greeting, _hello);
    second.authenticate();
    await _until(() => server.isConnected.value == true);
    expect(server.clientIP, '127.0.0.1');
  });

  test('a handshake that is not UTF-8 drops the client and the server keeps listening', () async {
    final log = _captureLog();
    final (server, port) = await _startServer();

    final probe = await _connect(port);
    probe.socket.add([0x16, 0x03, 0x01, 0xff, 0xfe]); // binary, like a TLS ClientHello from a scanner
    await probe.closed;
    expect(server.isConnected.value, isFalse);
    expect(server.clientIP, '?');
    expect(log, anyElement(contains('invalid handshake')));

    final next = await _connect(port);
    expect(await next.greeting, _hello);
  });

  test('a silent client is dropped after the auth timeout and never shows as connected', () async {
    final log = _captureLog();
    final (server, port) = await _startServer(authTimeout: _shortAuthTimeout);
    final changes = <bool?>[];
    server.isConnected.addListener(() => changes.add(server.isConnected.value));

    final silent = await _connect(port);
    expect(await silent.greeting, _hello);
    await silent.closed;
    expect(changes, isEmpty);
    expect(server.clientIP, '?');
    expect(log, anyElement(contains('no authentication')));
  });

  test('a client with the wrong secret is dropped after the auth timeout', () async {
    final log = _captureLog();
    final (server, port) = await _startServer(authTimeout: _shortAuthTimeout);

    final wrong = await _connect(port);
    expect(await wrong.greeting, _hello);
    wrong.authenticate(secret: 'guess');
    await wrong.closed;
    expect(server.isConnected.value, isFalse);
    expect(log, anyElement(contains('no authentication')));
  });

  test('a second client gets through while a silent one is still pending', () async {
    final log = _captureLog();
    // Long enough that the silent client is certainly still pending while the phone authenticates
    final (server, port) = await _startServer(authTimeout: const Duration(seconds: 2));

    final silent = await _connect(port);
    expect(await silent.greeting, _hello);

    final phone = await _connect(port);
    expect(await phone.greeting, _hello);
    phone.authenticate();
    await _until(() => server.isConnected.value == true);
    expect(silent.isClosed, isFalse, reason: 'the silent client is still pending');

    await silent.closed;
    expect(log, anyElement(contains('Dropped 127.0.0.1:${silent.socket.port}: no authentication')));
    expect(server.isConnected.value, isTrue);
    expect(phone.isClosed, isFalse);
  });

  test('a client that authenticates replaces a stale authenticated one', () async {
    final log = _captureLog();
    final (server, port) = await _startServer();

    final stale = await _connect(port);
    expect(await stale.greeting, _hello);
    stale.authenticate();
    await _until(() => server.isConnected.value == true);

    final phone = await _connect(port);
    expect(await phone.greeting, _hello, reason: 'the server keeps listening while a client is connected');
    phone.authenticate();
    await stale.closed;
    expect(log, anyElement(contains('Dropped 127.0.0.1:${stale.socket.port}: replaced by 127.0.0.1:${phone.socket.port}')));
    expect(server.isConnected.value, isTrue);
    expect(phone.isClosed, isFalse);
  });

  test('when too many connections are pending, the oldest one makes room', () async {
    final log = _captureLog();
    final (server, port) = await _startServer();

    final silent = <_Peer>[];
    for (var i = 0; i < 4; i++) {
      final peer = await _connect(port);
      expect(await peer.greeting, _hello); // in order, so the server registered them oldest first
      silent.add(peer);
    }

    final phone = await _connect(port);
    expect(await phone.greeting, _hello);
    await silent.first.closed; // the oldest pending one made room
    expect(log, anyElement(contains('too many pending connections')));
    phone.authenticate();
    await _until(() => server.isConnected.value == true);
  });

  test('a flood from one address does not push out the phone while it authenticates', () async {
    final log = _captureLog();
    final (server, port) = await _startServer();

    final phone = await _connect(port);
    expect(await phone.greeting, _hello);
    final flood = <_Peer>[];
    for (var i = 0; i < 3 * 4; i++) {
      final peer = await _connect(port, from: '127.0.0.2');
      expect(await peer.greeting, _hello);
      flood.add(peer);
    }
    await _until(() => flood.where((peer) => peer.isClosed).length == flood.length - 3); // the flood made room among its own
    expect(phone.isClosed, isFalse);
    expect(log.where((m) => m.contains('too many pending')), everyElement(startsWith('Dropped 127.0.0.2:')));

    phone.authenticate();
    await _until(() => server.isConnected.value == true);
    expect(server.clientIP, '127.0.0.1');
  });

  test('disposing the server drops pending and authenticated connections', () async {
    final log = _captureLog();
    final (server, port) = await _startServer();

    final pending = await _connect(port);
    expect(await pending.greeting, _hello);
    final client = await _connect(port);
    expect(await client.greeting, _hello);
    client.authenticate();
    await _until(() => server.isConnected.value == true);

    server.dispose();
    await pending.closed;
    await client.closed;
    expect(server.isConnected.value, isFalse);
    expect(log.where((m) => m.contains('server disposed')), hasLength(2));
  });

  test('disposing the server while it is still binding leaves the port free', () async {
    final port = await _freePort();
    _createServer(port).dispose(); // the constructor's bind is still pending
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final rebind = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await rebind.close();
  });
}
