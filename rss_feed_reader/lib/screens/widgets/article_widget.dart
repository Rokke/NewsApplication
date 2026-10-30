import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/screens/widgets/lists/article_list_item.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';

// final articlesProvider = StreamProvider<List<ArticleData>>((ref) {
//   final db = ref.watch(rssDatabase);
//   final selectedFeed = ref.watch(selectedFeedId);
//   return db.articles(feedId: selectedFeed.state, status: ref.watch(filterShowArticleStatus).state);
// });
// final selectedArticleHelperProvider = StateProvider<SelectedArticleHelper?>((ref) => null);

class ArticleView extends ConsumerWidget {
  static final _log = Logger('ArticleView');
  const ArticleView({super.key});

  // static _changeArticleStatus(BuildContext context, List<ArticleEncode> articles, int index, StateController<SelectedArticleHelper?> selected, int status) async {
  //   debugPrint('_changeArticleStatus - selected: ${articles.length - 1 > index ? index + 1 : index - 1}, index: $index, newindex: ${articles.length - 1 > index ? index + 1 : index - 1}, length: ${articles.length}: change: ${articles[index].id}-${articles[index].title}');
  //   context.read(rssDatabase).updateArticleStatus(articleId: articles[index].id!, status: status);
  //   selected.state = articles.length - 1 <= index ? null : SelectedArticleHelper(articles[index + 1], (status) => _changeArticleStatus(context, articles, index + 1, selected, status));
  // }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedProvider = ref.read(providerFeedHeader);
    return Card(
      child: ValueListenableBuilder(
        valueListenable: feedProvider.isInitialized,
        builder: (context, bool initialized, child) => initialized
            ? AnimatedList(
                key: feedProvider.articleKey,
                initialItemCount: feedProvider.articles.length,
                itemBuilder: (BuildContext context, int index, animation) {
                  final article = feedProvider.articles[index];
                  // Look the article up by id when tapped: [index] is from build
                  // time and may be stale after removals.
                  int currentIndex() => feedProvider.articles.indexWhere((a) => a.id == article.id);
                  return SizeTransition(
                    sizeFactor: animation,
                    child: ArticleListItem(
                      article: article,
                      onRemoveArticle: () {
                        _log.info('ui: remove article tapped, id: ${article.id}, built at: $index, now: ${currentIndex()}');
                        feedProvider.changeArticleStatusById(id: article.id);
                      },
                      onSelectedArticle: () {
                        final now = currentIndex();
                        _log.info('ui: article tapped, id: ${article.id}, built at: $index, now: $now, ${FrameWatch.sinceLastFrame()}');
                        if (now >= 0) feedProvider.changeSelectedArticle = now;
                      },
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  'Ingen uleste RSS feed',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
      ),
    );
  }
}
