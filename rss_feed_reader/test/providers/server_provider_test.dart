import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_feed_reader/providers/ipchecks.dart';
import 'package:rss_feed_reader/providers/server_provider.dart';

/// A server on a free loopback port (loopback only, so Windows Firewall doesn't prompt).
Future<(SocketServerHandler, int)> _startServer() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  final container = ProviderContainer(overrides: [providerIPChecks.overrideWithValue(null)]);
  addTearDown(container.dispose);
  final server = container.read(Provider((ref) => SocketServerHandler(ref, port: port, secret: 'secret', bindAddress: InternetAddress.loopbackIPv4)));
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

  test('dropping a client while its greeting is still being sent does not throw', () async {
    final (server, port) = await _startServer();
    final dropped = Completer<void>();
    server.isConnected.addListener(() {
      // Runs right after _newConnection() has started flushing the greeting
      if (server.isConnected.value == true && !dropped.isCompleted) scheduleMicrotask(() => dropped.complete(Future.sync(server.dispose)));
    });

    final client = await _connect(port);
    addTearDown(client.destroy);
    await dropped.future;
    expect(server.isConnected.value, isFalse);
    expect(server.clientIP, '?');
  });
}
