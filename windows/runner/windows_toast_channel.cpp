#include "windows_toast_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <cstdint>
#include <iterator>
#include <map>
#include <memory>
#include <set>
#include <string>

#include <windows.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Notifications.h>

namespace {

constexpr wchar_t kAppUserModelId[] = L"LocusPlanner.Desktop";
HWND g_window = nullptr;

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

// Windows DateTime counts 100 ns ticks since 1601-01-01, while Dart sends
// signed milliseconds since 1970-01-01. Anchor at the Unix epoch explicitly so
// an absolute instant is preserved across the channel.
constexpr int64_t kMinEpochMs = 0;                    // 1970-01-01T00:00:00Z
constexpr int64_t kMaxEpochMs = 253402300799999;      // 9999-12-31T23:59:59.999Z

bool IsSupportedEpochMs(int64_t epoch_ms) {
  return epoch_ms >= kMinEpochMs && epoch_ms <= kMaxEpochMs;
}

winrt::Windows::Foundation::DateTime ToDateTime(int64_t epoch_ms) {
  using namespace std::chrono;
  return winrt::clock::from_time_t(0) + milliseconds{epoch_ms};
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
    bool skipped_invalid = false;
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
      // A malformed instant must not be converted; schedule the valid entries
      // and report the batch as degraded rather than throwing them all away.
      if (!IsSupportedEpochMs(fire_at)) {
        skipped_invalid = true;
        continue;
      }
      const auto title = StringArg(map, "title", "Locus reminder");
      const auto body = StringArg(map, "body");
      const auto launch = StringArg(map, "launchUri", "locus://open");
      XmlDocument xml;
      xml.LoadXml(winrt::hstring(BuildToastXml(title, body, launch)));
      ScheduledToastNotification toast(xml, ToDateTime(fire_at));
      toast.Id(winrt::hstring(Wide(id)));
      notifier.AddToSchedule(toast);
    }
    result->Success(EncodableValue(!skipped_invalid));
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

HICON g_badge_icon = nullptr;
int g_badge_count = 0;

HICON CreateBadgeIcon(int count) {
  HDC screen = ::GetDC(nullptr);
  if (screen == nullptr) return nullptr;
  HDC color = ::CreateCompatibleDC(screen);
  HBITMAP bitmap = ::CreateCompatibleBitmap(screen, 16, 16);
  if (color == nullptr || bitmap == nullptr) {
    if (bitmap != nullptr) ::DeleteObject(bitmap);
    if (color != nullptr) ::DeleteDC(color);
    ::ReleaseDC(nullptr, screen);
    return nullptr;
  }
  HGDIOBJ old_bitmap = ::SelectObject(color, bitmap);
  RECT rect{0, 0, 16, 16};
  HBRUSH brush = ::CreateSolidBrush(RGB(198, 40, 40));
  ::FillRect(color, &rect, brush);
  ::DeleteObject(brush);
  ::SetBkMode(color, TRANSPARENT);
  ::SetTextColor(color, RGB(255, 255, 255));
  HFONT font = ::CreateFontW(12, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HGDIOBJ old_font = ::SelectObject(color, font);
  wchar_t text[8];
  ::swprintf_s(text, L"%d", count > 99 ? 99 : count);
  ::DrawTextW(color, text, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  ::SelectObject(color, old_font);
  ::DeleteObject(font);
  ::SelectObject(color, old_bitmap);
  HBITMAP mask = ::CreateBitmap(16, 16, 1, 1, nullptr);
  ICONINFO info{};
  info.fIcon = TRUE;
  info.hbmMask = mask;
  info.hbmColor = bitmap;
  HICON icon = ::CreateIconIndirect(&info);
  ::DeleteObject(mask);
  ::DeleteObject(bitmap);
  ::DeleteDC(color);
  ::ReleaseDC(nullptr, screen);
  return icon;
}

bool ApplyBadge(int count) {
  if (g_window == nullptr) return false;
  ITaskbarList3* taskbar = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&taskbar))) ||
      taskbar == nullptr) {
    return false;
  }
  taskbar->HrInit();
  HICON icon = count > 0 ? CreateBadgeIcon(count) : nullptr;
  const HRESULT hr =
      taskbar->SetOverlayIcon(g_window, icon, count > 0 ? L"Tasks due" : L"");
  taskbar->Release();
  if (g_badge_icon != nullptr) ::DestroyIcon(g_badge_icon);
  g_badge_icon = icon;
  return SUCCEEDED(hr);
}

void SetBadge(int count,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  g_badge_count = count;
  result->Success(EncodableValue(ApplyBadge(count)));
}

std::wstring ExecutablePath() {
  wchar_t buffer[MAX_PATH * 4];
  const DWORD length =
      ::GetModuleFileNameW(nullptr, buffer, static_cast<DWORD>(std::size(buffer)));
  return std::wstring(buffer, length);
}

bool CreateJumpLink(const std::wstring& directory, const std::string& id,
                    const std::wstring& title, const std::wstring& arguments,
                    const std::wstring& description, IShellItem** item) {
  const std::wstring link_path = directory + L"\\" + Wide(id) + L".lnk";
  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&link))) ||
      link == nullptr) {
    return false;
  }
  bool ok = false;
  IPropertyStore* store = nullptr;
  IPersistFile* file = nullptr;
  do {
    link->SetPath(ExecutablePath().c_str());
    link->SetArguments(arguments.c_str());
    if (!description.empty()) link->SetDescription(description.c_str());
    if (FAILED(link->QueryInterface(IID_PPV_ARGS(&store))) ||
        store == nullptr) {
      break;
    }
    PROPVARIANT value;
    ::PropVariantInit(&value);
    if (SUCCEEDED(::InitPropVariantFromString(title.c_str(), &value))) {
      store->SetValue(PKEY_Title, value);
      ::PropVariantClear(&value);
    }
    ::PropVariantInit(&value);
    if (SUCCEEDED(
            ::InitPropVariantFromString(kAppUserModelId, &value))) {
      store->SetValue(PKEY_AppUserModel_ID, value);
      ::PropVariantClear(&value);
    }
    store->Commit();
    if (FAILED(link->QueryInterface(IID_PPV_ARGS(&file))) || file == nullptr) {
      break;
    }
    if (FAILED(file->Save(link_path.c_str(), TRUE))) break;
    if (FAILED(::SHCreateItemFromParsingName(link_path.c_str(), nullptr,
                                             IID_PPV_ARGS(item))) ||
        *item == nullptr) {
      break;
    }
    ok = true;
  } while (false);
  if (file != nullptr) file->Release();
  if (store != nullptr) store->Release();
  link->Release();
  return ok;
}

void UpdateJumpList(const EncodableList& items,
                    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  PWSTR local_app_data = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE,
                                    nullptr, &local_app_data)) ||
      local_app_data == nullptr) {
    result->Success(EncodableValue(false));
    return;
  }
  std::wstring directory(local_app_data);
  ::CoTaskMemFree(local_app_data);
  directory += L"\\Locus\\JumpList";
  ::SHCreateDirectoryExW(nullptr, directory.c_str(), nullptr);

  ICustomDestinationList* list = nullptr;
  IObjectCollection* collection = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_DestinationList, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list))) ||
      list == nullptr) {
    result->Success(EncodableValue(false));
    return;
  }
  if (FAILED(::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&collection))) ||
      collection == nullptr) {
    list->Release();
    result->Success(EncodableValue(false));
    return;
  }
  UINT removed = 0;
  IObjectArray* removed_items = nullptr;
  if (FAILED(list->BeginList(&removed, IID_PPV_ARGS(&removed_items)))) {
    if (removed_items != nullptr) removed_items->Release();
    collection->Release();
    list->Release();
    result->Success(EncodableValue(false));
    return;
  }
  if (removed_items != nullptr) removed_items->Release();

  for (const auto& item : items) {
    if (!std::holds_alternative<EncodableMap>(item)) continue;
    const auto& map = std::get<EncodableMap>(item);
    const auto id = StringArg(map, "id");
    if (id.empty()) continue;
    IShellItem* shell_item = nullptr;
    if (CreateJumpLink(directory, id, Wide(StringArg(map, "title")),
                       Wide(StringArg(map, "arguments")),
                       Wide(StringArg(map, "description")), &shell_item)) {
      collection->AddObject(shell_item);
      shell_item->Release();
    }
  }
  const HRESULT added = list->AddUserTasks(collection);
  const HRESULT committed = SUCCEEDED(added) ? list->CommitList() : added;
  collection->Release();
  list->Release();
  result->Success(EncodableValue(SUCCEEDED(committed)));
}

}  // namespace

void SetWindowsToastWindow(HWND window) { g_window = window; }

void ReapplyWindowsBadge() {
  if (g_badge_count > 0) ApplyBadge(g_badge_count);
}



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
          if (!call.arguments() ||
              !std::holds_alternative<int64_t>(*call.arguments())) {
            result->Success(EncodableValue(false));
            return;
          }
          SetBadge(static_cast<int>(std::get<int64_t>(*call.arguments())),
                   std::move(result));
          return;
        }
        if (call.method_name() == "updateJumpList") {
          if (!call.arguments() ||
              !std::holds_alternative<EncodableList>(*call.arguments())) {
            result->Success(EncodableValue(false));
            return;
          }
          UpdateJumpList(std::get<EncodableList>(*call.arguments()),
                         std::move(result));
          return;
        }
        result->NotImplemented();
      });
}
