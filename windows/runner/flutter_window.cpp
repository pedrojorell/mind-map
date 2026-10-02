#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include <flutter_windows.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Onde a posição da janela fica guardada (HKEY_CURRENT_USER).
constexpr wchar_t kWindowRegistryKey[] = L"Software\\MapLong\\Window";
constexpr wchar_t kPlacementValue[] = L"Placement";

// Tamanho mínimo da janela (em pixels lógicos, a 100% de escala).
constexpr int kMinWidth = 900;
constexpr int kMinHeight = 600;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::RestorePlacement() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  WINDOWPLACEMENT placement = {};
  DWORD size = sizeof(placement);
  if (::RegGetValueW(HKEY_CURRENT_USER, kWindowRegistryKey, kPlacementValue,
                     RRF_RT_REG_BINARY, nullptr, &placement,
                     &size) != ERROR_SUCCESS ||
      size != sizeof(placement) || placement.length != sizeof(placement)) {
    return;
  }
  // O monitor onde a janela estava pode ter sido desconectado.
  if (::MonitorFromRect(&placement.rcNormalPosition,
                        MONITOR_DEFAULTTONULL) == nullptr) {
    return;
  }
  const bool maximized = placement.showCmd == SW_SHOWMAXIMIZED;
  // Só posiciona agora; a janela aparece quando o primeiro quadro estiver
  // pronto (evita um piscar branco).
  placement.showCmd = SW_HIDE;
  placement.flags = 0;
  ::SetWindowPlacement(hwnd, &placement);
  SetInitialShowCommand(maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

void FlutterWindow::SavePlacement() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(hwnd, &placement)) {
    return;
  }
  // Minimizada ao fechar: reabre como estava antes de minimizar.
  if (placement.showCmd == SW_SHOWMINIMIZED ||
      placement.showCmd == SW_MINIMIZE) {
    placement.showCmd = (placement.flags & WPF_RESTORETOMAXIMIZED)
                            ? SW_SHOWMAXIMIZED
                            : SW_SHOWNORMAL;
  }
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kWindowRegistryKey, kPlacementValue,
                    REG_BINARY, &placement, sizeof(placement));
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  open_files_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "maplong/open_files",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  open_files_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = FlutterDesktopGetDpiForHWND(hwnd);
      info->ptMinTrackSize.x = ::MulDiv(kMinWidth, dpi, 96);
      info->ptMinTrackSize.y = ::MulDiv(kMinHeight, dpi, 96);
      return 0;
    }
    case WM_CLOSE:
      SavePlacement();
      break;
    case WM_COPYDATA: {
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == kOpenFilesCopyDataId &&
          open_files_channel_) {
        const std::string payload(static_cast<const char*>(data->lpData),
                                  data->cbData);
        flutter::EncodableList files;
        size_t start = 0;
        while (start < payload.size()) {
          size_t end = payload.find('\n', start);
          if (end == std::string::npos) {
            end = payload.size();
          }
          if (end > start) {
            files.emplace_back(payload.substr(start, end - start));
          }
          start = end + 1;
        }
        open_files_channel_->InvokeMethod(
            "open", std::make_unique<flutter::EncodableValue>(files));
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
