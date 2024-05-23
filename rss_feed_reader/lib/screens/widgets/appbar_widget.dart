import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rss_feed_reader/providers/feed_list.dart';
import 'package:rss_feed_reader/providers/server_provider.dart';
import 'package:rss_feed_reader/screens/settings_screen.dart';
import 'package:rss_feed_reader/screens/widgets/details_widget.dart';
import 'package:rss_feed_reader/screens/widgets/monitor_button.dart';
import 'package:rss_feed_reader/utils/misc_functions.dart';
import 'package:window_manager/window_manager.dart';

class CustomAppBarWidget extends ConsumerWidget {
  // static final _log = Logger('CustomAppBarWidget');
  final PackageInfo appVersion;
  const CustomAppBarWidget(this.appVersion, {super.key});
  Future<void> _test(BuildContext context) async {
    debugPrint('_test()');
    try {
      playSound(soundFile: SoundFile.soundNewItem);
      // debugPrint('checkAndUpdateTweet: ${await context.read(providerTweetHeader).checkAndUpdateTweet()}');
    } catch (err) {
      debugPrint('Error: $err');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // debugPrint('test: ${appVersion.appName}-${appVersion.buildNumber}-${appVersion.packageName}-${appVersion.version}');
    final feedProvider = ref.read(providerFeedHeader);
    final socketProvider = ref.read(providerSocketServer);
    return AppBar(
      // automaticallyImplyLeading: Platform.isWindows ? false : true,
      toolbarHeight: Platform.isWindows ? 30 : 56,
      title: Text('RSS Oversikt - ${appVersion.version}${(appVersion.buildNumber.isNotEmpty) ? ".${appVersion.buildNumber}" : ""}'),
      actions: [
        GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) {
              windowManager.startDragging();
            },
            child: const Tooltip(
              message: 'Move window',
              child: Icon(
                Icons.api_rounded,
                size: 20,
                semanticLabel: 'Move window',
              ),
            )),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(), borderRadius: BorderRadius.circular(10), color: Colors.purple[900]),
            child: Row(
              children: [
                ValueListenableBuilder(
                  valueListenable: feedProvider.numberOfArticleNotifier,
                  builder: (context, int amount, _) {
                    final errorReported = ref.read(providerErrorReported.notifier);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(),
                        borderRadius: BorderRadius.circular(6),
                        color: errorReported.state != null
                            ? Colors.red
                            : amount > 0
                                ? Colors.blue
                                : null,
                      ),
                      child: errorReported.state == null
                          ? Text('$amount')
                          : GestureDetector(
                              onTap: () {
                                showSnackbar(context, errorReported.state!);
                                errorReported.state = null;
                              },
                              child: Text(amount.toString()),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: socketProvider.isConnected,
          builder: (BuildContext context, bool? connected, Widget? child) {
            return connected == null
                ? const Icon(Icons.stop)
                : connected == true
                    ? Text('Tilkoblet:\n ${socketProvider.clientIP}')
                    : const Icon(
                        Icons.no_cell,
                        color: Colors.red,
                        size: 12,
                      );
          },
        ),
        const MonitorButton(),
        IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => SettingsScreen())), icon: const Icon(Icons.settings)),
        IconButton(
            color: Colors.red,
            icon: const Icon(
              Icons.exit_to_app,
            ),
            onPressed: () {
              windowManager.close();
              exit(0);
            }),
        if (kDebugMode)
          IconButton(
            icon: const Icon(Icons.hot_tub),
            onPressed: () => _test(context),
          ),
      ],
    );
  }
}
