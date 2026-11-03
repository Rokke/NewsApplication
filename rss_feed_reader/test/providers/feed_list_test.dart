import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';

import '../helpers/test_db.dart';

Future<FeedListHeader> _loadedHeader(AppDb db) async {
  final header = FeedListHeader(db);
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!header.isInitialized.value) {
    if (DateTime.now().isAfter(deadline)) fail('FeedListHeader never finished loading');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return header;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.where((r) => r.level >= Level.WARNING).listen((r) => debugPrint('${r.loggerName} ${r.level} ${r.message} ${r.error ?? ''}'));

  late AppDb db;
  late int feedId;

  setUp(() async {
    db = openTestDb();
    feedId = await seedArticles(db, 8);
  });

  tearDown(() => db.close());

  test('seen on the selected article selects the next one', () async {
    final header = await _loadedHeader(db);
    header.changeSelectedArticle = 4;
    var notified = 0;
    header.selectedArticleIndexNotifier.addListener(() => notified++);

    header.markCurrentAsRead();

    expect(header.articles, hasLength(7));
    expect(header.selectedArticleIndexNotifier.value, 4);
    expect(header.selectedArticle!.title, 'Article 5');
    // Same index, new article: the details pane must still be told.
    expect(notified, greaterThan(0));
  });

  test('seen on the last article leaves nothing selected', () async {
    final header = await _loadedHeader(db);
    header.changeSelectedArticle = 7;

    header.markCurrentAsRead();

    expect(header.articles, hasLength(7));
    expect(header.selectedArticleIndexNotifier.value, -1);
    expect(header.selectedArticle, isNull);
  });

  test('after seen on the last article the next new article gets selected', () async {
    final header = await _loadedHeader(db);
    header.changeSelectedArticle = 7;
    header.markCurrentAsRead();

    final newArticle = ArticleEncode(id: 999, parent: header.feeds.first, title: 'New', pubDate: 2000, url: 'https://example.com/new', guid: 'new');
    await header.addArticleToList(newArticle);

    expect(header.selectedArticle!.title, 'New');
  });

  test('a timer insert right after a remove keeps the indexes in step', () async {
    final header = await _loadedHeader(db);
    header.changeSelectedArticle = 4;
    header.markCurrentAsRead();

    // The feed timer appends while the remove animation would still run.
    final newArticle = ArticleEncode(id: 999, parent: header.feeds.first, title: 'New', pubDate: 2000, url: 'https://example.com/new', guid: 'new');
    await header.addArticleToList(newArticle);

    expect(header.articles.map((a) => a.title), ['Article 0', 'Article 1', 'Article 2', 'Article 3', 'Article 5', 'Article 6', 'Article 7', 'New']);
    expect(header.selectedArticle!.title, 'Article 5');
    expect(header.numberOfArticleNotifier.value, 8);
  });

  test('mark all read leaves no out-of-range selection', () async {
    final header = await _loadedHeader(db);
    header.changeSelectedArticle = 6;

    await header.markAllRead(feedId);

    expect(header.articles, isEmpty);
    expect(header.selectedArticleIndexNotifier.value, -1);
    expect(header.selectedArticle, isNull);
  });

  test('selectedArticle is null instead of throwing when the index is stale', () async {
    final header = await _loadedHeader(db);
    header.selectedArticleIndexNotifier.value = 42;

    expect(header.selectedArticle, isNull);
  });

  test('a status change on an invalid index is ignored', () async {
    final header = await _loadedHeader(db);
    header.changeSelectedArticle = 2;

    header.changeArticleStatusByIndex(index: 8);

    expect(header.articles, hasLength(8));
    expect(header.selectedArticleIndexNotifier.value, 2);
  });

  group('a fetch whose links changed but whose guids stayed (#18)', () {
    ArticleEncode fetched(FeedEncode feed, int i, {String host = 'example.org', String? guid, int? pubDate}) =>
        ArticleEncode(parent: feed, title: 'Article $i', pubDate: pubDate ?? 1000 + i, url: 'https://$host/$i', guid: guid ?? 'guid-$i');

    test('adds no rows and moves the urls', () async {
      final header = await _loadedHeader(db);
      final feed = header.feeds.first;

      final added = await header.addFetchedArticles(feed, [for (var i = 0; i < 8; i++) fetched(feed, i)]);

      expect(added, 0);
      final rows = await db.select(db.article).get();
      expect(rows, hasLength(8));
      expect(rows.map((r) => r.url), everyElement(startsWith('https://example.org/')));
      expect(rows.map((r) => r.active), everyElement(isTrue));
      expect(header.articles, hasLength(8));
      expect(feed.activeArticles.map((a) => a.url), everyElement(startsWith('https://example.org/')));

      // The next fetch finds them by url again.
      expect(await header.addFetchedArticles(feed, [for (var i = 0; i < 8; i++) fetched(feed, i)]), 0);
      expect(await db.select(db.article).get(), hasLength(8));
    });

    test('keeps a read article read', () async {
      final header = await _loadedHeader(db);
      final feed = header.feeds.first;
      await header.markAllRead(feedId);

      final added = await header.addFetchedArticles(feed, [for (var i = 0; i < 8; i++) fetched(feed, i)]);

      expect(added, 0);
      expect(header.articles, isEmpty);
      expect(await db.articles(status: ArticleTableStatus.unread), isEmpty);
      expect(await db.select(db.article).get(), hasLength(8));
    });

    test('a guid shared by several items in one fetch is not used', () async {
      final header = await _loadedHeader(db);
      final feed = header.feeds.first;

      final added = await header.addFetchedArticles(feed, [fetched(feed, 1, host: 'a.org', guid: 'guid-1'), fetched(feed, 2, host: 'a.org', guid: 'guid-1')]);

      expect(added, 2);
      expect(await db.select(db.article).get(), hasLength(10));
    });

    test('skips a new item far older than the newest known article', () async {
      final header = await _loadedHeader(db);
      final feed = header.feeds.first;
      const day = 24 * 3600 * 1000;

      final added = await header.addFetchedArticles(feed, [
        fetched(feed, 20, guid: 'old', pubDate: 1007 - 181 * day),
        fetched(feed, 21, guid: 'recent', pubDate: 1007 - 10 * day),
        fetched(feed, 22, guid: 'new', pubDate: 1007 + day),
      ]);

      expect(added, 2);
      final urls = (await db.select(db.article).get()).map((r) => r.url);
      expect(urls, isNot(contains('https://example.org/20')));
      expect(urls, containsAll(['https://example.org/21', 'https://example.org/22']));
    });
  });
}
