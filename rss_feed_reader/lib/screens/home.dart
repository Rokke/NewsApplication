import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:resizable_widget/resizable_widget.dart';
import 'package:rss_feed_reader/models/rss_tree.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/screens/widgets/appbar_widget.dart';
import 'package:rss_feed_reader/screens/widgets/article_widget.dart';
import 'package:rss_feed_reader/screens/widgets/details_widget.dart';
import 'package:rss_feed_reader/screens/widgets/feed_widget.dart';
import 'package:window_manager/window_manager.dart';

final applicationVersionProvider = FutureProvider<PackageInfo>((ref) {
  final rss = ref.watch(rssProvider);
  final pi = PackageInfo.fromPlatform();
  if (kReleaseMode && !rss.started) rss.startMonitoring(postponeStart: const Duration(seconds: 20));
  return pi;
});

// class AppInfo {
//   PackageInfo? _pInfo;
//   final _log = Logger('AppInfoNotifier');
//   AppInfoNotifier(RSSHead rss) {
//     _init(rss);
//   }

//   _init(RSSHead rss) async {
//     _pInfo = await PackageInfo.fromPlatform();
//     _log.info('App starting $this');
//     if (kReleaseMode) rss.startMonitoring(postponeStart: Duration(seconds: 20));
//   }

//   bool get initialized => _pInfo != null;
//   String? get appName => _pInfo?.appName;
//   String? get packageName => _pInfo?.packageName;
//   String? get buildNumber => _pInfo?.buildNumber;
//   String? get version => _pInfo?.version;
//   @override
//   String toString() {
//     return '$appName - $version.$buildNumber. $packageName';
//   }
// }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WindowListener {
  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() {
    ref.read(providerConfig).checkWindowSize();
    super.onWindowMoved();
  }

  @override
  void onWindowResized() {
    ref.read(providerConfig).checkWindowSize();
    super.onWindowResized();
  }

  @override
  void onWindowEnterFullScreen() {
    ref.read(providerConfig).checkWindowSize();
    super.onWindowEnterFullScreen();
  }

  @override
  void onWindowLeaveFullScreen() {
    ref.read(providerConfig).checkWindowSize();
    super.onWindowLeaveFullScreen();
  }

  @override
  Widget build(BuildContext context) {
    PackageInfo.fromPlatform().then((appVersion) => debugPrint('Future: ${appVersion.appName}-${appVersion.buildNumber}-${appVersion.packageName}-${appVersion.version}'));
    final appVersionFuture = ref.watch(applicationVersionProvider);
    final config = ref.watch(providerConfig);
    final screenSize = MediaQuery.sizeOf(context);
    return Scaffold(
      drawer: SizedBox(width: screenSize.width < 500 ? screenSize.width / 1.15 : 500, child: const Drawer(child: FeedView())),
      appBar: appVersionFuture.when(
        data: (appVersion) => PreferredSize(
          preferredSize: Size.fromHeight(Platform.isWindows ? 30 : 56),
          child: CustomAppBarWidget(appVersion),
        ),
        loading: () => AppBar(
          title: const Text('Starter...'),
          actions: [
            const CircularProgressIndicator(),
            IconButton(
                icon: const Icon(Icons.exit_to_app),
                onPressed: () {
                  windowManager.close();
                  exit(0);
                }),
          ],
        ),
        error: (_, __) => AppBar(title: const Text('RSS Oversikt'), actions: [
          IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () {
                windowManager.close();
                exit(0);
              }),
        ]),
      ),
      body: screenSize.height > 700
          ? ResizableWidget(
              separatorSize: 3,
              isHorizontalSeparator: true,
              percentages: config.percentages,
              onResized: (sizes) {
                config.updatePercentage(sizes.first.percentage);
              },
              children: const [
                ArticleView(),
                DetailStackWidget(),
              ],
            )
          : const ArticleView(),
    );
  }
}
