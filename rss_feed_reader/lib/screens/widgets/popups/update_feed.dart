import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/feed_encode.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';

class UpdateFeedPopup extends ConsumerWidget {
  static final _log = Logger('UpdateFeedPopup');
  final FeedEncode feed;
  // final notifierCategories=ValueNotifier<List<(int,String)>>([]);
  const UpdateFeedPopup(this.feed, {super.key});
  // static const heroTag = 'popupHeroUpdateFeed';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FeedFavData? feedFav;
    final favUrlChanged = ValueNotifier<String?>(null);
    final txtUrl = TextEditingController(text: feed.url),
        txtTitle = TextEditingController(text: feed.title),
        txtFavIcon = TextEditingController(text: feed.feedFav),
        txtTtl = TextEditingController(text: feed.ttl.toString()),
        txtAddCategory = TextEditingController();
    // ref.read(rssDatabase).fetchCategories(feed.id!).then((value) => notifierCategories.value = value);
    // context.read(feedFavIdProvider(feed.id!)).whenData((data) {
    //   feedFav = data;
    //   if (data != null) valueUrl.value = txtFavIcon.text = data.url;
    // });
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
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
                    SizedBox(
                      height: 50,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 100,
                            child: TextField(
                                controller: txtAddCategory,
                                decoration: const InputDecoration(labelText: 'Category'),
                                onEditingComplete: () {
                                  ref.read(rssDatabase).insertFeedCategory(feed.id!, txtAddCategory.text).then((value) => ref.invalidate(providerCategories(feed.id!)));
                                  txtAddCategory.clear();
                                }),
                          ),
                          Flexible(child: SelectedCategoriesWidget(feed.id!)),
                        ],
                      ),
                    ),
                    // ValueListenableBuilder(valueListenable: notifierCategories, builder: (context, categories, _) => Wrap(children: categories.map((e) => Chip(label: Text(e.$2))).toList())),
                    Expanded(child: Container()),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(onPressed: () => Navigator.pop(context, null), child: const Text('Avbryt')),
                        ElevatedButton(
                          onPressed: () async {
                            if (feed.id != null &&
                                (favUrlChanged.value != null ||
                                    (txtTitle.text.isNotEmpty && txtTitle.text != feed.title) ||
                                    (txtUrl.text.isNotEmpty && txtUrl.text != feed.url) ||
                                    (txtTtl.text.isNotEmpty && int.tryParse(txtTtl.text) != feed.ttl))) {
                              if (await ref.read(providerFeedHeader).updateFeedInfo(feed, feedFav: favUrlChanged.value, title: txtTitle.text, url: txtUrl.text, ttl: int.tryParse(txtTtl.text))) {
                                if (context.mounted) Navigator.of(context).pop(true);
                              }
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
    );
  }
}

final providerCategories = FutureProviderFamily((ref, int feedId) => ref.watch(rssDatabase).fetchCategories(feedId));

class SelectedCategoriesWidget extends ConsumerWidget {
  final int feedId;
  const SelectedCategoriesWidget(this.feedId, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futureCategory = ref.watch(providerCategories(feedId));
    return futureCategory.when(
        data: (categories) => Wrap(children: categories.map((e) => Chip(label: Text(e.$2))).toList()), loading: () => const CircularProgressIndicator(), error: (err, stack) => const Text('Error'));
  }
}
