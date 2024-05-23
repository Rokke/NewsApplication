import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/providers/network.dart';
import 'package:rss_feed_reader/providers/tweet_list.dart';

final monitoringRunning = StateProvider<bool>((ref) => false);
// const TTL_MS = 60000;

// class RSSTree {
//   // final List<RSSArticle> _articles = [1, 2, 3, 4, 5, 6, 7].map((e) => RSSArticle('url $e')).toList();
// }

class RSSHead {
  final _log = Logger('RSSHead');
  Timer? _timer;
  final Ref ref;
  bool busy = false, tweetsFailing = false;
  RSSHead(this.ref); // : super(RSSTree());
  Future<void> startMonitoring({Duration? postponeStart}) async {
    _log.info('startMonitoring($postponeStart)');
    ref.read(monitoringRunning.notifier).state = true;
    final feedProvider = ref.read(providerFeedHeader);
    if (postponeStart != null) await Future.delayed(postponeStart);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!busy) {
        busy = true;
        try {
          if (!await feedProvider.findFeedToUpdate() && !tweetsFailing) await ref.read(providerTweetHeader).checkAndUpdateTweet(isAuto: true);
        } on NewsAppNetworkException catch (serr, stackTrace) {
          tweetsFailing = true;
          _log.warning('startMonitoring-error', serr, stackTrace);
        } catch (err) {
          _log.severe('startMonitoring-Monitor error-${err.runtimeType}', err);
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
    _log.info('stopMonitoring($ignoreProvider)');
    _timer?.cancel();
    _timer = null;
    if (!ignoreProvider) ref.read(monitoringRunning.notifier).state = false;
  }
}

final rssProvider = Provider<RSSHead>((ref) {
  ref.watch(providerConfig);
  Logger('rssProvider').info('rebuild');
  final rssHead = RSSHead(ref);
  ref.onDispose(() {
    Logger('rssProvider').info('onDispose');
    rssHead.stopMonitoring(ignoreProvider: true);
  });
  return rssHead;
});
