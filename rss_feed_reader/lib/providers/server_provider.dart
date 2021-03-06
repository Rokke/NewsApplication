import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/rss_tree.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/providers/tweet_list.dart';

const defaultPort = kDebugMode ? 3344 : 3344;
const socketHeadHello = 'CONNECTED:';
const socketVersion = '1.0';
const codeAlreadyConnected = -99;
const blockedIP = ['45.'];

final providerSocketServer = Provider<SocketServerHandler>((ref) {
  final config = ref.watch(providerConfig);
  Logger('providerSocketServer').info('rebuild');
  final ret = SocketServerHandler(ref.read, secret: config.socketSecret);
  ref.onDispose(() => ret.dispose());
  return ret;
});

class SocketServerHandler {
  final _log = Logger('SocketServerHandler');
  final int port;
  final Reader read;
  ServerSocket? _serverSocket;
  String clientVersion = '';
  final String _secret;
  int currentTweetIndex = 0;
  bool authenticate = false;
  Socket? _clientSocket;
  ValueNotifier<bool?> isConnected = ValueNotifier(false);
  String get clientIP => _clientSocket?.remoteAddress.address ?? '?';
  SocketServerHandler(this.read, {this.port = defaultPort, required String secret}) : _secret = secret {
    _startListener();
  }
  Future<void> _startListener() async {
    if (_serverSocket == null) {
      if (_secret.isNotEmpty) {
        _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        _serverSocket?.listen(_newConnection, onDone: _serverDone, onError: _serverError);
        _log.fine('_startListener');
      } else {
        isConnected.value = null;
        _log.info('_startListener()-not configured');
      }
    } else {
      _log.info('_startListener()-already active');
    }
  }

  void dispose() {
    _closeServerListener();
    _closeClient();
  }

  void _serverDone() {
    debugPrint('_serverDone');
  }

  void _serverError(err) {
    debugPrint('_serverError($err)');
  }

  void _closeServerListener() {
    _log.info('_closeServerListener($_serverSocket)');
    _serverSocket?.close();
    _serverSocket = null;
  }

  void _newConnection(Socket socket) {
    if (_clientSocket == null) {
      _closeServerListener();
      if (blockedIP.any((element) {
        debugPrint('IP: ${socket.remoteAddress.address} - $element');
        return socket.remoteAddress.address.startsWith(element) != false;
      })) {
        _log.warning('_newConnection(${socket.remoteAddress}:${socket.remotePort}) - Blocked IP trying to connect');
        socket.destroy();
      } else {
        _clientSocket = socket;
        _log.info('_newConnection(${_clientSocket?.remoteAddress}:${_clientSocket?.remotePort})');
        _clientSocket?.listen(_clientDataReceived, onDone: _clientDisconnected, onError: _clientError);
        _clientSocket?.write('$socketHeadHello$socketVersion');
        debugPrint('SENT: $socketHeadHello$socketVersion');
        isConnected.value = _clientSocket != null;
        _clientSocket?.flush();
      }
    } else {
      _log.warning('_newConnection(${socket.remoteAddress}:${socket.remotePort}) - Someone is already connected so ignoring');
      _clientSendData({'code': codeAlreadyConnected, 'data': 'already connected'}, socket: socket);
      socket.destroy();
    }
  }

  void _clientDisconnected() {
    _log.info('_clientDisconnected(${_clientSocket?.remoteAddress}:${_clientSocket?.remotePort})');
    _closeClient();
    _startListener();
  }

  void _closeClient() {
    _log.info('_closeClient($_clientSocket)');
    _clientSocket?.close();
    _clientSocket?.destroy();
    _clientSocket = null;
    clientVersion = '';
    isConnected.value = false;
  }

  void _clientError(err) {
    _log.warning('_clientError($err)');
  }

  void _clientSendData(Map<String, dynamic> json, {Socket? socket}) {
    socket ??= _clientSocket;
    assert(socket != null, 'Trying to send when no connected clients');
    final strSend = jsonEncode(json);
    final lst = '${strSend.length}:$strSend';
    _log.fine('_clientSendData(${strSend.length})');
    debugPrint('lst: ${lst.length} bytes');
    socket!.add(utf8.encode(lst));
    // socket!.write(lst);
    // socket.flush();
  }

  void _selectAndSendTweet({int tweetIndex = 0}) {
    assert(tweetIndex >= -1 && tweetIndex <= 1, 'Invalid tweetIndex: $tweetIndex');
    _log.info('_selectAndSendTweet($tweetIndex)');
    final tweetProvider = read(providerTweetHeader);
    if (tweetProvider.tweets.isEmpty) {
      _log.info('_selectAndSendTweet - no unread tweets');
      _clientSendData(_createJSON(code: -2, data: 'No tweets'));
    }
    if (tweetIndex == -1) {
      if (--currentTweetIndex < 0) currentTweetIndex = tweetProvider.tweets.length - 1;
    } else if (tweetIndex == 1) {
      if (++currentTweetIndex >= tweetProvider.tweets.length) currentTweetIndex = 0;
    }
    _clientSendData(_createJSON(code: 2, data: tweetProvider.tweets[currentTweetIndex].toJson()));
  }

  Future<void> _selectAndSendFeed({int changeIndex = 0}) async {
    _log.info('_selectAndSendFeed($changeIndex)');
    assert(changeIndex >= -1 || changeIndex <= 1, 'Invalid changeIndex: $changeIndex');
    final feedProvider = read(providerFeedHeader);
    if (feedProvider.selectedArticle == null) {
      feedProvider.changeSelectedArticle = 0;
    } else if (changeIndex == -1) {
      feedProvider.selectPreviousArticle();
    } else if (changeIndex == 1) {
      feedProvider.selectNextArticle();
    }
    if (feedProvider.selectedArticle != null) {
      await feedProvider.selectedArticle!.articleDescription(read(rssDatabase));
      _clientSendData(_createJSON(code: 1, data: feedProvider.selectedArticle!.toJson()));
    } else {
      _log.info('_selectAndSendFeed - no unread feeds');
      _clientSendData(_createJSON(code: -1, data: 'No feeds'));
    }
  }

  Map<String, dynamic> _createJSON({required int code, required dynamic data}) {
    final feedProvider = read(providerFeedHeader);
    final tweetProvider = read(providerTweetHeader);
    return {
      'code': code,
      'data': data,
      'articleCount': feedProvider.articles.length,
      'articleIndex': feedProvider.selectedArticleIndexNotifier.value,
      'tweetCount': tweetProvider.tweets.length,
      'tweetIndex': currentTweetIndex,
      'running': read(monitoringRunning.notifier).state,
    };
  }

  void _clientDataReceived(Uint8List data) {
    final utfString = utf8.decode(data);
    _log.info('_clientDataReceived($utfString)');
    if (isConnected.value == false || clientVersion.isEmpty) {
      if (utfString.startsWith(socketHeadHello) && utfString.endsWith('.$_secret')) {
        clientVersion = utfString.split('$socketHeadHello:').last.split('.').first;
        isConnected.value = _clientSocket != null;
        debugPrint('Connected: $clientVersion, ${isConnected.value}');
        _selectAndSendFeed();
      } else {
        debugPrint('Invalid client request: "$utfString" != "$socketHeadHello"');
        _log.warning('_newConnection(${_clientSocket!.remoteAddress}:${_clientSocket!.remotePort}) - Invalid header. Stopping server - $utfString');
        _closeClient();
        isConnected.value = null;
        Future.delayed(const Duration(hours: 1), _startListener);
      }
    } else {
      debugPrint('decode');
      final json = jsonDecode(utfString) as Map<String, dynamic>;
      debugPrint('decoded: $json');
      switch (json['command']) {
        case 'start_monitor':
          read(rssProvider).startMonitoring();
          break;
        case 'previous_feed':
          _selectAndSendFeed(changeIndex: -1);
          break;
        case 'next_feed':
          _selectAndSendFeed(changeIndex: 1);
          break;
        case 'feed':
          _selectAndSendFeed();
          break;
        case 'previous_tweet':
          _selectAndSendTweet(tweetIndex: -1);
          break;
        case 'next_tweet':
          _selectAndSendTweet(tweetIndex: 1);
          break;
        case 'tweet':
          _selectAndSendTweet();
          break;
        case 'tweet_read':
          final tweetProvider = read(providerTweetHeader);
          final id = json['id'] as int;
          if (id >= 0) {
            tweetProvider.removeTweet(id);
            _selectAndSendTweet();
          }
          break;
        case 'article_read':
          final feedProvider = read(providerFeedHeader);
          final id = json['id'] as int;
          if (id >= 0) {
            feedProvider.changeArticleStatusById(id: id);
            _selectAndSendFeed();
          }
          break;
        default:
          _log.warning('_clientDataReceived - invalid command: (${json['command']})');
      }
    }
  }
}
