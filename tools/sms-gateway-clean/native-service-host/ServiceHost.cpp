#include <windows.h>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kServiceName[] = L"BimalPathologySMSGatewayClean";
constexpr DWORD kStopTimeoutMs = 55000;
SERVICE_STATUS_HANDLE statusHandle = nullptr;
SERVICE_STATUS statusValue{};
HANDLE stopEvent = nullptr;
HANDLE childProcess = nullptr;
HANDLE job = nullptr;
DWORD processExit = 0;
std::wstring stopPath;
std::wstring dataDirectory();

void rotateIfLarge(const std::wstring& path) {
  WIN32_FILE_ATTRIBUTE_DATA attributes{};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &attributes)) return;
  ULARGE_INTEGER size{}; size.HighPart = attributes.nFileSizeHigh; size.LowPart = attributes.nFileSizeLow;
  if (size.QuadPart < 10ULL * 1024ULL * 1024ULL) return;
  const std::wstring archived = path + L".1"; DeleteFileW(archived.c_str()); MoveFileExW(path.c_str(), archived.c_str(), MOVEFILE_REPLACE_EXISTING);
}

void logHostStage(const char* stage, DWORD code) {
  const std::wstring path = dataDirectory() + L"\\logs\\native-service.log";
  rotateIfLarge(path);
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
    nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  SYSTEMTIME now{}; GetSystemTime(&now); char line[192]{};
  const int length = sprintf_s(line, "%04u-%02u-%02uT%02u:%02u:%02uZ stage=%s code=%lu\r\n",
    now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond, stage, static_cast<unsigned long>(code));
  DWORD written = 0; if (length > 0) WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr); CloseHandle(file);
}

std::wstring quote(const std::wstring& value) {
  if (value.find_first_of(L" \t\"") == std::wstring::npos) return value;
  std::wstring out = L"\""; size_t slashes = 0;
  for (wchar_t ch : value) {
    if (ch == L'\\') { ++slashes; continue; }
    if (ch == L'\"') { out.append(slashes * 2 + 1, L'\\'); out.push_back(ch); slashes = 0; continue; }
    out.append(slashes, L'\\'); slashes = 0; out.push_back(ch);
  }
  out.append(slashes * 2, L'\\'); out.push_back(L'\"'); return out;
}

std::wstring executableDirectory() {
  std::vector<wchar_t> path(32768); const DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length == path.size()) return {};
  const std::wstring value(path.data(), length); const auto slash = value.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"." : value.substr(0, slash);
}

std::wstring dataDirectory() {
  std::vector<wchar_t> value(32768); const DWORD length = GetEnvironmentVariableW(L"ProgramData", value.data(), static_cast<DWORD>(value.size()));
  if (!length || length >= value.size()) return {};
  return std::wstring(value.data(), length) + L"\\BimalPathology\\SmsGatewayClean";
}

void report(DWORD state, DWORD win32 = NO_ERROR, DWORD serviceCode = 0, DWORD wait = 0) {
  statusValue.dwServiceType = SERVICE_WIN32_OWN_PROCESS; statusValue.dwCurrentState = state;
  statusValue.dwControlsAccepted = state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN : 0;
  statusValue.dwWin32ExitCode = win32; statusValue.dwServiceSpecificExitCode = serviceCode; statusValue.dwWaitHint = wait;
  statusValue.dwCheckPoint = (state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING) ? statusValue.dwCheckPoint + 1 : 0;
  if (statusHandle) SetServiceStatus(statusHandle, &statusValue);
}

bool writeStopRequest() {
  HANDLE file = CreateFileW(stopPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  constexpr char body[] = "stop\n"; DWORD written = 0; const BOOL ok = WriteFile(file, body, sizeof(body) - 1, &written, nullptr);
  FlushFileBuffers(file); CloseHandle(file); return ok && written == sizeof(body) - 1;
}

DWORD WINAPI controlHandler(DWORD control, DWORD, void*, void*) {
  if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
    report(SERVICE_STOP_PENDING, NO_ERROR, 0, kStopTimeoutMs); writeStopRequest(); if (stopEvent) SetEvent(stopEvent);
  }
  return NO_ERROR;
}

DWORD runChild() {
  const std::wstring base = executableDirectory(); const std::wstring node = base + L"\\runtime\\node.exe"; const std::wstring main = base + L"\\app\\src\\main.js";
  if (GetFileAttributesW(node.c_str()) == INVALID_FILE_ATTRIBUTES || GetFileAttributesW(main.c_str()) == INVALID_FILE_ATTRIBUTES) return ERROR_FILE_NOT_FOUND;
  DeleteFileW(stopPath.c_str()); std::wstring command = quote(node) + L" --enable-source-maps " + quote(main);
  std::vector<wchar_t> mutableCommand(command.begin(), command.end()); mutableCommand.push_back(L'\0');
  const std::wstring childLogPath = dataDirectory() + L"\\logs\\node-service.log";
  rotateIfLarge(childLogPath);
  SECURITY_ATTRIBUTES inheritHandles{}; inheritHandles.nLength = sizeof(inheritHandles); inheritHandles.bInheritHandle = TRUE;
  HANDLE childLog = CreateFileW(childLogPath.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
    &inheritHandles, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (childLog == INVALID_HANDLE_VALUE) return GetLastError();
  SetFilePointer(childLog, 0, nullptr, FILE_END);
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE); startup.hStdOutput = childLog; startup.hStdError = childLog;
  PROCESS_INFORMATION process{};
  job = CreateJobObjectW(nullptr, nullptr); if (!job) return GetLastError();
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{}; limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return GetLastError();
  if (!CreateProcessW(node.c_str(), mutableCommand.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED, nullptr, base.c_str(), &startup, &process)) {
    const DWORD error = GetLastError(); CloseHandle(childLog); logHostStage("create_process", error); return error;
  }
  CloseHandle(childLog);
  childProcess = process.hProcess;
  if (!AssignProcessToJobObject(job, childProcess)) {
    const DWORD error = GetLastError(); TerminateProcess(childProcess, error); CloseHandle(process.hThread);
    CloseHandle(childProcess); childProcess = nullptr; logHostStage("assign_job", error); return error;
  }
  if (ResumeThread(process.hThread) == static_cast<DWORD>(-1)) {
    const DWORD error = GetLastError(); TerminateJobObject(job, error); CloseHandle(process.hThread);
    CloseHandle(childProcess); childProcess = nullptr; logHostStage("resume_thread", error); return error;
  }
  CloseHandle(process.hThread); logHostStage("child_started", NO_ERROR);
  HANDLE waits[] = { stopEvent, childProcess }; const DWORD result = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
  if (result == WAIT_OBJECT_0 && WaitForSingleObject(childProcess, kStopTimeoutMs) == WAIT_TIMEOUT) TerminateJobObject(job, ERROR_TIMEOUT);
  DWORD exitCode = 0; GetExitCodeProcess(childProcess, &exitCode); CloseHandle(childProcess); childProcess = nullptr; CloseHandle(job); job = nullptr; DeleteFileW(stopPath.c_str());
  if (result == WAIT_OBJECT_0) { logHostStage("child_stopped", NO_ERROR); return NO_ERROR; }
  const DWORD finalCode = exitCode == 0 ? ERROR_PROCESS_ABORTED : exitCode; logHostStage("child_exited", finalCode); return finalCode;
}

void WINAPI ServiceMain(DWORD, wchar_t**) {
  statusHandle = RegisterServiceCtrlHandlerExW(kServiceName, controlHandler, nullptr); if (!statusHandle) return;
  report(SERVICE_START_PENDING, NO_ERROR, 0, 30000); stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr); const std::wstring data = dataDirectory();
  if (!stopEvent || data.empty()) { report(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR, ERROR_INVALID_ENVIRONMENT); return; }
  stopPath = data + L"\\service-stop.request"; report(SERVICE_RUNNING); processExit = runChild(); CloseHandle(stopEvent); stopEvent = nullptr;
  report(SERVICE_STOPPED, processExit == NO_ERROR ? NO_ERROR : ERROR_SERVICE_SPECIFIC_ERROR, processExit);
}

int selfTest() {
  if (quote(L"plain") != L"plain") return 1;
  if (quote(L"C:\\Program Files\\node.exe") != L"\"C:\\Program Files\\node.exe\"") return 2;
  if (executableDirectory().empty() || dataDirectory().empty()) return 3;
  return 0;
}
}

int wmain(int argc, wchar_t** argv) {
  if (argc == 2 && std::wstring(argv[1]) == L"--self-test") return selfTest();
  SERVICE_TABLE_ENTRYW table[] = {{const_cast<wchar_t*>(kServiceName), ServiceMain}, {nullptr, nullptr}};
  if (!StartServiceCtrlDispatcherW(table)) return static_cast<int>(GetLastError());
  return static_cast<int>(processExit);
}
