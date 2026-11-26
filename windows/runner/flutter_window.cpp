#include "flutter_window.h"

#include <windows.h>
#include <mfapi.h>
#include <mfplay.h>
#include <mmsystem.h>
#include <shobjidl.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

#pragma warning(disable : 4995)

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

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  ReleaseMediaPlayer();
}

void FlutterWindow::ReleaseMediaPlayer() {
  if (mfp_player_ != nullptr) {
    mfp_player_->Stop();
    mfp_player_->Shutdown();
    mfp_player_->Release();
    mfp_player_ = nullptr;
  }
  current_opened_path_.clear();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  MFStartup(MF_VERSION);

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
          double volume = 0.85;
          double speed = 1.0;

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
          auto spd_it = args->find(flutter::EncodableValue("speed"));
          if (spd_it != args->end() &&
              std::holds_alternative<double>(spd_it->second)) {
            speed = std::get<double>(spd_it->second);
          }

          std::wstring wide_path = Utf8ToWide(path_utf8);
          bool opened_ok = true;
          bool newly_created = false;

          if (wide_path != current_opened_path_ || mfp_player_ == nullptr) {
            ReleaseMediaPlayer();
            // Create Windows Media Foundation player with hWnd = nullptr (audio-only mode
            // for .mp4 video/audio containers, zero video rendering overhead, async workqueue!)
            // fStartPlayback = TRUE automatically starts playback when async media load finishes.
            HRESULT hr = MFPCreateMediaPlayer(
                wide_path.c_str(), TRUE, MFP_OPTION_NONE, nullptr, nullptr,
                &mfp_player_);
            if (SUCCEEDED(hr) && mfp_player_ != nullptr) {
              current_opened_path_ = wide_path;
              newly_created = true;
            } else {
              opened_ok = false;
            }
          }

          int duration_ms = 0;
          if (mfp_player_ != nullptr) {
            float vol_f = static_cast<float>(volume);
            if (vol_f < 0.0f) vol_f = 0.0f;
            if (vol_f > 1.0f) vol_f = 1.0f;
            mfp_player_->SetVolume(vol_f);

            if (!newly_created) {
              float rate_f = static_cast<float>(speed);
              if (rate_f >= 0.5f && rate_f <= 2.0f) {
                mfp_player_->SetRate(rate_f);
              }
              PROPVARIANT pos_var;
              PropVariantInit(&pos_var);
              pos_var.vt = VT_I8;
              pos_var.hVal.QuadPart = static_cast<LONGLONG>(pos_ms) * 10000LL;
              mfp_player_->SetPosition(MFP_POSITIONTYPE_100NS, &pos_var);
              PropVariantClear(&pos_var);
              mfp_player_->Play();
            }

            PROPVARIANT dur_var;
            PropVariantInit(&dur_var);
            if (SUCCEEDED(
                    mfp_player_->GetDuration(MFP_POSITIONTYPE_100NS, &dur_var))) {
              if (dur_var.vt == VT_I8 || dur_var.vt == VT_UI8) {
                duration_ms =
                    static_cast<int>(dur_var.hVal.QuadPart / 10000LL);
              }
            }
            PropVariantClear(&dur_var);
          }

          flutter::EncodableMap res;
          res[flutter::EncodableValue("durationMs")] =
              flutter::EncodableValue(duration_ms);
          res[flutter::EncodableValue("ok")] =
              flutter::EncodableValue(opened_ok);
          result->Success(flutter::EncodableValue(res));
          return;
        }

        if (method == "pause") {
          if (mfp_player_ != nullptr) {
            mfp_player_->Pause();
          }
          result->Success();
          return;
        }

        if (method == "stop") {
          ReleaseMediaPlayer();
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
          if (mfp_player_ != nullptr) {
            PROPVARIANT pos_var;
            PropVariantInit(&pos_var);
            pos_var.vt = VT_I8;
            pos_var.hVal.QuadPart = static_cast<LONGLONG>(pos_ms) * 10000LL;
            mfp_player_->SetPosition(MFP_POSITIONTYPE_100NS, &pos_var);
            PropVariantClear(&pos_var);
          }
          result->Success();
          return;
        }

        if (method == "setVolume") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          double volume = 0.85;
          if (args) {
            auto it = args->find(flutter::EncodableValue("volume"));
            if (it != args->end() &&
                std::holds_alternative<double>(it->second)) {
              volume = std::get<double>(it->second);
            }
          }
          if (mfp_player_ != nullptr) {
            float vol_f = static_cast<float>(volume);
            if (vol_f < 0.0f) vol_f = 0.0f;
            if (vol_f > 1.0f) vol_f = 1.0f;
            mfp_player_->SetVolume(vol_f);
          }
          result->Success();
          return;
        }

        if (method == "setSpeed") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          double speed = 1.0;
          if (args) {
            auto it = args->find(flutter::EncodableValue("speed"));
            if (it != args->end() &&
                std::holds_alternative<double>(it->second)) {
              speed = std::get<double>(it->second);
            }
          }
          if (mfp_player_ != nullptr) {
            mfp_player_->SetRate(static_cast<float>(speed));
          }
          result->Success();
          return;
        }

        if (method == "getPosition") {
          int pos_ms = -1;
          int len_ms = -1;
          if (mfp_player_ != nullptr) {
            PROPVARIANT pos_var;
            PropVariantInit(&pos_var);
            if (SUCCEEDED(
                    mfp_player_->GetPosition(MFP_POSITIONTYPE_100NS, &pos_var))) {
              if (pos_var.vt == VT_I8 || pos_var.vt == VT_UI8) {
                pos_ms = static_cast<int>(pos_var.hVal.QuadPart / 10000LL);
              }
            }
            PropVariantClear(&pos_var);

            PROPVARIANT dur_var;
            PropVariantInit(&dur_var);
            if (SUCCEEDED(
                    mfp_player_->GetDuration(MFP_POSITIONTYPE_100NS, &dur_var))) {
              if (dur_var.vt == VT_I8 || dur_var.vt == VT_UI8) {
                len_ms = static_cast<int>(dur_var.hVal.QuadPart / 10000LL);
              }
            }
            PropVariantClear(&dur_var);
          }
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
                {L"Audio & MP4 Files (*.mp3;*.mp4;*.flac;*.wav;*.m4a;*.aac;*.ogg;*.wma)",
                 L"*.mp3;*.mp4;*.flac;*.wav;*.m4a;*.aac;*.ogg;*.wma"},
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
  ReleaseMediaPlayer();
  MFShutdown();
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
