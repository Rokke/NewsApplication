#ifndef RUNNER_DISPLAY_WATCH_H_
#define RUNNER_DISPLAY_WATCH_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Watches display, monitor, session and power changes for a top-level Flutter
// window, reports them to Dart on the "rss_feed_reader/power" channel
// (method "event", one string argument) and refreshes the window when a
// display comes back: ForceRedraw() plus a 1 px resize and back, once at once
// and once again a little later. A Flutter window on a monitor that slept or
// was disconnected can otherwise keep presenting to a dead output, so the
// screen stays frozen while input still works.
//
// Self-contained: own it from FlutterWindow, create it after the controller,
// pass every top-level message to HandleMessage, and destroy it before the
// controller.
class DisplayWatch {
 public:
  DisplayWatch(HWND window, flutter::FlutterViewController* controller);
  ~DisplayWatch();

  DisplayWatch(const DisplayWatch&) = delete;
  DisplayWatch& operator=(const DisplayWatch&) = delete;

  // Returns true when the message was fully handled (only its own timer).
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void Report(const std::string& event);
  void Refresh(const std::string& reason);
  std::string DescribeMonitors() const;

  HWND window_;
  flutter::FlutterViewController* controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HPOWERNOTIFY display_notify_ = nullptr;
  std::string pending_reason_;
};

#endif  // RUNNER_DISPLAY_WATCH_H_
