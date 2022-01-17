import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:news_client_application/models/socket_response.dart';
import 'package:news_client_application/settings_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:news_client_application/providers/socket_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

class HomePage extends ConsumerStatefulWidget {
  HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool showFeeds = true;
  void launchURL(String url) async {
    final completeUrl = url.startsWith('http') ? url : 'http://$url';
    await launch(completeUrl);
  }

  @override
  Widget build(BuildContext context) {
    String url = '';
    final width = MediaQuery.of(context).size.width / 3;
    final socketProvider = ref.read(providerSocket);
    return ValueListenableBuilder(
      valueListenable: socketProvider.status,
      builder: (BuildContext context, SocketStatus status, Widget? child) => Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              IconButton(
                  onPressed: () {
                    setState(() {
                      showFeeds = !showFeeds;
                    });
                    socketProvider.clientSendData({'command': showFeeds ? 'feed' : 'tweet'});
                  },
                  icon: Icon(Icons.refresh)),
              Text(showFeeds ? 'RSS news' : 'Tweet news'),
            ],
          ),
          actions: [
            if (socketProvider.isConnected) IconButton(onPressed: () => socketProvider.clientSendData({'command': showFeeds ? 'previous_feed' : 'previous_tweet'}), icon: Icon(Icons.skip_previous)),
            if (socketProvider.isConnected) IconButton(onPressed: () => url.isNotEmpty ? launchURL(url) : null, icon: Icon(Icons.open_in_browser)),
            if (socketProvider.isConnected) IconButton(onPressed: () => socketProvider.clientSendData({'command': showFeeds ? 'next_feed' : 'next_tweet'}), icon: Icon(Icons.skip_next)) else if (status == SocketStatus.WAITING) CircularProgressIndicator() else Icon(Icons.no_cell, color: Colors.red),
            if (status == SocketStatus.CONNECTED_NOTRUNNING) IconButton(onPressed: () => socketProvider.clientSendData({'command': 'start_monitor'}), icon: Icon(Icons.play_arrow_sharp, color: Colors.red)) else if (status == SocketStatus.CONNECTED_RUNNING) Icon(Icons.check, color: Colors.green),
            IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => SettingsScreen())), icon: const Icon(Icons.settings)),
          ],
        ),
        body: socketProvider.isValid
            ? StreamBuilder<SocketResponse>(
                stream: socketProvider.stream,
                initialData: null,
                builder: (BuildContext context, AsyncSnapshot<SocketResponse> snapshot) {
                  if (snapshot.hasData) {
                    if (snapshot.data != null) {
                      if (snapshot.data!.code >= 1 && snapshot.data!.newsItem != null) {
                        final item = snapshot.data!.newsItem!;
                        url = item.url;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: EdgeInsets.all(4),
                              color: Theme.of(context).primaryColor,
                              child: Center(
                                child: Text(
                                  item.title,
                                  style: Theme.of(context).primaryTextTheme.bodyText1,
                                ),
                              ),
                            ),
                            if (item.text.isNotEmpty)
                              Expanded(
                                  child: showFeeds
                                      ? Html(
                                          data: item.text,
                                          shrinkWrap: true,
                                        )
                                      : Linkify(
                                          text: item.text,
                                          onOpen: (link) => launchURL(link.text),
                                          style: Theme.of(context).textTheme.headline6,
                                        ))
                            else
                              Expanded(child: Center(child: Text('No description'))),
                            Container(
                              color: Theme.of(context).bottomAppBarColor,
                              child: Row(children: [
                                Container(
                                    width: width,
                                    alignment: Alignment.centerLeft,
                                    child: item.imageUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: item.imageUrl!,
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.center,
                                            height: 40,
                                            errorWidget: (_, __, ___) => Container(),
                                          )
                                        : Container()),
                                Container(
                                  width: width,
                                  child: Center(
                                    child: ElevatedButton(
                                      style: ButtonStyle(elevation: MaterialStateProperty.resolveWith((states) => 0), shadowColor: MaterialStateProperty.all<Color>(Colors.red)),
                                      onPressed: () => socketProvider.clientSendData({'command': showFeeds ? 'article_read' : 'tweet_read', 'id': item.id}),
                                      child: Container(
                                        width: 100,
                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                                        child: Icon(
                                          Icons.delete,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                    constraints: BoxConstraints.tightFor(height: 40, width: width),
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      alignment: Alignment.center,
                                      color: Theme.of(context).disabledColor,
                                      height: 40,
                                      width: 100,
                                      child: Stack(
                                        children: [
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              showFeeds ? '${snapshot.data!.currentArticle + 1}/${snapshot.data!.numberOfArticles}' : '${snapshot.data!.currentTweet + 1}/${snapshot.data!.numberOfTweets}',
                                              style: Theme.of(context).primaryTextTheme.headline6,
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              showFeeds ? '${snapshot.data!.currentTweet + 1}/${snapshot.data!.numberOfTweets}' : '${snapshot.data!.currentArticle + 1}/${snapshot.data!.numberOfArticles}',
                                              style: Theme.of(context).primaryTextTheme.bodyText1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ]),
                            )
                          ],
                        );
                      }
                      return Center(
                          child: Text(
                        snapshot.data!.code == -1
                            ? 'Ingen artikler'
                            : snapshot.data!.code == -2
                                ? 'Ingen tweets'
                                : 'Unknown type',
                        style: Theme.of(context).textTheme.headline3,
                      ));
                    } else
                      return Container(child: Text('No data'));
                  } else
                    return Container(
                      child: Text('No snapshot'),
                    );
                },
              )
            : IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => SettingsScreen())), icon: const Icon(Icons.settings)),
      ),
    );
  }
}
