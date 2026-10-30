import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';

/// Watches whether the window keeps presenting frames after the app changes
/// something the user should see. If no frame arrives within [timeout], it
/// logs a warning and forces one, so a render stall shows up in the log
/// instead of as a silently frozen screen.
class FrameWatch {
  static final _log = Logger('FrameWatch');
  static const timeout = Duration(seconds: 2);
  static DateTime? _lastFrame;
  static bool _started = false;
  static Timer? _check;

  static DateTime? get lastFrame => _lastFrame;

  static void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _log.info('start()');
  }

  static void _onTimings(List<FrameTiming> timings) => _lastFrame = DateTime.now();

  /// Seconds since the last presented frame, for log lines.
  static String sinceLastFrame() {
    final last = _lastFrame;
    if (last == null) return 'no frame yet';
    return 'last frame ${DateTime.now().difference(last).inMilliseconds} ms ago';
  }

  /// Call after a state change that must reach the screen.
  static void noteChange(String reason) {
    if (!_started) return;
    final state = SchedulerBinding.instance.lifecycleState;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) return; // minimized: no frames expected
    // Keep the earliest pending check, so repeated clicks during a stall can't
    // keep pushing the warning out.
    if (_check?.isActive ?? false) return;
    final changedAt = DateTime.now();
    _check = Timer(timeout, () {
      final last = _lastFrame;
      if (last == null || last.isBefore(changedAt)) {
        _log.warning('no frame for ${DateTime.now().difference(last ?? changedAt).inMilliseconds} ms after $reason, lifecycle: ${SchedulerBinding.instance.lifecycleState} - forcing a frame');
        forceFrame('stall after $reason');
      }
    });
  }

  static void forceFrame(String reason) {
    if (!_started) return;
    _log.fine('forceFrame($reason), ${sinceLastFrame()}');
    SchedulerBinding.instance.scheduleForcedFrame();
  }
}
