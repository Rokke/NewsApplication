import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/screens/widgets/category_widget.dart';
import 'package:rss_feed_reader/utils/misc_functions.dart';

class ArticleListItem extends ConsumerWidget {
  final ArticleEncode article;
  final Function() onRemoveArticle;
  final Function() onSelectedArticle;
  const ArticleListItem({Key? key, required this.article, required this.onRemoveArticle, required this.onSelectedArticle}) : super(key: key);

  static Widget articleContainer(BuildContext context, ArticleEncode article, {Function()? onRemoveArticle, bool isSelected = false, Function()? onSelectedArticle}) => Container(
        decoration: BoxDecoration(color: isSelected ? Colors.blue[900] : Colors.blue, borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(2),
        child: GestureDetector(
          onTap: isSelected && onSelectedArticle != null ? null : () => onSelectedArticle!(),
          child: Card(
            color: isSelected ? Colors.blue[800] : Colors.blue,
            elevation: isSelected ? 0 : 10,
            child: Stack(
              children: [
                ListTile(
                  leading: article.parent.feedFav != null
                      ? CachedNetworkImage(
                          imageUrl: article.parent.feedFav!,
                          fit: BoxFit.fitWidth,
                          width: 30,
                          errorWidget: (_, __, ___) => Container(),
                        )
                      : const Icon(Icons.visibility),
                  dense: true,
                  title: Text(article.title),
                  subtitle: Text(article.url),
                  // trailing: IconButton(
                  //   icon: article.status == ArticleTableStatus.FAVORITE ? Icon(Icons.favorite, color: Colors.red) : Icon(article.status == ArticleTableStatus.READ ? Icons.visibility_off : Icons.visibility),
                  //   onPressed: () => article.status != ArticleTableStatus.UNREAD ? context.read(rssDatabase).updateArticleStatus(articleId: article.id!, status: ArticleTableStatus.UNREAD) : onRemoveArticle(),
                  // ),
                ),
                if (article.category != null) Positioned(right: 50, top: 0, child: Wrap(children: article.category!.split(',').map((e) => CategoryWidget(article.id, e)).toList())),
                Positioned(
                  right: 50,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(3)),
                    child: Text(dateTimeFormat(DateTime.fromMillisecondsSinceEpoch(article.pubDate))),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedProvider = ref.read(providerFeedHeader);
    final selectedNotifier = ValueNotifier(false);
    try {
      return ValueListenableBuilder(
        valueListenable: feedProvider.selectedArticleIndexNotifier,
        builder: (context, int selectedIndex, child) {
          selectedNotifier.value = feedProvider.selectedArticle?.id == article.id;
          return child!;
        },
        child: ValueListenableBuilder(valueListenable: selectedNotifier, builder: (context, bool selected, _) => articleContainer(context, article, onRemoveArticle: onRemoveArticle, isSelected: selected, onSelectedArticle: onSelectedArticle)),
      );
    } catch (error) {
      debugPrint('Error: $article');
      return Text('error: $error');
    }
  }
}
