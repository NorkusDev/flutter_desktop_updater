#include "desktop_updater_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>
#include <Shlwapi.h>
#include <shellapi.h>

#pragma comment(lib, "Version.lib")
#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "Shell32.lib")

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <variant>
#include <vector>

namespace fs = std::filesystem;

namespace desktop_updater {
namespace {

// ---------- helpers ----------
std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return L"";
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(), -1, nullptr, 0);
  if (size <= 0) return L"";
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(), -1, result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return "";
  std::string result(size - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring CurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return L"";
    if (length < buffer.size() - 1) return std::wstring(buffer.data(), length);
    buffer.resize(buffer.size() * 2);
  }
}

// ---------- PowerShell helpers ----------
std::string PowerShellQuote(const std::wstring& value) {
  std::string escaped = WideToUtf8(value);
  size_t pos = 0;
  while ((pos = escaped.find('\'', pos)) != std::string::npos) {
    escaped.replace(pos, 1, "''");
    pos += 2;
  }
  return "'" + escaped + "'";
}

std::string PowerShellArray(const std::vector<std::wstring>& values) {
  if (values.empty()) return "@()";
  std::string result = "@(";
  for (size_t i = 0; i < values.size(); ++i) {
    if (i > 0) result += ", ";
    result += PowerShellQuote(values[i]);
  }
  result += ")";
  return result;
}

bool WriteUtf8PowerShellScript(const fs::path& script_path, const std::string& script) {
  std::ofstream file(script_path, std::ios::binary | std::ios::trunc);
  if (!file.is_open()) return false;
  const unsigned char bom[] = {0xEF, 0xBB, 0xBF};
  file.write(reinterpret_cast<const char*>(bom), sizeof(bom));
  file << script;
  return file.good();
}

bool StartDetachedPowerShell(const fs::path& script_path, bool asAdmin = false) {
  std::wstring command;
  if (asAdmin) {
    // Gunakan Start-Process untuk elevasi
    command = L"powershell.exe -NoProfile -Command \"Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \\\"" + 
              script_path.wstring() + L"\\\"'\"";
  } else {
    command = L"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
              script_path.wstring() + L"\"";
  }

  std::vector<wchar_t> command_line(command.begin(), command.end());
  command_line.push_back(L'\0');

  STARTUPINFOW si = {sizeof(si)};
  PROCESS_INFORMATION pi = {};
  BOOL started = CreateProcessW(nullptr, command_line.data(), nullptr, nullptr, FALSE,
                                CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
  if (started) {
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
  }
  return started == TRUE;
}

// ---------- File sementara untuk parameter elevasi ----------
struct ElevatedUpdateParams {
  std::wstring staging_path;
  std::vector<std::wstring> removed_files;
};

bool WriteElevatedParams(const fs::path& file_path, const ElevatedUpdateParams& params) {
  std::ofstream out(file_path, std::ios::binary);
  if (!out) return false;
  // Format: [staging_path_length:uint32_t][staging_path:wstring][removed_count:uint32_t][foreach: length+wstring]
  uint32_t len = static_cast<uint32_t>(params.staging_path.size());
  out.write(reinterpret_cast<const char*>(&len), sizeof(len));
  out.write(reinterpret_cast<const char*>(params.staging_path.data()), len * sizeof(wchar_t));
  uint32_t count = static_cast<uint32_t>(params.removed_files.size());
  out.write(reinterpret_cast<const char*>(&count), sizeof(count));
  for (const auto& f : params.removed_files) {
    uint32_t flen = static_cast<uint32_t>(f.size());
    out.write(reinterpret_cast<const char*>(&flen), sizeof(flen));
    out.write(reinterpret_cast<const char*>(f.data()), flen * sizeof(wchar_t));
  }
  return out.good();
}

bool ReadElevatedParams(const fs::path& file_path, ElevatedUpdateParams& params) {
  std::ifstream in(file_path, std::ios::binary);
  if (!in) return false;
  uint32_t len = 0;
  in.read(reinterpret_cast<char*>(&len), sizeof(len));
  if (!in || len == 0) return false;
  params.staging_path.resize(len);
  in.read(reinterpret_cast<char*>(params.staging_path.data()), len * sizeof(wchar_t));
  uint32_t count = 0;
  in.read(reinterpret_cast<char*>(&count), sizeof(count));
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t flen = 0;
    in.read(reinterpret_cast<char*>(&flen), sizeof(flen));
    std::wstring f(flen, L'\0');
    in.read(reinterpret_cast<char*>(f.data()), flen * sizeof(wchar_t));
    params.removed_files.push_back(f);
  }
  return in.good();
}

// ---------- Cek hak akses tulis ----------
bool CanWriteToDirectory(const std::wstring& dir) {
  // Coba buat file temporary untuk test tulis
  std::wstring test_file = dir + L"\\desktop_updater_write_test.tmp";
  HANDLE h = CreateFileW(test_file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    return false;
  }
  CloseHandle(h);
  // Berhasil, file akan terhapus otomatis
  return true;
}

bool IsRunningAsAdmin() {
  BOOL isAdmin = FALSE;
  PSID adminGroup = nullptr;
  SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
  if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                               DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &adminGroup)) {
    if (!CheckTokenMembership(nullptr, adminGroup, &isAdmin)) {
      isAdmin = FALSE;
    }
    FreeSid(adminGroup);
  }
  return isAdmin == TRUE;
}

bool RequestAdminPrivileges(const std::wstring& args) {
  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  HINSTANCE result = ShellExecuteW(nullptr, L"runas", exePath, args.c_str(), nullptr, SW_SHOW);
  return (INT_PTR)result > 32;
}

// ---------- Jadwal install & relaunch (digunakan langsung atau setelah elevasi) ----------
bool ScheduleInstallAndRelaunch(const std::wstring& staging_path,
                                const std::vector<std::wstring>& removed_files,
                                std::string* error) {
  std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    *error = "Unable to resolve executable path.";
    return false;
  }

  fs::path executable(executable_path);
  fs::path target_directory = executable.parent_path();
  if (!staging_path.empty() && !fs::exists(fs::path(staging_path))) {
    *error = "Staged update directory does not exist.";
    return false;
  }

  fs::path script_path = fs::temp_directory_path() /
      (L"desktop_updater_" + std::to_wstring(GetCurrentProcessId()) + L".ps1");

  std::ostringstream script;
  script << "$ErrorActionPreference = 'Stop'\n"
         << "$pidToWait = " << GetCurrentProcessId() << "\n"
         << "$staging = " << PowerShellQuote(staging_path) << "\n"
         << "$target = " << PowerShellQuote(target_directory.wstring()) << "\n"
         << "$exe = " << PowerShellQuote(executable_path) << "\n"
         << "$removed = " << PowerShellArray(removed_files) << "\n"
         << "$skipRelaunch = $env:DESKTOP_UPDATER_SMOKE_SKIP_RELAUNCH\n"
         << "while (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue) {\n"
         << "  Start-Sleep -Milliseconds 500\n"
         << "}\n"
         << "$targetRoot = [IO.Path]::GetFullPath($target).TrimEnd('\\\\')\n"
         << "$targetRootWithSlash = $targetRoot + '\\'\n"
         << "foreach ($relative in $removed) {\n"
         << "  if ([string]::IsNullOrWhiteSpace($relative)) { continue }\n"
         << "  $candidate = [IO.Path]::GetFullPath((Join-Path $target $relative))\n"
         << "  if (($candidate.Equals($targetRoot, [StringComparison]::OrdinalIgnoreCase) -or "
            "$candidate.StartsWith($targetRootWithSlash, [StringComparison]::OrdinalIgnoreCase)) "
            "-and (Test-Path -LiteralPath $candidate)) {\n"
         << "    Remove-Item -LiteralPath $candidate -Recurse -Force\n"
         << "  }\n"
         << "}\n"
         << "if (-not [string]::IsNullOrWhiteSpace($staging)) {\n"
         << "  $deadline = (Get-Date).AddSeconds(90)\n"
         << "  while ($true) {\n"
         << "    try {\n"
         << "      Get-ChildItem -LiteralPath $staging -Force | ForEach-Object {\n"
         << "        Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force\n"
         << "      }\n"
         << "      break\n"
         << "    } catch {\n"
         << "      if ((Get-Date) -gt $deadline) { throw }\n"
         << "      Start-Sleep -Seconds 1\n"
         << "    }\n"
         << "  }\n"
         << "  Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue\n"
         << "}\n"
         << "if ($skipRelaunch -ne '1') {\n"
         << "  Start-Process -FilePath $exe -WorkingDirectory $target\n"
         << "}\n"
         << "Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue\n";

  if (!WriteUtf8PowerShellScript(script_path, script.str())) {
    *error = "Unable to write update helper script.";
    return false;
  }

  // Jika kita sudah admin, jalankan langsung; jika tidak, minta elevasi untuk script (jarang terjadi)
  bool needAdmin = !IsRunningAsAdmin() && !CanWriteToDirectory(target_directory.wstring());
  if (!StartDetachedPowerShell(script_path, needAdmin)) {
    *error = "Unable to start update helper script.";
    return false;
  }

  return true;
}

std::vector<std::wstring> RemovedFilesFromArguments(const flutter::EncodableMap& arguments) {
  std::vector<std::wstring> removed_files;
  auto it = arguments.find(flutter::EncodableValue("removedFiles"));
  if (it == arguments.end()) return removed_files;
  const auto* list = std::get_if<flutter::EncodableList>(&it->second);
  if (!list) return removed_files;
  for (const auto& val : *list) {
    if (const auto* str = std::get_if<std::string>(&val)) {
      removed_files.push_back(Utf8ToWide(*str));
    }
  }
  return removed_files;
}

// ---------- Eksekusi setelah elevasi ----------
void ExecuteElevatedUpdate() {
  // Baca parameter dari file temp
  fs::path params_file = fs::temp_directory_path() / L"desktop_updater_elevated_params.bin";
  ElevatedUpdateParams params;
  if (!ReadElevatedParams(params_file, params)) {
    // Fallback: coba install tanpa staging (restartApp mungkin)
    std::string error;
    if (!ScheduleInstallAndRelaunch(L"", {}, &error)) {
      MessageBoxA(nullptr, error.c_str(), "Update Error", MB_ICONERROR);
    }
    ExitProcess(0);
  }
  // Hapus file parameter
  DeleteFileW(params_file.c_str());

  std::string error;
  if (!ScheduleInstallAndRelaunch(params.staging_path, params.removed_files, &error)) {
    MessageBoxA(nullptr, error.c_str(), "Update Error", MB_ICONERROR);
  }
  ExitProcess(0);
}

}  // namespace

// static
void DesktopUpdaterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  // Deteksi apakah ini proses elevated untuk update
  int argc;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  bool isElevatedUpdate = false;
  if (argv) {
    for (int i = 1; i < argc; ++i) {
      if (wcscmp(argv[i], L"--update-elevated") == 0) {
        isElevatedUpdate = true;
        break;
      }
    }
    LocalFree(argv);
  }

  if (isElevatedUpdate) {
    ExecuteElevatedUpdate();  // tidak kembali
    return;
  }

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "desktop_updater",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DesktopUpdaterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DesktopUpdaterPlugin::DesktopUpdaterPlugin() {}
DesktopUpdaterPlugin::~DesktopUpdaterPlugin() {}

void DesktopUpdaterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "getPlatformVersion") {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) version_stream << "10+";
    else if (IsWindows8OrGreater()) version_stream << "8";
    else if (IsWindows7OrGreater()) version_stream << "7";
    result->Success(flutter::EncodableValue(version_stream.str()));
  }
  else if (method_call.method_name() == "restartApp") {
    std::string error;
    if (!ScheduleInstallAndRelaunch(L"", {}, &error)) {
      result->Error("RestartError", error);
      return;
    }
    result->Success();
    ExitProcess(0);
  }
  else if (method_call.method_name() == "installUpdate") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("InvalidArguments", "installUpdate expects a map.");
      return;
    }
    auto it = args->find(flutter::EncodableValue("stagingPath"));
    if (it == args->end()) {
      result->Error("InvalidArguments", "stagingPath is required.");
      return;
    }
    const auto* staging_path = std::get_if<std::string>(&it->second);
    if (!staging_path || staging_path->empty()) {
      result->Error("InvalidArguments", "stagingPath must be a non-empty string.");
      return;
    }

    std::wstring wStaging = Utf8ToWide(*staging_path);
    std::vector<std::wstring> removed = RemovedFilesFromArguments(*args);

    // Tentukan direktori target
    std::wstring targetDir = fs::path(CurrentExecutablePath()).parent_path().wstring();

    // Jika kita belum admin dan tidak bisa menulis ke target, minta elevasi
    if (!IsRunningAsAdmin() && !CanWriteToDirectory(targetDir)) {
      // Simpan parameter ke file temp
      fs::path paramsFile = fs::temp_directory_path() / L"desktop_updater_elevated_params.bin";
      ElevatedUpdateParams params{wStaging, removed};
      if (!WriteElevatedParams(paramsFile, params)) {
        result->Error("ElevationError", "Failed to save update parameters.");
        return;
      }

      // Minta elevasi dan kirim argumen --update-elevated
      if (RequestAdminPrivileges(L"--update-elevated")) {
        // Sukses, keluar dari proses ini
        result->Success();
        ExitProcess(0);
      } else {
        // Gagal elevasi (user cancel)
        DeleteFileW(paramsFile.c_str());
        result->Error("ElevationError", "Administrator privileges required to install update.");
        return;
      }
    }

    // Jika sudah admin atau bisa menulis, langsung jalankan
    std::string error;
    if (!ScheduleInstallAndRelaunch(wStaging, removed, &error)) {
      result->Error("InstallError", error);
      return;
    }
    result->Success();
    ExitProcess(0);
  }
  else if (method_call.method_name() == "getExecutablePath") {
    result->Success(flutter::EncodableValue(WideToUtf8(CurrentExecutablePath())));
  }
  else if (method_call.method_name() == "getCurrentVersion") {
    std::wstring exe_path = CurrentExecutablePath();
    DWORD handle = 0;
    DWORD size = GetFileVersionInfoSizeW(exe_path.c_str(), &handle);
    if (size == 0) {
      result->Error("VersionError", "Unable to get version size.");
      return;
    }
    std::vector<BYTE> data(size);
    if (!GetFileVersionInfoW(exe_path.c_str(), handle, size, data.data())) {
      result->Error("VersionError", "Unable to get version info.");
      return;
    }
    struct LANGANDCODEPAGE {
      WORD wLanguage;
      WORD wCodePage;
    }* lpTranslate;
    UINT cbTranslate = 0;
    if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                        reinterpret_cast<LPVOID*>(&lpTranslate), &cbTranslate) ||
        cbTranslate < sizeof(LANGANDCODEPAGE)) {
      result->Error("VersionError", "Unable to get translation info.");
      return;
    }
    wchar_t subBlock[50];
    swprintf_s(subBlock, L"\\StringFileInfo\\%04x%04x\\ProductVersion",
               lpTranslate[0].wLanguage, lpTranslate[0].wCodePage);
    LPBYTE buf = nullptr;
    UINT len = 0;
    if (!VerQueryValueW(data.data(), subBlock, reinterpret_cast<LPVOID*>(&buf), &len)) {
      result->Error("VersionError", "Unable to query product version.");
      return;
    }
    std::wstring productVersion(reinterpret_cast<wchar_t*>(buf));
    size_t plusPos = productVersion.find(L'+');
    if (plusPos == std::wstring::npos || plusPos + 1 >= productVersion.length()) {
      result->Error("VersionError", "Invalid product version format.");
      return;
    }
    std::wstring buildNumber = productVersion.substr(plusPos + 1);
    size_t lastChar = buildNumber.find_last_not_of(L" \t\r\n");
    if (lastChar == std::wstring::npos) {
      result->Error("VersionError", "Invalid product version format.");
      return;
    }
    buildNumber.erase(lastChar + 1);
    result->Success(flutter::EncodableValue(WideToUtf8(buildNumber)));
  }
  else {
    result->NotImplemented();
  }
}

}  // namespace desktop_updater