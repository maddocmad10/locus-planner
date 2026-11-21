#include "windows_toast_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <cstdint>
#include <map>
#include <memory>
#include <set>
#include <string>

#include <windows.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Notifications.h>

namespace {

constexpr wchar_t kAppUserModelId[] = L"LocusPlanner.Desktop";


using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Data::Xml::Dom::XmlDocument;
using winrt::Windows::UI::Notifications::ScheduledToastNotification;
using winrt::Windows::UI::Notifications::ToastNotificationManager;

std::string Utf8(const std::wstring& value);

std::string Utf8(const winrt::hstring& value) {
  return Utf8(std::wstring(value.c_str()));
}

std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), result.data(), size,
                        nullptr, nullptr);
  return result;
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string EscapeXml(const std::string& value) {
  std::string out;
  out.reserve(value.size());
  for (const char c : value) {
    switch (c) {
      case '&': out += "&amp;"; break;
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '"': out += "&quot;"; break;
      case '\'': out += "&apos;"; break;
      default: out += c; break;
    }
  }
  return out;
}

std::string StringArg(const EncodableMap& map, const char* key,
                      const std::string& fallback = {}) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return fallback;
  }
  return std::get<std::string>(it->second);
}

int64_t IntArg(const EncodableMap& map, const char* key, int64_t fallback = 0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (std::holds_alternative<int64_t>(it->second)) {
    return std::get<int64_t>(it->second);
  }
  if (std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  return fallback;
}

winrt::Windows::Foundation::DateTime ToDateTime(int64_t epoch_ms) {
  using namespace std::chrono;
  const auto ticks = milliseconds(epoch_ms);
  return winrt::Windows::Foundation::DateTime{
      duration_cast<std::chrono::duration<int64_t, std::ratio<1, 10000000>>>(
          ticks)};
}

std::wstring BuildToastXml(const std::string& title, const std::string& body,
                           const std::string& launch) {
  return L"<toast activationType=\"protocol\" launch=\"" +
         Wide(EscapeXml(launch)) + L"\"><visual><binding template=\"ToastGeneric\"><text>" +
         Wide(EscapeXml(title)) + L"</text><text>" + Wide(EscapeXml(body)) +
         L"</text></binding></visual></toast>";
}

void Schedule(const EncodableList& items, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    auto notifier = ToastNotificationManager::CreateToastNotifier(kAppUserModelId);
    std::map<std::wstring, ScheduledToastNotification> existing;
    const auto scheduled = notifier.GetScheduledToastNotifications();
    for (uint32_t index = 0; index < scheduled.Size(); ++index) {
      const auto toast = scheduled.GetAt(index);
      existing.emplace(std::wstring(toast.Id().c_str()), toast);
    }
    for (const auto& item : items) {
      if (!std::holds_alternative<EncodableMap>(item)) continue;
      const auto& map = std::get<EncodableMap>(item);
      const auto id = StringArg(map, "id");
      if (id.empty() || id.size() > 16) continue;
      const auto wide_id = Wide(id);
      auto found = existing.find(wide_id);
      if (found != existing.end()) {
        notifier.RemoveFromSchedule(found->second);
      }
      const auto fire_at = IntArg(map, "fireAtEpochMs");
      if (fire_at <= 0) continue;
      const auto title = StringArg(map, "title", "Locus reminder");
      const auto body = StringArg(map, "body");
      const auto launch = StringArg(map, "launchUri", "locus://open");
      XmlDocument xml;
      xml.LoadXml(winrt::hstring(BuildToastXml(title, body, launch)));
      ScheduledToastNotification toast(xml, ToDateTime(fire_at));
      toast.Id(winrt::hstring(Wide(id)));
      notifier.AddToSchedule(toast);
    }
    result->Success(EncodableValue(true));
  } catch (const winrt::hresult_error& error) {
    result->Error("toast_error", Utf8(error.message()));
  } catch (...) {
    result->Error("toast_error", "Could not schedule Windows toasts.");
  }
}

void CancelAllExcept(const EncodableList& keep,
                     std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    std::set<std::wstring> keep_ids;
    for (const auto& item : keep) {
      if (std::holds_alternative<std::string>(item)) {
        keep_ids.insert(Wide(std::get<std::string>(item)));
      }
    }
    auto notifier = ToastNotificationManager::CreateToastNotifier(kAppUserModelId);
    const auto scheduled = notifier.GetScheduledToastNotifications();
    for (uint32_t index = 0; index < scheduled.Size(); ++index) {
      const auto toast = scheduled.GetAt(index);
      if (!keep_ids.empty() && keep_ids.count(std::wstring(toast.Id().c_str())) > 0) continue;
      notifier.RemoveFromSchedule(toast);
    }
    result->Success(EncodableValue(true));
  } catch (const winrt::hresult_error& error) {
    result->Error("toast_error", Utf8(error.message()));
  } catch (...) {
    result->Error("toast_error", "Could not cancel Windows toasts.");
  }
}

}  // namespace



void RegisterWindowsToastChannel(flutter::BinaryMessenger* messenger) {
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "locus/windows_toasts",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "schedule") {
          if (!call.arguments() ||
              !std::holds_alternative<EncodableList>(*call.arguments())) {
            result->Error("bad_args", "schedule expects a list");
            return;
          }
          Schedule(std::get<EncodableList>(*call.arguments()),
                   std::move(result));
          return;
        }
        if (call.method_name() == "cancelAllExcept") {
          if (!call.arguments() ||
              !std::holds_alternative<EncodableList>(*call.arguments())) {
            result->Error("bad_args", "cancelAllExcept expects a list");
            return;
          }
          CancelAllExcept(std::get<EncodableList>(*call.arguments()),
                          std::move(result));
          return;
        }
        if (call.method_name() == "listScheduled") {
          try {
            auto notifier =
                ToastNotificationManager::CreateToastNotifier(kAppUserModelId);
            EncodableList ids;
            const auto scheduled = notifier.GetScheduledToastNotifications();
            for (uint32_t index = 0; index < scheduled.Size(); ++index) {
              ids.push_back(EncodableValue(Utf8(scheduled.GetAt(index).Id())));
            }
            result->Success(EncodableValue(ids));
          } catch (...) {
            result->Success(EncodableValue(EncodableList{}));
          }
          return;
        }
        if (call.method_name() == "setBadge") {
          // Taskbar overlay icon is deferred; the Dart side treats false as
          // "badge unavailable" and keeps working.
          result->Success(EncodableValue(false));
          return;
        }
        result->NotImplemented();
      });
}
