import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:resizable_widget/resizable_widget.dart';
import 'package:rss_feed_reader/models/rss_tree.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';
import 'package:rss_feed_reader/screens/widgets/appbar_widget.dart';
import 'package:rss_feed_reader/screens/widgets/article_widget.dart';
import 'package:rss_feed_reader/screens/widgets/details_widget.dart';
import 'package:rss_feed_reader/screens/widgets/feed_widget.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';
import 'package:rss_feed_reader/utils/log_file.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> with WindowListener, WidgetsBindingObserver {
  static final _log = Logger('HomeScreen');
  @override
  void initState() {
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.info('lifecycle: $state, ${FrameWatch.sinceLastFrame()}');
    if (state == AppLifecycleState.resumed) FrameWatch.forceFrame('resumed');
  }

  @override
  void onWindowFocus() {
    _log.info('window: focus, ${FrameWatch.sinceLastFrame()}');
    FrameWatch.forceFrame('window focus');
    super.onWindowFocus();
  }

  @override
  void onWindowBlur() {
    _log.info('window: blur');
    super.onWindowBlur();
  }

  @override
  void onWindowMinimize() {
    _log.info('window: minimize');
    super.onWindowMinimize();
  }

  @override
  void onWindowRestore() {
    _log.info('window: restore, ${FrameWatch.sinceLastFrame()}');
    FrameWatch.forceFrame('window restore');
    super.onWindowRestore();
  }

  @override
  void onWindowMaximize() {
    _log.info('window: maximize');
    super.onWindowMaximize();
  }

  @override
  void onWindowUnmaximize() {
    _log.info('window: unmaximize');
    super.onWindowUnmaximize();
  }

  @override
  void onWindowClose() {
    _log.info('window: close');
    super.onWindowClose();
  }

  Future<void> _exit(String reason) async {
    _log.info('ui: exit pressed ($reason)');
    await AppLog.shutdown(reason);
    windowManager.close();
    exit(0);
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
                onPressed: () => _exit('loading app bar')),
          ],
        ),
        error: (_, __) => AppBar(title: const Text('RSS Oversikt'), actions: [
          IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () => _exit('error app bar')),
        ]),
      ),
      body: screenSize.height > 700
          ? ResizableWidget(
              separatorSize: 3,
              isHorizontalSeparator: true,
              percentages: config.percentages,
              onResized: (sizes) {
                _log.finer('ui: divider dragged to ${sizes.first.percentage}');
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
