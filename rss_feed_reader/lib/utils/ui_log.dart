import 'package:logging/logging.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';

final _uiLog = Logger('UI');

/// One INFO line per button, menu or key action, so the log shows the last
/// thing the user did and whether the screen was still drawing at that time.
void logUi(String action) => _uiLog.info('ui: $action, ${FrameWatch.sinceLastFrame()}');
