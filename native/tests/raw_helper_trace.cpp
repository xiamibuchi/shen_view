// Windows integration-test proxy. Forward the real helper's binary streams
// unchanged and log commands separately, so a displayed frame cannot be
// mistaken for evidence that sensor development actually ran.
#include <windows.h>
#include <filesystem>
#include <string>
#include <vector>

std::wstring Environment(const wchar_t* name) {
  const auto count = GetEnvironmentVariableW(name, nullptr, 0);
  if (!count) return {};
  std::vector<wchar_t> value(count);
  GetEnvironmentVariableW(name, value.data(), count);
  return value.data();
}

std::wstring Quote(const std::wstring& argument) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (const auto c : argument) {
    if (c == L'\\') { ++slashes; continue; }
    result.append(slashes * (c == L'\"' ? 2 : 1), L'\\');
    slashes = 0;
    if (c == L'\"') result += L'\\';
    result += c;
  }
  result.append(slashes * 2, L'\\');
  return result + L"\"";
}

std::string Utf8(const std::wstring& text) {
  const int count = WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
      static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string result(count, 0);
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
      result.data(), count, nullptr, nullptr);
  return result;
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 3 && argc != 5) return 2;
  const auto real = Environment(L"RAW_TRACE_HELPER");
  const auto log = Environment(L"RAW_TRACE_LOG");
  if (real.empty() || log.empty()) return 2;
  const auto file = CreateFileW(log.c_str(), FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return 3;
  const auto record = Utf8(std::wstring(argv[1]) + L"\t" +
      std::filesystem::path(argv[2]).filename().wstring() + L"\t" +
      (argc == 5 ? argv[3] : L"0") + L"\t" +
      (argc == 5 ? argv[4] : L"0") + L"\n");
  DWORD written = 0;
  const auto logged = WriteFile(file, record.data(),
      static_cast<DWORD>(record.size()), &written, nullptr);
  CloseHandle(file);
  if (!logged || written != record.size()) return 3;

  std::wstring command = Quote(real);
  for (int i = 1; i < argc; ++i) command += L" " + Quote(argv[i]);
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(real.c_str(), command.data(), nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &process))
    return 4;
  const auto job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation,
      &limits, sizeof(limits)) || !AssignProcessToJobObject(job, process.hProcess)) {
    TerminateProcess(process.hProcess, 5);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    if (job) CloseHandle(job);
    return 5;
  }
  ResumeThread(process.hThread);
  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(process.hProcess, &code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  CloseHandle(job);
  return static_cast<int>(code);
}
