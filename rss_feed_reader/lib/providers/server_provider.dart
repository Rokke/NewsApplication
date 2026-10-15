import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/rss_tree.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/providers/ipchecks.dart';
import 'package:rss_feed_reader/providers/tweet_list.dart';

const defaultPort = kDebugMode ? 3344 : 3344;
const socketHeadHello = 'CONNECTED:';
const socketVersion = '1.0';
const codeAlreadyConnected = -99;
// Connections still waiting to authenticate; when another arrives, one of the address with the most pending ones is dropped
const _maxPending = 4;
const _maxListenRetryDelay = Duration(minutes: 5);
// const blockedIP = ['45.', '89'];

final providerSocketServer = Provider<SocketServerHandler>((ref) {
  final config = ref.watch(providerConfig);
  Logger('providerSocketServer').info('rebuild($config)');
  final ret = SocketServerHandler(ref, secret: config.socketSecret);
  ref.onDispose(() {
    Logger('providerSocketServer').info('dispose');
    ret.dispose();
  });
  return ret;
});

/// One accepted socket, from accept until it is dropped.
class _Connection {
  _Connection(this.socket, this.address, this.port);
  final Socket socket;
  // Socket.remoteAddress/remotePort throw once the socket is closed (e.g. reset by the peer),
  // so they are read once on accept and kept here for the UI and the log.
  final String address;
  final int port;
  String handshakeBuffer = '';
  Timer? authTimer;
  String version = '';
  bool dropped = false;
  String get label => '$address:$port';
}

class SocketServerHandler {
  final _log = Logger('SocketServerHandler');
  final int port;
  final InternetAddress? _bindAddress; // null = all IPv4 interfaces
  final Duration _authTimeout;
  final bool _sendFeedOnAuth;
  final Ref ref;
  ServerSocket? _serverSocket;
  Timer? _listenRetryTimer;
  Duration _listenRetryDelay = Duration.zero;
  DateTime _listeningSince = DateTime.now();
  final String _secret;
  int currentTweetIndex = 0;
  _Connection? _client; // the authenticated client, at most one
  final _pending = <_Connection>{}; // not authenticated yet, oldest first
  bool _disposed = false;
  ValueNotifier<bool?> isConnected = ValueNotifier(false);
  String get clientIP => _client?.address ?? '?';
  String get clientVersion => _client?.version ?? '';

  /// [sendFeedOnAuth] is off in tests, which would otherwise open the real database.
  SocketServerHandler(this.ref,
      {this.port = defaultPort, required String secret, InternetAddress? bindAddress, Duration authTimeout = const Duration(seconds: 10), @visibleForTesting bool sendFeedOnAuth = true})
      : _secret = secret,
        _bindAddress = bindAddress,
        _authTimeout = authTimeout,
        _sendFeedOnAuth = sendFeedOnAuth {
    _log.info('Init - port: $port, secret: "${secret.length > 3 ? '${secret.substring(0, secret.length - 3)}***' : '***'}" (${secret.length} chars)');
    _startListener();
  }
  Future<void> _startListener() async {
    try {
      if (_serverSocket == null) {
        if (_secret.isNotEmpty) {
          final serverSocket = await ServerSocket.bind(_bindAddress ?? InternetAddress.anyIPv4, port);
          if (_disposed) {
            // Disposed while binding (e.g. settings saved): don't leave an orphan listener holding the port
            _log.info('_startListener()-disposed while binding');
            serverSocket.close();
            return;
          }
          _serverSocket = serverSocket..listen(_newConnection, onDone: _serverDone, onError: _serverError);
          _listeningSince = DateTime.now();
          _log.fine('_startListener');
        } else {
          isConnected.value = null;
          _log.info('_startListener()-not configured');
        }
      } else {
        _log.info('_startListener()-already active');
      }
    } catch (err) {
      _log.warning('_startListener()-unable to start', err);
      _retryListenerLater();
    }
  }

  /// Listens again after a delay that doubles on each failure (1 s up to 5 min), so a bind that keeps failing or a
  /// listener that keeps erroring neither leaves the server deaf nor floods the log.
  void _retryListenerLater() {
    if (_disposed) return;
    _listenRetryDelay = _listenRetryDelay == Duration.zero ? const Duration(seconds: 1) : _listenRetryDelay * 2;
    if (_listenRetryDelay > _maxListenRetryDelay) _listenRetryDelay = _maxListenRetryDelay;
    _log.info('Listening again in ${_listenRetryDelay.inSeconds} s');
    _listenRetryTimer?.cancel();
    _listenRetryTimer = Timer(_listenRetryDelay, _startListener);
  }

  void dispose() {
    _disposed = true;
    _listenRetryTimer?.cancel();
    _closeServerListener();
    for (final conn in [..._pending, if (_client != null) _client!]) {
      _drop(conn, 'server disposed');
    }
  }

  void _serverDone() {
    if (_disposed) {
      _log.info('_serverDone');
      return;
    }
    // The listener stays open while clients connect and only dispose() closes it, so the OS ended it: listen again
    _log.warning('_serverDone()-listener closed unexpectedly');
    _serverSocket = null;
    // One that ran for a while failed by chance rather than in a loop: start the backoff over
    if (DateTime.now().difference(_listeningSince) > const Duration(minutes: 1)) _listenRetryDelay = Duration.zero;
    _retryListenerLater();
  }

  void _serverError(Object err) {
    // dart:io ends the listener after an error, so _serverDone follows and listens again
    _log.warning('_serverError($err)', err);
  }

  void _closeServerListener() {
    _log.info('_closeServerListener($_serverSocket)');
    _serverSocket?.close();
    _serverSocket = null;
  }

  void _newConnection(Socket socket) {
    final String address;
    final int remotePort;
    try {
      address = socket.remoteAddress.address;
      remotePort = socket.remotePort;
    } catch (err) {
      _log.warning('_newConnection()-connection already gone', err);
      socket.destroy();
      return;
    }
    _log.fine('_newConnection($address:$remotePort)');
    // Check permanent block list (prefix-based, e.g. '45.', '89.'); isBlocked logs the reason
    final ipCheck = ref.read(providerIPChecks);
    if (ipCheck != null && ipCheck.isBlocked(address)) {
      socket.destroy();
      return;
    }
    // The listener stays open: a connected client may be stale (e.g. a phone that dropped off Wi-Fi), and its replacement must get through
    if (_pending.length >= _maxPending) _drop(_evictionCandidate(), 'too many pending connections', level: Level.WARNING);
    final conn = _Connection(socket, address, remotePort);
    _pending.add(conn);
    conn.authTimer = Timer(_authTimeout, () => _drop(conn, 'no authentication within ${_authTimeout.inMilliseconds / 1000} s', level: Level.WARNING));
    socket.listen((data) => _clientDataReceived(conn, data), onDone: () => _drop(conn, 'closed by peer'), onError: (Object err) => _drop(conn, 'socket error', level: Level.WARNING, error: err));
    // Write errors also arrive in onError above; this only keeps them from surfacing again as unhandled errors
    socket.done.then((_) {}, onError: (Object err) => _log.fine('Client socket ${conn.label} done with error: $err'));
    _log.info('Connection from ${conn.label} awaiting authentication (${_pending.length} pending)');
    // No flush(): while it is pending, add() and close() on the socket throw, and its failure would go unhandled
    socket.write('$socketHeadHello$socketVersion');
    _log.fine('SENT: $socketHeadHello$socketVersion');
  }

  /// The oldest pending connection of the address with the most pending ones (the oldest overall on a tie), so a flood
  /// from one address only pushes out its own connections and not the phone's.
  _Connection _evictionCandidate() {
    final counts = <String, int>{};
    for (final conn in _pending) {
      counts[conn.address] = (counts[conn.address] ?? 0) + 1;
    }
    final busiest = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return _pending.firstWhere((conn) => conn.address == busiest);
  }

  /// Closes [conn] and logs why; safe to call again for a connection that is already gone.
  void _drop(_Connection conn, String reason, {Level level = Level.INFO, Object? error}) {
    if (conn.dropped) return;
    conn.dropped = true;
    conn.authTimer?.cancel();
    _pending.remove(conn);
    _log.log(level, 'Dropped ${conn.label}: $reason', error);
    if (identical(conn, _client)) {
      _client = null;
      isConnected.value = false;
    }
    // Only destroy(): close() throws while a write is pending, which would abort the cleanup
    conn.socket.destroy();
  }

  void _authenticated(_Connection conn) {
    conn.authTimer?.cancel();
    _pending.remove(conn);
    // The newest client wins: the current one is most likely the same phone, reconnecting after its connection went silent.
    // Dropping it first also flips isConnected false -> true, so the app bar picks up the new address.
    final previous = _client;
    if (previous != null) _drop(previous, 'replaced by ${conn.label}');
    _client = conn;
    isConnected.value = true;
    _log.info('Authenticated - clientVersion: ${conn.version}, from: ${conn.label}');
    if (_sendFeedOnAuth) _selectAndSendFeed(conn);
  }

  /// Sends a reply to [conn], the connection that asked for it.
  void _clientSendData(_Connection conn, Map<String, dynamic> json) {
    if (!identical(conn, _client)) {
      // Dropped or replaced while the reply was being prepared (e.g. during a database read); it must not reach the newcomer
      _log.info('_clientSendData - ${conn.label} is no longer the client, not sent');
      return;
    }
    final strSend = jsonEncode(json);
    final lst = '${strSend.length}:$strSend';
    _log.fine('_clientSendData(${strSend.length})');
    debugPrint('lst: ${lst.length} bytes');
    conn.socket.add(utf8.encode(lst));
    // socket!.write(lst);
    // socket.flush();
  }

  void _selectAndSendTweet(_Connection conn, {int tweetIndex = 0}) {
    assert(tweetIndex >= -1 && tweetIndex <= 1, 'Invalid tweetIndex: $tweetIndex');
    _log.info('_selectAndSendTweet($tweetIndex)');
    final tweetProvider = ref.read(providerTweetHeader);
    if (tweetProvider.tweets.isEmpty) {
      _log.info('_selectAndSendTweet - no unread tweets');
      _clientSendData(conn, _createJSON(code: -2, data: 'No tweets'));
    }
    if (tweetIndex == -1) {
      if (--currentTweetIndex < 0) currentTweetIndex = tweetProvider.tweets.length - 1;
    } else if (tweetIndex == 1) {
      if (++currentTweetIndex >= tweetProvider.tweets.length) currentTweetIndex = 0;
    }
    _clientSendData(conn, _createJSON(code: 2, data: tweetProvider.tweets[currentTweetIndex].toJson()));
  }

  Future<void> _selectAndSendFeed(_Connection conn, {int changeIndex = 0}) async {
    _log.info('_selectAndSendFeed($changeIndex)');
    assert(changeIndex >= -1 || changeIndex <= 1, 'Invalid changeIndex: $changeIndex');
    final feedProvider = ref.read(providerFeedHeader);
    if (feedProvider.selectedArticle == null) {
      feedProvider.changeSelectedArticle = 0;
    } else if (changeIndex == -1) {
      feedProvider.selectPreviousArticle();
    } else if (changeIndex == 1) {
      feedProvider.selectNextArticle();
    }
    if (feedProvider.selectedArticle != null) {
      await feedProvider.selectedArticle!.articleDescription(ref.read(rssDatabase));
      _clientSendData(conn, _createJSON(code: 1, data: feedProvider.selectedArticle!.toJson()));
    } else {
      _log.info('_selectAndSendFeed - no unread feeds');
      _clientSendData(conn, _createJSON(code: -1, data: 'No feeds'));
    }
  }

  Map<String, dynamic> _createJSON({required int code, required dynamic data}) {
    final feedProvider = ref.read(providerFeedHeader);
    final tweetProvider = ref.read(providerTweetHeader);
    return {
      'code': code,
      'data': data,
      'articleCount': feedProvider.articles.length,
      'articleIndex': feedProvider.selectedArticleIndexNotifier.value,
      'tweetCount': tweetProvider.tweets.length,
      'tweetIndex': currentTweetIndex,
      'running': ref.read(monitoringRunning.notifier).state,
    };
  }

  void _clientDataReceived(_Connection conn, Uint8List data) {
    if (conn.dropped) return;
    // allowMalformed: binary probes (e.g. TLS) must fail the handshake check below, not throw out of this callback
    final utfString = utf8.decode(data, allowMalformed: true);
    _log.info('_clientDataReceived(${data.length} bytes) from ${conn.label}');
    if (!identical(conn, _client)) {
      // Awaiting handshake response — buffer data (may arrive in multiple TCP packets)
      conn.handshakeBuffer += utfString;
      final buffer = conn.handshakeBuffer;
      _log.fine('Handshake buffer: "${buffer.length > 100 ? '${buffer.substring(0, 100)}...' : buffer}"');
      _log.fine('startsWith=$socketHeadHello: ${buffer.startsWith(socketHeadHello)}, endsWith=._secret: ${buffer.endsWith('.$_secret')}');
      if (buffer.startsWith(socketHeadHello) && buffer.endsWith('.$_secret')) {
        // Everything between the hello and '.<secret>', so version '1.0' isn't cut at its own dot
        conn.version = buffer.substring(socketHeadHello.length, buffer.length - _secret.length - 1);
        conn.handshakeBuffer = '';
        _authenticated(conn);
      } else if (!socketHeadHello.startsWith(buffer) && !buffer.startsWith(socketHeadHello)) {
        // Clearly not a valid handshake (e.g. HTTP request) — silently close
        final preview = buffer.length > 80 ? '${buffer.substring(0, 80)}...' : buffer;
        _drop(conn, 'invalid handshake "$preview"', level: Level.WARNING);
      } else if (buffer.length > 500) {
        // Too much data without valid handshake — silently close
        _drop(conn, 'handshake too long (${buffer.length} bytes)', level: Level.WARNING);
      } else {
        _log.fine('Handshake incomplete, waiting for more data (${buffer.length} bytes so far)');
      }
    } else {
      debugPrint('decode');
      final json = jsonDecode(utfString) as Map<String, dynamic>;
      debugPrint('decoded: $json');
      switch (json['command']) {
        case 'start_monitor':
          ref.read(rssProvider).startMonitoring();
          break;
        case 'previous_feed':
          _selectAndSendFeed(conn, changeIndex: -1);
          break;
        case 'next_feed':
          _selectAndSendFeed(conn, changeIndex: 1);
          break;
        case 'feed':
          _selectAndSendFeed(conn);
          break;
        case 'previous_tweet':
          _selectAndSendTweet(conn, tweetIndex: -1);
          break;
        case 'next_tweet':
          _selectAndSendTweet(conn, tweetIndex: 1);
          break;
        case 'tweet':
          _selectAndSendTweet(conn);
          break;
        case 'tweet_read':
          final tweetProvider = ref.read(providerTweetHeader);
          final id = json['id'] as int;
          if (id >= 0) {
            tweetProvider.removeTweet(id);
            _selectAndSendTweet(conn);
          }
          break;
        case 'article_read':
          final feedProvider = ref.read(providerFeedHeader);
          final id = json['id'] as int;
          if (id >= 0) {
            feedProvider.changeArticleStatusById(id: id);
            _selectAndSendFeed(conn);
          }
          break;
        default:
          _log.warning('_clientDataReceived - invalid command: (${json['command']})');
      }
    }
  }
}
