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
}
