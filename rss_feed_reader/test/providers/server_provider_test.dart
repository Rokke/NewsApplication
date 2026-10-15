import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_feed_reader/providers/ipchecks.dart';
import 'package:rss_feed_reader/providers/server_provider.dart';

/// A free loopback port (loopback only, so Windows Firewall doesn't prompt).
Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

SocketServerHandler _createServer(int port) {
  final container = ProviderContainer(overrides: [providerIPChecks.overrideWithValue(null)]);
  addTearDown(container.dispose);
  return container.read(Provider((ref) => SocketServerHandler(ref, port: port, secret: 'secret', bindAddress: InternetAddress.loopbackIPv4)));
}

Future<(SocketServerHandler, int)> _startServer() async {
  final port = await _freePort();
  final server = _createServer(port);
  addTearDown(server.dispose);
  return (server, port);
}

/// Connects once the server listens: it binds asynchronously, and again only after dropping a client.
Future<Socket> _connect(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    try {
      return await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
    } on SocketException {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<String> _greeting(Socket socket) {
  final greeting = Completer<String>();
  socket.listen((data) {
    if (!greeting.isCompleted) greeting.complete(utf8.decode(data));
  }, onError: (_) {});
  return greeting.future.timeout(const Duration(seconds: 5));
}

/// SO_LINGER {on, 0 s}: closing then sends a TCP reset instead of a FIN, like a
/// port scanner or a phone dropping off the network.
RawSocketOption _resetOnClose() => Platform.isWindows
    ? RawSocketOption(RawSocketOption.levelSocket, 0x0080, Uint8List.fromList([1, 0, 0, 0])) // u_short l_onoff, l_linger
    : RawSocketOption(RawSocketOption.levelSocket, Platform.isLinux ? 13 : 0x0080, Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0])); // int l_onoff, l_linger

void main() {
  test('a client resetting its connection does not wedge the server', () async {
    final (server, port) = await _startServer();

    final first = await _connect(port);
    expect(await _greeting(first), '$socketHeadHello$socketVersion');
    expect(server.isConnected.value, isTrue);
    expect(server.clientIP, '127.0.0.1');

    first.setRawOption(_resetOnClose());
    first.destroy();

    final second = await _connect(port);
    addTearDown(second.destroy);
    expect(await _greeting(second), '$socketHeadHello$socketVersion');
    expect(server.isConnected.value, isTrue);
    expect(server.clientIP, '127.0.0.1');
  });

  test('a handshake that is not UTF-8 drops the client and the server listens again', () async {
    final (server, port) = await _startServer();

    final probe = await _connect(port);
    addTearDown(probe.destroy);
    final dropped = Completer<void>();
    probe.listen((_) {}, onError: (_) {}, onDone: dropped.complete);
    probe.add([0x16, 0x03, 0x01, 0xff, 0xfe]); // binary, like a TLS ClientHello from a scanner
    await dropped.future.timeout(const Duration(seconds: 5));
    expect(server.isConnected.value, isFalse);
    expect(server.clientIP, '?');

    final next = await _connect(port);
    addTearDown(next.destroy);
    expect(await _greeting(next), '$socketHeadHello$socketVersion');
  });

  test('disposing the server while it is still binding leaves the port free', () async {
    final port = await _freePort();
    _createServer(port).dispose(); // the constructor's bind is still pending
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final rebind = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await rebind.close();
  });
}
