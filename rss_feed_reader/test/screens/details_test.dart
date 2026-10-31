import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/screens/widgets/article_widget.dart';
import 'package:rss_feed_reader/screens/widgets/details_widget.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDb db;
  late ProviderContainer container;

  Finder detailsTitle(String title) => find.descendant(of: find.byType(DetailWidget), matching: find.text(title));

  Future<FeedListHeader> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      db = openTestDb();
      await seedArticles(db, 8);
    });
    container = ProviderContainer(overrides: [rssDatabase.overrideWithValue(db)]);
    addTearDown(container.dispose);
    late FeedListHeader header;
    await tester.runAsync(() async {
      header = container.read(providerFeedHeader);
      while (!header.isInitialized.value) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Column(children: [Expanded(child: ArticleView()), Expanded(child: DetailWidget())]),
        ),
      ),
    ));
    await tester.pump();
    return header;
  }

  Future<void> settle(WidgetTester tester) async {
    // Let the description lookup finish, then run the 500 ms remove animation.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  testWidgets('seen shows the next article, also when the feed timer inserts during the remove animation', (tester) async {
    final header = await pumpScreen(tester);
    header.changeSelectedArticle = 4;
    await settle(tester);
    expect(detailsTitle('Article 4'), findsOneWidget);

    await tester.tap(find.byTooltip('Seen'));
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-animation insert, the way the feed timer does it.
    await header.addArticleToList(ArticleEncode(id: 999, parent: header.feeds.first, title: 'New', pubDate: 2000, url: 'https://example.com/new', guid: 'new'));
    await settle(tester);

    expect(detailsTitle('Article 4'), findsNothing);
    expect(detailsTitle('Article 5'), findsOneWidget);
    expect(header.articles, hasLength(8));
    // The list shows exactly the model: the removed one is gone, the new one is there.
    final listed = find.descendant(of: find.byType(ArticleView), matching: find.byType(ListTile));
    expect(listed, findsNWidgets(8));
    expect(find.descendant(of: find.byType(ArticleView), matching: find.text('Article 4')), findsNothing);
    expect(find.descendant(of: find.byType(ArticleView), matching: find.text('New')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seen on the last article shows no article without throwing', (tester) async {
    final header = await pumpScreen(tester);
    header.changeSelectedArticle = 7;
    await settle(tester);

    await tester.tap(find.byTooltip('Seen'));
    await settle(tester);

    expect(header.selectedArticle, isNull);
    expect(find.text('Ingen artikkel valgt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale selection shows "no article" instead of an error', (tester) async {
    final header = await pumpScreen(tester);
    header.selectedArticleIndexNotifier.value = 42;
    await settle(tester);

    expect(find.text('Ingen artikkel valgt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
