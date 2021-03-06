import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';

class UpdateFeedPopup extends ConsumerWidget {
  static final _log = Logger('UpdateFeedPopup');
  final FeedEncode feed;
  const UpdateFeedPopup(this.feed, {Key? key}) : super(key: key);
  static const heroTag = 'popupHeroUpdateFeed';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FeedFavData? feedFav;
    final favUrlChanged = ValueNotifier<String?>(null);
    final txtUrl = TextEditingController(text: feed.url), txtTitle = TextEditingController(text: feed.title), txtFavIcon = TextEditingController(text: feed.feedFav), txtTtl = TextEditingController(text: feed.ttl.toString());
    // context.read(feedFavIdProvider(feed.id!)).whenData((data) {
    //   feedFav = data;
    //   if (data != null) valueUrl.value = txtFavIcon.text = data.url;
    // });
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Hero(
          tag: heroTag + feed.id.toString(),
          child: Material(
            color: Colors.purple,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints.tightFor(width: 600, height: 500),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: txtUrl, decoration: const InputDecoration(labelText: 'RSS url')),
                      TextField(controller: txtTitle, decoration: const InputDecoration(labelText: 'Tittel')),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: txtFavIcon, decoration: const InputDecoration(labelText: 'FavIcon'))),
                          ValueListenableBuilder(
                            valueListenable: favUrlChanged,
                            builder: (context, String? changedUrlValue, _) {
                              // print('refesh: $valUrl');
                              return ElevatedButton.icon(
                                label: Container(height: 40),
                                style: ButtonStyle(backgroundColor: MaterialStateColor.resolveWith((states) => Colors.purple.shade700)),
                                // color: Colors.blue,
                                icon: changedUrlValue == null && feed.feedFav == null
                                    ? const Icon(Icons.rss_feed, color: Colors.red)
                                    : Image.network(
                                        changedUrlValue ?? feed.feedFav!,
                                        width: 30,
                                        fit: BoxFit.fitWidth,
                                        errorBuilder: (err, __, ___) {
                                          _log.warning('invalid imageurl: ${changedUrlValue ?? feed.feedFav}', err);
                                          return const Icon(Icons.error);
                                        },
                                      ),
                                onPressed: () {
                                  debugPrint('new: ${txtFavIcon.text}');
                                  favUrlChanged.value = txtFavIcon.text;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      TextField(controller: txtTtl, decoration: const InputDecoration(labelText: 'TTL')),
                      Expanded(child: Container()),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(onPressed: () => Navigator.pop(context, null), child: const Text('Avbryt')),
                          ElevatedButton(
                            onPressed: () async {
                              if (feed.id != null && (favUrlChanged.value != null || (txtTitle.text.isNotEmpty && txtTitle.text != feed.title) || (txtUrl.text.isNotEmpty && txtUrl.text != feed.url) || (txtTtl.text.isNotEmpty && int.tryParse(txtTtl.text) != feed.ttl))) {
                                if (await ref.read(providerFeedHeader).updateFeedInfo(feed, feedFav: favUrlChanged.value, title: txtTitle.text, url: txtUrl.text, ttl: int.tryParse(txtTtl.text))) Navigator.of(context).pop(true);
                              }
                            },
                            child: const Text('Lagre'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
