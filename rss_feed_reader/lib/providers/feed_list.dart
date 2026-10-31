import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/network.dart' as network;
import 'package:rss_feed_reader/screens/widgets/lists/article_list_item.dart';
import 'package:rss_feed_reader/screens/widgets/lists/feed_list_item.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';
import 'package:rss_feed_reader/utils/misc_functions.dart';

final providerFeedHeader = Provider<FeedListHeader>((ref) {
  return FeedListHeader(ref.watch(rssDatabase));
});

class FeedListHeader {
  static final _log = Logger('FeedListHeader');
  final _listFeedKey = GlobalKey<AnimatedListState>();
  final GlobalKey<AnimatedListState> _listArticleKey = GlobalKey<AnimatedListState>();
  final AppDb db;
  // final List<int> readIds = [];
  List<ArticleEncode> articles = [];
  List<ArticleEncode> last10ReadArticles = [];
  List<FeedEncode> feeds = [];
  int status = ArticleTableStatus.unread;
  // int? _lastRemovedId;
  final hasUndoItem = ValueNotifier(false);
  ValueNotifier<bool> isInitialized = ValueNotifier(false);
  final selectedArticleIndexNotifier = SelectionNotifier();
  bool selectNextArticle() {
    if (selectedArticleIndexNotifier.value < articles.length - 1) {
      _select(selectedArticleIndexNotifier.value + 1, 'next');
    } else {
      _log.fine('selectNextArticle()-at end(${selectedArticleIndexNotifier.value}, len: ${articles.length})');
      return false;
    }
    return true;
  }

  bool selectPreviousArticle() {
    if (selectedArticleIndexNotifier.value > 0) {
      _select(selectedArticleIndexNotifier.value - 1, 'previous');
    } else {
      _log.fine('selectPreviousArticle()-at start(${selectedArticleIndexNotifier.value}, len: ${articles.length})');
      return false;
    }
    return true;
  }

  ValueNotifier<int> numberOfArticleNotifier = ValueNotifier(0);
  void _updateAmountOfShownArticles() => numberOfArticleNotifier.value = articles.length;

  /// The selected article, or null when nothing is selected or the index no
  /// longer fits the list.
  ArticleEncode? get selectedArticle {
    final index = selectedArticleIndexNotifier.value;
    return index >= 0 && index < articles.length ? articles[index] : null;
  }

  // ignore: avoid_setters_without_getters
  set changeSelectedArticle(int index) {
    if (index < articles.length) {
      _select(index, 'changeSelectedArticle');
    } else {
      _log.warning('changeSelectedArticle($index)-out of range, len: ${articles.length}');
    }
  }

  /// Every selection change goes through here, so it is logged and the
  /// listeners are told even when the index stays the same but the article
  /// behind it changed (after a removal).
  void _select(int index, String reason) {
    final old = selectedArticleIndexNotifier.value;
    _log.info('select($reason): $old -> $index, id: ${index >= 0 && index < articles.length ? articles[index].id : '-'}, len: ${articles.length}');
    selectedArticleIndexNotifier.select(index);
    FrameWatch.noteChange('select($reason)');
  }

  /// Keeps the selection inside the list after articles were removed.
  void _clampSelection(String reason) {
    final index = selectedArticleIndexNotifier.value;
    if (index >= articles.length) _select(articles.length - 1, 'clamp after $reason');
  }

  FeedListHeader(this.db) {
    reloadFeeds();
  }
  Future<void> reloadFeeds() async {
    _log.info('reloadFeeds()');
    isInitialized.value = false;
    try {
      await _loadFeedsAndArticles();
    } catch (err, stack) {
      _log.severe('reloadFeeds()-failed', err, stack);
    }
    isInitialized.value = true;
  }

  Future<void> _loadFeedsAndArticles() async {
    final lastFound = DateTime.now().millisecondsSinceEpoch;
    feeds = (await db.feeds()).map((e) => FeedEncode.fromDB(e)).toList();
    for (final feed in feeds) {
      feed.activeArticles = (await db.fetchActiveArticles(feed.id!)).map<ArticleActiveRead>((f) => ArticleActiveRead(id: f.id, url: f.url, lastFoundEpoch: lastFound)).toList();
      _log.finest('active(${feed.id}): ${feed.activeArticles.length}');
    }
    articles = (await db.articles()).map((e) => ArticleEncode.fromDB(e, feeds)).toList();
    _log.info('reloadFeeds()-feeds: ${feeds.length}, articles: ${articles.length}');
    _updateAmountOfShownArticles();
    _clampSelection('reloadFeeds');
  }

  Future<bool> findFeedToUpdate({int waitTimeSeconds = 0}) async {
    var oldest = -1;
    for (var i = 0; i < feeds.length; i++) {
      if (oldest == -1 || feeds[i].earliestMillisecondsSinceEpoch < feeds[oldest].earliestMillisecondsSinceEpoch) oldest = i;
      if (feeds[oldest].lastCheck == 0) break;
    }
    if (oldest >= 0 && feeds[oldest].earliestMillisecondsSinceEpoch < DateTime.now().millisecondsSinceEpoch) {
      if (waitTimeSeconds > 0) {
        debugPrint('waiting: $waitTimeSeconds, ID: ${feeds[oldest].id}');
        await Future.delayed(Duration(seconds: waitTimeSeconds));
      }
      await updateOrCreateFeed(feeds[oldest]);
      return true;
    } else {
      _log.finest('Nothing to update');
    }
    return false;
  }

  Future<void> removeFeed(int feedId) async {
    final index = feeds.indexWhere((element) => element.id == feedId);
    if (index >= 0) {
      _log.warning('removeFeed($feedId)-remove, articles: ${articles.length}, selected: ${selectedArticleIndexNotifier.value}');
      isInitialized.value = false;
      await db.deleteFeed(feeds[index]);
      var foundArticleIndexToRemove = -1;
      while ((foundArticleIndexToRemove = articles.indexWhere((element) => element.parent.id == feedId)) >= 0) {
        _removeArticleFromList(articles[foundArticleIndexToRemove], foundArticleIndexToRemove);
      }
      final oldFeed = feeds.removeAt(index);
      _listFeedKey.currentState?.removeItem(index, (context, animation) => FeedListItem(feed: oldFeed));
      _updateAmountOfShownArticles();
      _clampSelection('removeFeed');
      _log.info('removeFeed($feedId)-done, articles: ${articles.length}, selected: ${selectedArticleIndexNotifier.value}');
      isInitialized.value = true;
    } else {
      _log.warning('removeFeed($feedId)-invalid id');
    }
  }

  Future<int> markAllRead(int feedId) {
    _log.info('markAllRead($feedId)-articles: ${articles.length}, selected: ${selectedArticleIndexNotifier.value}');
    final futureRet = db.markAllRead(feedId);
    int foundIndex;
    while ((foundIndex = articles.indexWhere((element) => element.parent.id == feedId)) >= 0) {
      final before = articles.length;
      changeArticleStatusByIndex(index: foundIndex);
      // A failed removal would otherwise spin here forever and freeze the app.
      if (articles.length >= before) {
        _log.severe('markAllRead($feedId)-article at $foundIndex was not removed, stopping');
        break;
      }
    }
    _clampSelection('markAllRead');
    _log.info('markAllRead($feedId)-done, articles: ${articles.length}, selected: ${selectedArticleIndexNotifier.value}');
    return futureRet;
  }

  Future<FeedFullDecode?> fetchFeedEncode(String url, {FeedEncode? parentFeed}) async {
    try {
      _log.fine('fetchFeedEncode($url)');
      final channel = await network.readChannel(url, log: _log);
      if (channel != null) return FeedFullDecode.fromChannel(channel, url, parentFeed: parentFeed, log: _log);
    } catch (err, stack) {
      _log.warning('fetchFeedEncode($url)', err, stack);
    }
    return null;
  }

  bool unreadLastItem() {
    if (last10ReadArticles.isNotEmpty) {
      final unread = last10ReadArticles.removeAt(0);
      _log.info('unreadLastItem: $unread');
      // final updateId = last10Read;
      hasUndoItem.value = last10ReadArticles.isNotEmpty;
      _restoreArticle(unread.id, 'undo');
      return true;
    } else {
      _log.warning('unreadLastItem - not valid');
    }
    return false;
  }

  /// Sets an article back to unread and puts it at the end of the list.
  Future<void> _restoreArticle(int articleId, String reason) async {
    try {
      await db.updateArticleStatus(articleId: articleId, status: ArticleTableStatus.unread);
      final articleData = await db.fetchSingleArticle(articleId: articleId);
      if (articleData != null) {
        await _addNewArticleToList(ArticleEncode.fromDB(articleData, feeds));
        if (selectedArticleIndexNotifier.value > -1) _select(-1, 'after $reason');
      } else {
        _log.warning('_restoreArticle($articleId, $reason)-not found in db');
      }
    } catch (err, stack) {
      _log.severe('_restoreArticle($articleId, $reason)', err, stack);
    }
  }

  /// Inserts like the feed timer does, for tests.
  @visibleForTesting
  Future<void> addArticleToList(ArticleEncode article) => _addNewArticleToList(article);

  Future<void> _addNewArticleToList(ArticleEncode article) async {
    int sortedIndex = articles.length;
    (article.parent as FeedEncode).activeArticles.add(ArticleActiveRead(id: article.id, url: article.url, lastFoundEpoch: DateTime.now().millisecondsSinceEpoch));
    articles.insert(sortedIndex, article);
    final listState = _listArticleKey.currentState;
    listState?.insertItem(sortedIndex);
    _log.info('_addNewArticleToList(${article.url})-id: ${article.id}, index: $sortedIndex, len: ${articles.length}, list mounted: ${listState != null}, selected: ${selectedArticleIndexNotifier.value}');
    _updateAmountOfShownArticles();
    if (selectedArticleIndexNotifier.value < 0) {
      _select(sortedIndex, 'first new article');
    } else {
      FrameWatch.noteChange('insert article ${article.id}');
    }
  }

  Future<bool> _addNewArticle(ArticleEncode article) async {
    assert(article.parent.id != null, "article can't be inserted with invalid parent.id");
    try {
      await db.insertArticle(article.toInsertCompanion).then((value) {
        article.id = value;
        _log.info('_addNewArticle(${article.url})-$value,${article.active}');
        return _addNewArticleToList(article).then((_) => true);
      }).onError((error, stackTrace) async {
        final found = await (db.select(db.article)..where((tbl) => tbl.parent.equals(article.parent.id!) & tbl.url.equals(article.url))).getSingleOrNull();
        if (found != null) {
          _log.warning('_addNewArticle()-Duplicate error: $error, found: ${found.id}');
          await (db.update(db.article)..where((tbl) => tbl.id.equals(found.id))).write(const ArticleCompanion(active: Value(true)));
          // debugPrint('statement: ret: $ret, ${await (db.select(db.article)..where((tbl) => tbl.id.equals(found.id))).getSingleOrNull()}');
          // (db.update(db.article)..where((tbl) => tbl.id.equals(found.id))).write(ArticleCompanion(active: Value(true)));
          (article.parent as FeedEncode).activeArticles.add(ArticleActiveRead(id: found.id, url: found.url, lastFoundEpoch: DateTime.now().millisecondsSinceEpoch));
        } else {
          _log.severe('_addNewArticle()-Different error?: $error');
        }
        return false;
      });
    } catch (err, stack) {
      _log.warning('_addNewArticle()-Article exist! $article', err, stack);
    }
    return false;
  }

  Future<void> updateOrCreateFeed(FeedEncode? feed, {String? imgUrl, String? url}) async {
    assert(feed != null || url != null, 'feed or url must be valid');
    bool hasFeeds = false;
    try {
      feed?.lastError = null;
      final feedFullEncode = await fetchFeedEncode(feed?.url ?? url!, parentFeed: feed);
      debugPrint('updateOrCreateFeed(${feedFullEncode?.feed})-${feedFullEncode?.articles.length},${feedFullEncode?.feed.activeArticles.length}');
      if (feedFullEncode != null) {
        final updatedFeed = feed?.id != null ? feed! : feedFullEncode.feed;
        // int newId;
        if (feed?.id == null) {
          // feed = feedFullEncode.feed;
          final fut = db.insertNewFeed(updatedFeed.toInsertCompanion);
          var index = feeds.indexWhere((element) => element.title.compareTo(updatedFeed.title) > 0);
          if (index == -1) {
            index = feeds.length - 1;
          } else {
            hasFeeds = true;
          }
          feeds.insert(index, updatedFeed);
          _listFeedKey.currentState?.insertItem(index);
          updatedFeed.id = await fut;
          _log.info('updateOrCreateFeed()-new feed(${updatedFeed.id})');
        } else {
          _log.info('updateOrCreateFeed()-update lastCheck on feed(${updatedFeed.id})');
          assert(updatedFeed.id != null);
          updatedFeed.lastCheck = feedFullEncode.feed.lastCheck;
          updatedFeed.lastBuildDate = feedFullEncode.feed.lastBuildDate;
          _log.info('updateOrCreateFeed(): ${await db.updateFeed(updatedFeed.id!, FeedCompanion(lastCheck: Value(updatedFeed.lastCheck)))}');
        }
        _log.finer('update/add-Feed: ${updatedFeed.id}');
        try {
          final lastEpoch = DateTime.now().millisecondsSinceEpoch;
          int newArticles = 0;
          final saveOnlyCategories = await db.fetchCategories(updatedFeed.id!);
          for (final article in feedFullEncode.articles) {
            if (saveOnlyCategories.isNotEmpty && !saveOnlyCategories.any((element) => article.category?.contains(element.$2) ?? false)) {
              _log.info('Ignoring item: ${article.id}-${article.title}(${article.url}), wrong category: ${article.category}');
            } else if (article.url.isNotEmpty) {
              final foundArticle = updatedFeed.activeArticles.indexWhere((element) => element.url.compareTo(article.url) == 0);
              if (foundArticle < 0) {
                _log.info('Adding new item: ${article.title}(${article.url})');
                newArticles++;
                await _addNewArticle(article);
              } else {
                updatedFeed.activeArticles[foundArticle].lastFoundEpoch = lastEpoch;
                _log.finer('updateOrCreateFeed()-update lastFoundEpoch on article($updatedFeed)');
              }
            } else {
              _log.warning('Ignoring empty item: ${article.guid}');
            }
          }
          _log.fine('Finished with ${feedFullEncode.articles.length} articles, new: $newArticles');
          int indexToRemove = -1;
          final batchIds = <int>[];
          while ((indexToRemove = updatedFeed.activeArticles.indexWhere((element) => element.lastFoundEpoch < lastEpoch)) >= 0) {
            batchIds.add(updatedFeed.activeArticles[indexToRemove].id);
            updatedFeed.activeArticles.removeAt(indexToRemove);
          }
          await db.removeActiveStatus(batchIds);
          if (!hasFeeds && newArticles > 0) {
            playSound(soundFile: SoundFile.soundNewItem, log: _log);
          }
          _log.info('Still active($hasFeeds, $newArticles): ${updatedFeed.activeArticles.map((e) => e.id).join(",")}, new: $newArticles');
        } catch (err, stack) {
          _log.severe('updateOrCreateFeed()-Error', err, stack);
        }
      } else {
        _log.warning('No feed found for: $url');
        feed?.lastCheck = DateTime.now().millisecondsSinceEpoch;
      }
    } on SocketException catch (err) {
      _log.warning('Error calling url: $err');
      if (feed?.id != null) {
        feed!.lastError = 'Error: $err';
        feed.lastCheck = DateTime.now().millisecondsSinceEpoch;
        await db.updateFeed(feed.id!, FeedCompanion(lastCheck: Value(feed.lastCheck)));
      }
    } catch (err, stack) {
      _log.warning('updateOrCreateFeed($feed)', err, stack);
      throw Exception('updateOrCreateFeed-Error');
    }
  }

  Value<T> _valueOrAbsent<T>(T? newValue, dynamic previous) => (newValue == null || newValue == previous) ? const Value.absent() : Value(newValue);
  Future<bool> updateFeedInfo(FeedEncode feed, {String? feedFav, String? title, String? url, int? ttl}) async {
    _log.info('updateFeedInfo($feed, $feedFav, $title, $url, $ttl)-${feed.id}');
    if (feed.id != null) {
      (db.update(db.feed)..where((tbl) => tbl.id.equals(feed.id!)))
          .write(FeedCompanion(feedFav: _valueOrAbsent(feedFav, feed.feedFav), title: _valueOrAbsent(title, feed.title), url: _valueOrAbsent(url, feed.url), ttl: _valueOrAbsent(ttl, feed.ttl)))
          .then(
        (value) {
          if (value != 1) {
            _log.warning(
                'updateFeedInfo-!Changed: ${feed.id}, $value, ${FeedCompanion(feedFav: _valueOrAbsent(feedFav, feed.feedFav), title: _valueOrAbsent(title, feed.title), url: _valueOrAbsent(url, feed.url), ttl: _valueOrAbsent(ttl, feed.ttl))}');
          }
        },
      );
      feed.feedFav = feedFav ?? feed.feedFav;
      feed.ttl = ttl ?? feed.ttl;
      feed.title = title ?? feed.title;
      feed.url = url ?? feed.url;
      return true;
    }
    return false;
  }

  /// Removes the article from [articles] and from the AnimatedList. The model
  /// is updated even when the list isn't mounted, so the two can't drift apart.
  void _removeArticleFromList(ArticleEncode article, int index) {
    final listState = _listArticleKey.currentState;
    if (listState != null) {
      listState.removeItem(index, (context, animation) => SizeTransition(sizeFactor: animation, child: ArticleListItem.articleContainer(context, article)), duration: const Duration(milliseconds: 500));
    } else {
      _log.warning('_removeArticleFromList(${article.id}, $index)-article list not mounted');
    }
    last10ReadArticles.insert(0, articles.removeAt(index));
    if (last10ReadArticles.length > 10) last10ReadArticles.removeLast();
    _log.info('_removeArticleFromList(${article.id})-index: $index, len: ${articles.length}');
  }

  void markCurrentAsRead() {
    if (selectedArticleIndexNotifier.value >= 0) {
      changeArticleStatusByIndex(index: selectedArticleIndexNotifier.value);
    } else {
      _log.fine('markCurrentAsRead()-nothing selected');
    }
  }

  void changeArticleStatusByIndex({required int index, int newStatus = ArticleTableStatus.read}) {
    if (index < 0 || index >= articles.length) {
      _log.warning('changeArticleStatusByIndex($index, $newStatus)-invalid index, len: ${articles.length}');
      return;
    }
    try {
      final article = articles[index];
      _log.info('changeArticleStatus-remove(${article.id}, $index, $newStatus)-len: ${articles.length}, selected: ${selectedArticleIndexNotifier.value}');
      db.updateArticleStatus(articleId: article.id, status: newStatus).catchError((Object err, StackTrace stack) {
        _log.severe('changeArticleStatus(${article.id}, $newStatus)-db update failed', err, stack);
        return 0;
      });
      if (newStatus == ArticleTableStatus.read) {
        hasUndoItem.value = true;
        _removeArticleFromList(article, index);
      }
      // The article at [index] is now the next one: select it again so the
      // details pane follows. Past the end (the last article was marked)
      // select nothing, so the first new article that arrives gets selected
      // instead of the one being kept for later.
      _select(index < articles.length ? index : -1, 'after status change');
      _updateAmountOfShownArticles();
    } catch (err, stack) {
      _log.severe('changeArticleStatus exception', err, stack);
    }
  }

  void showHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return AlertDialog(
          title: const Text('History'),
          content: SizedBox(
            height: size.height - 200,
            width: size.width - 200,
            child: ListView(
              children: last10ReadArticles
                  .map((e) => ListTile(
                      title: Text(e.title),
                      subtitle: Text(e.url),
                      trailing: IconButton(
                          icon: const Icon(Icons.undo),
                          onPressed: () {
                            _log.info('ui: history undo pressed, id: ${e.id}');
                            last10ReadArticles.remove(e);
                            hasUndoItem.value = last10ReadArticles.isNotEmpty;
                            _restoreArticle(e.id, 'history');
                            Navigator.of(context).pop();
                          })))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void changeArticleStatusById({required int id, int newStatus = ArticleTableStatus.read}) {
    assert(id > 0, 'changeArticleStatusById($id, $newStatus)');
    _log.info('changeArticleStatusById($id, $newStatus)');
    final foundIndex = articles.indexWhere((element) => element.id == id);
    if (foundIndex >= 0) {
      changeArticleStatusByIndex(index: foundIndex, newStatus: newStatus);
    } else {
      _log.warning('changeArticleStatusById($id)-not in list, len: ${articles.length}');
    }
  }

  GlobalKey<AnimatedListState> get articleKey => _listArticleKey;
  GlobalKey<AnimatedListState> get feedKey => _listFeedKey;
}

/// Selected article index. [select] notifies the listeners even when the index
/// stays the same, because after a removal the same index is a new article.
class SelectionNotifier extends ValueNotifier<int> {
  SelectionNotifier() : super(-1);

  void select(int index) {
    if (index == value) {
      notifyListeners();
    } else {
      value = index;
    }
  }
}
