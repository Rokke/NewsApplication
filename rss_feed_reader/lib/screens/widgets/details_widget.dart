import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/screens/widgets/twitter_widget.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';
import 'package:rss_feed_reader/utils/misc_functions.dart';

final providerErrorReported = StateProvider<String?>((ref) => null);

class DetailStackWidget extends StatelessWidget {
  const DetailStackWidget({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('DetailsStack build');
    return Stack(
        fit: StackFit.loose,
        // height: 200,
        children: [
          // Column(
          //   mainAxisSize: MainAxisSize.min,
          //   children: [
          const DetailWidget(),
          Positioned(right: 0, bottom: 0, child: Container(constraints: const BoxConstraints.expand(width: 400, height: 500), child: const TwitterWidget()))
          //   ],
          // ),
        ]);
  }
}

class DetailWidget extends ConsumerStatefulWidget {
  const DetailWidget({super.key});

  @override
  ConsumerState<DetailWidget> createState() => _DetailWidgetState();
}

class _DetailWidgetState extends ConsumerState<DetailWidget> {
  static final _log = Logger('DetailWidget');
  // One node for the widget's lifetime: a new node on every build loses the
  // keyboard focus, and Delete / arrows stop working.
  final _focusNode = FocusNode(debugLabel: 'DetailWidget');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _log.finest('build');
    final feedProvider = ref.watch(providerFeedHeader);
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is! KeyDownEvent) return;
        switch (event.logicalKey) {
          case LogicalKeyboardKey.delete:
            _log.info('ui: key Delete, selected: ${feedProvider.selectedArticleIndexNotifier.value}, ${FrameWatch.sinceLastFrame()}');
            feedProvider.markCurrentAsRead();
            break;
          case LogicalKeyboardKey.arrowDown:
            _log.info('ui: key ArrowDown, selected: ${feedProvider.selectedArticleIndexNotifier.value}');
            feedProvider.selectNextArticle();
            break;
          case LogicalKeyboardKey.arrowUp:
            _log.info('ui: key ArrowUp, selected: ${feedProvider.selectedArticleIndexNotifier.value}');
            feedProvider.selectPreviousArticle();
            break;
        }
      },
      child: Card(
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
          child: ValueListenableBuilder(
            valueListenable: feedProvider.selectedArticleIndexNotifier,
            builder: (context, int selectedIndex, child) {
              final article = feedProvider.selectedArticle;
              return article != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          color: Colors.blue[800],
                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(color: Colors.purple[900], padding: const EdgeInsets.all(4), child: Text('${article.id}')),
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Text(
                                    article.title,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  ValueListenableBuilder(
                                    valueListenable: feedProvider.hasUndoItem,
                                    builder: (_, bool hasUndo, __) => IconButton(
                                      icon: const Icon(Icons.undo),
                                      onPressed: hasUndo
                                          ? () {
                                              _log.info('ui: undo pressed, ${FrameWatch.sinceLastFrame()}');
                                              feedProvider.unreadLastItem();
                                            }
                                          : null,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.open_in_browser),
                                    onPressed: () {
                                      _log.info('ui: open in browser pressed, id: ${article.id}');
                                      launchURL(article.url);
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.favorite,
                                      color: feedProvider.status == ArticleTableStatus.favorite ? Colors.red : null,
                                    ),
                                    onPressed: () {
                                      _log.info('ui: favorite pressed, idx: $selectedIndex, id: ${article.id}, ${FrameWatch.sinceLastFrame()}');
                                      feedProvider.changeArticleStatusByIndex(
                                          index: selectedIndex, newStatus: feedProvider.status != ArticleTableStatus.favorite ? ArticleTableStatus.favorite : ArticleTableStatus.unread);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.history),
                                    onPressed: feedProvider.last10ReadArticles.isEmpty
                                        ? null
                                        : () {
                                            _log.info('ui: history pressed (details)');
                                            feedProvider.showHistoryDialog(context);
                                          },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      feedProvider.status == ArticleTableStatus.read ? Icons.visibility_off : Icons.visibility,
                                      color: feedProvider.status == ArticleTableStatus.read ? Colors.green : null,
                                    ),
                                    tooltip: 'Seen',
                                    onPressed: () {
                                      _log.info('ui: seen pressed, idx: $selectedIndex, id: ${article.id}, ${FrameWatch.sinceLastFrame()}');
                                      feedProvider.changeArticleStatusByIndex(
                                          index: selectedIndex, newStatus: feedProvider.status != ArticleTableStatus.read ? ArticleTableStatus.read : ArticleTableStatus.unread);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.only(left: 5, right: TwitterWidget.twitterListWidth - 30, top: 5, bottom: 5),
                            child: FutureBuilder(
                              future: article.articleDescription(ref.read(rssDatabase)),
                              initialData: null,
                              builder: (BuildContext context, AsyncSnapshot snapshot) {
                                try {
                                  // debugPrint('snapshot: ${snapshot.data}');
                                  return !snapshot.hasData
                                      ? const CircularProgressIndicator()
                                      : snapshot.data is String
                                          ? SingleChildScrollView(
                                              // child: Text(snapshot.data)
                                              child: Html(
                                                data: snapshot.data as String,
                                                // onImageError: (err, obj) {
                                                //   ref.read(providerErrorReported.notifier).state = 'onImageError(): $err';
                                                //   _log.warning('onImageError(${article.id})=>$obj', err);
                                                // },
                                                // onMathError: (str1, str2, str3) {
                                                //   ref.read(providerErrorReported.notifier).state = 'onMathError()';
                                                //   _log.warning('onMathError(${article.id})=>$str1,$str2,$str3');
                                                //   return Container(constraints: const BoxConstraints.tightFor(width: 20, height: 20), color: Colors.red);
                                                // },
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                'Ingen beskrivelse',
                                                style: Theme.of(context).textTheme.displaySmall,
                                              ),
                                            );
                                } catch (err) {
                                  _log.severe('Error rendering text(${article.id})', err);
                                  return SingleChildScrollView(child: Text('No data: ${snapshot.data}'));
                                }
                              },
                            ),
                          ),
                        ),
                        Container(
                          color: Colors.purple[900],
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              if (article.creator != null)
                                Text(article.creator!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                              else
                                const Text('N/A', style: TextStyle(fontSize: 12)),
                              Flexible(
                                  child: (article.category != null)
                                      ? Text(article.category!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                                      : const Text('N/A', style: TextStyle(fontSize: 12))),
                              Text(dateTimeFormat(DateTime.fromMillisecondsSinceEpoch(article.pubDate)), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Text(
                        'Ingen artikkel valgt',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    );
            },
          ),
        ),
      ),
    );
  }
}
