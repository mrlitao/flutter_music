#include "flutter_window.h"

#include <windows.h>
#include <mmsystem.h>
#include <shobjidl.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(count, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      &wide[0], count);
  return wide;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int count = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                  static_cast<int>(wide.size()), nullptr, 0,
                                  nullptr, nullptr);
  if (count <= 0) return std::string();
  std::string utf8(count, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      &utf8[0], count, nullptr, nullptr);
  return utf8;
}

std::wstring MciQuery(const std::wstring& cmd) {
  wchar_t buf[256] = {0};
  if (mciSendStringW(cmd.c_str(), buf, 255, nullptr) == 0) {
    return std::wstring(buf);
  }
  return L"";
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterAuraMusicChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterAuraMusicChannel() {
  aura_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.auramusic/native_bridge",
          &flutter::StandardMethodCodec::GetInstance());

  aura_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();

        if (method == "play") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGS", "Expected map arguments");
            return;
          }
          std::string path_utf8;
          int pos_ms = 0;
          double volume = 0.8;

          auto path_it = args->find(flutter::EncodableValue("path"));
          if (path_it != args->end() &&
              std::holds_alternative<std::string>(path_it->second)) {
            path_utf8 = std::get<std::string>(path_it->second);
          }
          auto pos_it = args->find(flutter::EncodableValue("positionMs"));
          if (pos_it != args->end() &&
              std::holds_alternative<int32_t>(pos_it->second)) {
            pos_ms = std::get<int32_t>(pos_it->second);
          }
          auto vol_it = args->find(flutter::EncodableValue("volume"));
          if (vol_it != args->end() &&
              std::holds_alternative<double>(vol_it->second)) {
            volume = std::get<double>(vol_it->second);
          }

          std::wstring wide_path = Utf8ToWide(path_utf8);
          if (wide_path != current_opened_path_) {
            mciSendStringW(L"close auraplayer", nullptr, 0, nullptr);
            std::wstring open_cmd =
                L"open \"" + wide_path + L"\" alias auraplayer";
            if (mciSendStringW(open_cmd.c_str(), nullptr, 0, nullptr) != 0) {
              // Fallback with mpegvideo type for broad codec support
              open_cmd = L"open \"" + wide_path +
                         L"\" type mpegvideo alias auraplayer";
              mciSendStringW(open_cmd.c_str(), nullptr, 0, nullptr);
            }
            mciSendStringW(L"set auraplayer time format milliseconds", nullptr,
                           0, nullptr);
            current_opened_path_ = wide_path;
          }

          int vol_mci = static_cast<int>(volume * 1000.0);
          if (vol_mci < 0) vol_mci = 0;
          if (vol_mci > 1000) vol_mci = 1000;
          std::wstring vol_cmd = L"setaudio auraplayer volume to " +
                                 std::to_wstring(vol_mci);
          mciSendStringW(vol_cmd.c_str(), nullptr, 0, nullptr);

          std::wstring play_cmd =
              L"play auraplayer from " + std::to_wstring(pos_ms);
          mciSendStringW(play_cmd.c_str(), nullptr, 0, nullptr);

          std::wstring len_str = MciQuery(L"status auraplayer length");
          int duration_ms = 0;
          if (!len_str.empty()) {
            duration_ms = _wtoi(len_str.c_str());
          }

          flutter::EncodableMap res;
          res[flutter::EncodableValue("durationMs")] =
              flutter::EncodableValue(duration_ms);
          result->Success(flutter::EncodableValue(res));
          return;
        }

        if (method == "pause") {
          mciSendStringW(L"pause auraplayer", nullptr, 0, nullptr);
          result->Success();
          return;
        }

        if (method == "stop") {
          mciSendStringW(L"close auraplayer", nullptr, 0, nullptr);
          current_opened_path_.clear();
          result->Success();
          return;
        }

        if (method == "seek") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          int pos_ms = 0;
          if (args) {
            auto it = args->find(flutter::EncodableValue("positionMs"));
            if (it != args->end() &&
                std::holds_alternative<int32_t>(it->second)) {
              pos_ms = std::get<int32_t>(it->second);
            }
          }
          std::wstring mode = MciQuery(L"status auraplayer mode");
          if (mode == L"playing") {
            std::wstring cmd =
                L"play auraplayer from " + std::to_wstring(pos_ms);
            mciSendStringW(cmd.c_str(), nullptr, 0, nullptr);
          } else {
            std::wstring cmd =
                L"seek auraplayer to " + std::to_wstring(pos_ms);
            mciSendStringW(cmd.c_str(), nullptr, 0, nullptr);
          }
          result->Success();
          return;
        }

        if (method == "setVolume") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          double volume = 0.8;
          if (args) {
            auto it = args->find(flutter::EncodableValue("volume"));
            if (it != args->end() &&
                std::holds_alternative<double>(it->second)) {
              volume = std::get<double>(it->second);
            }
          }
          int vol_mci = static_cast<int>(volume * 1000.0);
          std::wstring vol_cmd = L"setaudio auraplayer volume to " +
                                 std::to_wstring(vol_mci);
          mciSendStringW(vol_cmd.c_str(), nullptr, 0, nullptr);
          result->Success();
          return;
        }

        if (method == "getPosition") {
          std::wstring pos_str = MciQuery(L"status auraplayer position");
          std::wstring len_str = MciQuery(L"status auraplayer length");
          int pos_ms = -1;
          int len_ms = -1;
          if (!pos_str.empty()) pos_ms = _wtoi(pos_str.c_str());
          if (!len_str.empty()) len_ms = _wtoi(len_str.c_str());
          flutter::EncodableMap res;
          res[flutter::EncodableValue("positionMs")] =
              flutter::EncodableValue(pos_ms);
          res[flutter::EncodableValue("durationMs")] =
              flutter::EncodableValue(len_ms);
          result->Success(flutter::EncodableValue(res));
          return;
        }

        if (method == "pickFolder") {
          IFileOpenDialog* pfd = nullptr;
          std::string selected;
          if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                         CLSCTX_INPROC_SERVER,
                                         IID_PPV_ARGS(&pfd)))) {
            DWORD options = 0;
            if (SUCCEEDED(pfd->GetOptions(&options))) {
              pfd->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
            }
            if (SUCCEEDED(pfd->Show(GetHandle()))) {
              IShellItem* psi = nullptr;
              if (SUCCEEDED(pfd->GetResult(&psi))) {
                PWSTR pszPath = nullptr;
                if (SUCCEEDED(
                        psi->GetDisplayName(SIGDN_FILESYSPATH, &pszPath))) {
                  selected = WideToUtf8(pszPath);
                  CoTaskMemFree(pszPath);
                }
                psi->Release();
              }
            }
            pfd->Release();
          }
          if (selected.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(selected));
          }
          return;
        }

        if (method == "pickAudioFiles") {
          IFileOpenDialog* pfd = nullptr;
          flutter::EncodableList files;
          if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                         CLSCTX_INPROC_SERVER,
                                         IID_PPV_ARGS(&pfd)))) {
            COMDLG_FILTERSPEC rgSpec[] = {
                {L"Audio Files (*.mp3;*.flac;*.wav;*.m4a;*.aac;*.ogg;*.wma)",
                 L"*.mp3;*.flac;*.wav;*.m4a;*.aac;*.ogg;*.wma"},
                {L"All Files (*.*)", L"*.*"},
            };
            pfd->SetFileTypes(ARRAYSIZE(rgSpec), rgSpec);
            DWORD options = 0;
            if (SUCCEEDED(pfd->GetOptions(&options))) {
              pfd->SetOptions(options | FOS_ALLOWMULTISELECT |
                              FOS_FORCEFILESYSTEM);
            }
            if (SUCCEEDED(pfd->Show(GetHandle()))) {
              IShellItemArray* psia = nullptr;
              if (SUCCEEDED(pfd->GetResults(&psia))) {
                DWORD count = 0;
                psia->GetCount(&count);
                for (DWORD i = 0; i < count; ++i) {
                  IShellItem* psi = nullptr;
                  if (SUCCEEDED(psia->GetItemAt(i, &psi))) {
                    PWSTR pszPath = nullptr;
                    if (SUCCEEDED(psi->GetDisplayName(SIGDN_FILESYSPATH,
                                                      &pszPath))) {
                      files.push_back(
                          flutter::EncodableValue(WideToUtf8(pszPath)));
                      CoTaskMemFree(pszPath);
                    }
                    psi->Release();
                  }
                }
                psia->Release();
              }
            }
            pfd->Release();
          }
          result->Success(flutter::EncodableValue(files));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
  mciSendStringW(L"close auraplayer", nullptr, 0, nullptr);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
