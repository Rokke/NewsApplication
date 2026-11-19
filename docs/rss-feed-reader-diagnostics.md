# rss_feed_reader: logging and diagnostics

Code: `rss_feed_reader/lib/utils/log_file.dart`, `rss_feed_reader/lib/utils/ui_log.dart`, `rss_feed_reader/lib/utils/frame_watch.dart`, `rss_feed_reader/lib/utils/power_events.dart`, `rss_feed_reader/windows/runner/display_watch.cpp`, `rss_feed_reader/windows/runner/display_watch.h`, `rss_feed_reader/windows/runner/flutter_window.cpp`, `rss_feed_reader/test/utils/log_file_test.dart`

What the desktop app writes down so that a freeze or a fault can be read from
the log afterwards. All of it is started in `main()`
(`rss_feed_reader/lib/main.dart`). The app itself is in
[rss-feed-reader.md](rss-feed-reader.md).

## Log file
- `AppLog.start` (`lib/utils/log_file.dart`) sets `Logger.root.level` (`FINEST`
  in debug builds, `FINE` otherwise) and sends every record to `debugPrint`
  and, on Windows, to a `RotatingLogFile`.
- The file is `rss_feed_reader.log` in `logDirectory`
  (`ApplicationConfiguration`, default `D:\Temp\logs\rss_feed_reader`). At
  `maxBytes` it is rotated while the app runs: `rss_feed_reader.1.log` is the
  previous one, and `maxFiles` counts the current file too. Writes and
  rotations go through one queue.
- A line is `HH:mm:ss,mmm [logger] LEVEL message`, followed by `, ERR: <error>`
  and the stack trace on the next lines when the record has them.
- `_startLogger` in `main.dart` logs the app version and sends
  `FlutterError.onError` and `PlatformDispatcher.instance.onError` to the log.
- `AppLog.shutdown(reason)` logs the reason and closes the file. The exit
  buttons (`CustomAppBarWidget`, and `_exit` in `lib/screens/home.dart`) call
  it before `exit(0)`.
- Classes log through `Logger('<ClassName>')` from `package:logging`.
- The log holds the socket secret: `SocketServerHandler` logs the handshake
  buffer of every connection at `FINE`, and its constructor logs the secret
  without its last three characters.

## User actions
`logUi(action)` (`lib/utils/ui_log.dart`) writes one INFO line per button, menu
or key action, with the time since the last frame. A new button calls it.

## Frame watch
`FrameWatch` (`lib/utils/frame_watch.dart`) records when the last frame was
presented. `noteChange(reason)` is called after a change that must reach the
screen (`FeedListHeader._select`, a new article, a wake event). `timeout`
later, when no frame has come since, it logs a warning and calls `forceFrame`.
Nothing is checked while the app is hidden or paused. `HomeScreen`
(`lib/screens/home.dart`) logs window and lifecycle events with
`sinceLastFrame()` and forces a frame on focus, restore and resume.

## Display and power events
`DisplayWatch` (`windows/runner/display_watch.cpp`) watches session
lock/unlock, display on/off/dimmed, suspend/resume and `WM_DISPLAYCHANGE`.
`FlutterWindow` (`flutter_window.cpp`) owns it and passes it every window
message; the source file is listed in `windows/runner/CMakeLists.txt`. It
talks to `PowerEvents` (`lib/utils/power_events.dart`) over the method channel
`rss_feed_reader/power`:

- runner → Dart: method `event` with one string
- Dart → runner: method `monitors`, answered with a text describing the
  monitors and the window

On a wake event (display on, display change, session unlock, resume) the
runner calls `Refresh`: `ForceRedraw()`, and a 1 px resize and back unless the
window is minimized or maximized. It does so at once and a second time after
`kRefreshDelayMs`. `PowerEvents` logs every event and, for the wake events
(`_wakeEvents`), forces a frame and arms the frame watch. `PowerEvents.start`
runs on Windows only.
