import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/providers/tweet_list.dart';

final monitoringRunning = StateProvider<bool>((ref) => false);
// const TTL_MS = 60000;

// class RSSTree {
//   // final List<RSSArticle> _articles = [1, 2, 3, 4, 5, 6, 7].map((e) => RSSArticle('url $e')).toList();
// }

class RSSHead {
  final _log = Logger('RSSHead');
  Timer? _timer;
  final Reader read;
  bool busy = false;
  RSSHead(this.read); // : super(RSSTree());
  Future<void> startMonitoring({Duration? postponeStart}) async {
    _log.info('startMonitoring($postponeStart)');
    read(monitoringRunning.notifier).state = true;
    final feedProvider = read(providerFeedHeader);
    if (postponeStart != null) await Future.delayed(postponeStart);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!busy) {
        busy = true;
        try {
          if (!await feedProvider.findFeedToUpdate()) await read(providerTweetHeader).checkAndUpdateTweet(isAuto: true);
        } catch (err) {
          _log.severe('Monitor error', err);
          stopMonitoring();
        } finally {
          busy = false;
        }
      }
    });
  }

  bool get started => _timer != null;

  // Future<bool> findTweetToUpdate() async {
  // }

  void stopMonitoring({bool ignoreProvider = false}) {
    debugPrint('stopMonitoring($ignoreProvider)');
    _timer?.cancel();
    _timer = null;
    if (!ignoreProvider) read(monitoringRunning.notifier).state = false;
  }
}

final rssProvider = Provider<RSSHead>((ref) {
  ref.watch(providerConfig);
  Logger('rssProvider').info('rebuild');
  final rssHead = RSSHead(ref.read);
  ref.onDispose(() {
    debugPrint('onDispose');
    rssHead.stopMonitoring(ignoreProvider: true);
  });
  return rssHead;
});
