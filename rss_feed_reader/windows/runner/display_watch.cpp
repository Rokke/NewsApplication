#include "display_watch.h"

#include <flutter/standard_method_codec.h>
#include <wtsapi32.h>

// Linked here as well as in CMake, so the file can be dropped into another
// runner as is.
#pragma comment(lib, "wtsapi32.lib")

#include <vector>

namespace {

// Timer for the second, delayed refresh: a monitor that reconnects can report
// "on" before its output is usable again.
constexpr UINT_PTR kRefreshTimerId = 0x5157;
constexpr UINT kRefreshDelayMs = 2000;

std::string RectText(const RECT& r) {
  return std::to_string(r.left) + "," + std::to_string(r.top) + " " +
         std::to_string(r.right - r.left) + "x" +
         std::to_string(r.bottom - r.top);
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  reinterpret_cast<std::vector<HMONITOR>*>(data)->push_back(monitor);
  return TRUE;
}

}  // namespace

DisplayWatch::DisplayWatch(HWND window,
                           flutter::FlutterViewController* controller)
    : window_(window), controller_(controller) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      controller_->engine()->messenger(), "rss_feed_reader/power",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "monitors") {
          result->Success(flutter::EncodableValue(DescribeMonitors()));
        } else {
          result->NotImplemented();
        }
      });
  WTSRegisterSessionNotification(window_, NOTIFY_FOR_THIS_SESSION);
  display_notify_ = RegisterPowerSettingNotification(
      window_, &GUID_CONSOLE_DISPLAY_STATE, DEVICE_NOTIFY_WINDOW_HANDLE);
}

DisplayWatch::~DisplayWatch() {
  KillTimer(window_, kRefreshTimerId);
  if (display_notify_) UnregisterPowerSettingNotification(display_notify_);
  WTSUnRegisterSessionNotification(window_);
}

void DisplayWatch::Report(const std::string& event) {
  // Messages sent before Dart set its handler are dropped, which is fine.
  channel_->InvokeMethod("event",
                         std::make_unique<flutter::EncodableValue>(event));
}

std::string DisplayWatch::DescribeMonitors() const {
  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  const HMONITOR current = MonitorFromWindow(window_, MONITOR_DEFAULTTONULL);
  std::string text = "monitors=" + std::to_string(monitors.size());
  for (size_t i = 0; i < monitors.size(); i++) {
    MONITORINFO info{sizeof(info)};
    if (!GetMonitorInfo(monitors[i], &info)) continue;
    text += " [" + std::to_string(i) + ": " + RectText(info.rcMonitor);
    if (info.dwFlags & MONITORINFOF_PRIMARY) text += " primary";
    if (monitors[i] == current) text += " window";
    text += "]";
  }
  RECT rect;
  if (GetWindowRect(window_, &rect)) text += " window=" + RectText(rect);
  if (current == nullptr) text += " window-on-no-monitor";
  return text;
}

void DisplayWatch::Refresh(const std::string& reason) {
  controller_->ForceRedraw();
  RECT rect;
  if (!IsIconic(window_) && GetWindowRect(window_, &rect)) {
    const int width = rect.right - rect.left;
    const int height = rect.bottom - rect.top;
    const UINT flags =
        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
    SetWindowPos(window_, nullptr, 0, 0, width + 1, height, flags);
    SetWindowPos(window_, nullptr, 0, 0, width, height, flags);
  }
  Report("refreshed after " + reason + ", " + DescribeMonitors());
}

bool DisplayWatch::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  std::string wake;
  switch (message) {
    case WM_TIMER:
      if (wparam != kRefreshTimerId) return false;
      KillTimer(window_, kRefreshTimerId);
      Refresh(pending_reason_ + " (delayed)");
      return true;
    case WM_WTSSESSION_CHANGE:
      if (wparam == WTS_SESSION_LOCK) {
        Report("session lock");
      } else if (wparam == WTS_SESSION_UNLOCK) {
        wake = "session unlock";
      } else {
        Report("session change " + std::to_string(wparam));
      }
      break;
    case WM_POWERBROADCAST:
      if (wparam == PBT_POWERSETTINGCHANGE) {
        auto setting = reinterpret_cast<POWERBROADCAST_SETTING*>(lparam);
        if (setting &&
            IsEqualGUID(setting->PowerSetting, GUID_CONSOLE_DISPLAY_STATE) &&
            setting->DataLength >= sizeof(DWORD)) {
          // 0 = off, 1 = on, 2 = dimmed.
          const DWORD state = *reinterpret_cast<DWORD*>(setting->Data);
          if (state == 1) {
            wake = "display on";
          } else {
            Report(state == 0 ? "display off" : "display dimmed");
          }
        }
      } else if (wparam == PBT_APMSUSPEND) {
        Report("suspend");
      } else if (wparam == PBT_APMRESUMEAUTOMATIC ||
                 wparam == PBT_APMRESUMESUSPEND) {
        wake = wparam == PBT_APMRESUMEAUTOMATIC ? "resume automatic"
                                                : "resume suspend";
      }
      break;
    case WM_DISPLAYCHANGE:
      // Sent when a monitor is added, removed or changes mode - also when a
      // sleeping monitor drops off the bus and comes back.
      wake = "display change " + std::to_string(LOWORD(lparam)) + "x" +
             std::to_string(HIWORD(lparam));
      break;
  }
  if (!wake.empty()) {
    Report(wake + ", " + DescribeMonitors());
    Refresh(wake);
    pending_reason_ = wake;
    SetTimer(window_, kRefreshTimerId, kRefreshDelayMs, nullptr);
  }
  return false;
}
