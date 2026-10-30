import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/utils/frame_watch.dart';

/// Display on/off, monitor changes, session lock/unlock and suspend/resume,
/// reported by the Windows runner (`windows/runner/display_watch.cpp`). The
/// runner already forces a redraw and nudges the window on wake; here it's
/// logged next to the frame timings, and the frame watch checks that frames
/// really come back afterwards.
class PowerEvents {
  static final _log = Logger('PowerEvents');
  static const _channel = MethodChannel('rss_feed_reader/power');
  static const _wakeEvents = ['display on', 'display change', 'session unlock', 'resume'];

  static Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final event = call.arguments as String? ?? '?';
      _log.info('power: $event, ${FrameWatch.sinceLastFrame()}');
      if (_wakeEvents.any(event.startsWith)) {
        FrameWatch.forceFrame(event);
        FrameWatch.noteChange(event);
      }
    });
    try {
      _log.info('start: ${await _channel.invokeMethod<String>('monitors')}');
    } catch (err, stack) {
      _log.warning('start()-monitors not available', err, stack);
    }
  }
}
