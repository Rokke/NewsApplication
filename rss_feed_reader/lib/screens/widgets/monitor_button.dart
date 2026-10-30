import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_feed_reader/models/rss_tree.dart';
import 'package:rss_feed_reader/utils/ui_log.dart';

class MonitorButton extends ConsumerWidget {
  const MonitorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(monitoringRunning.notifier).state;
    return IconButton(
      icon: Icon(running ? Icons.pause : Icons.play_arrow),
      onPressed: () {
        logUi('monitor ${running ? 'stop' : 'start'} pressed');
        if (!running) {
          ref.read(rssProvider).startMonitoring();
        } else {
          ref.read(rssProvider).stopMonitoring();
        }
      },
    );
  }
}
