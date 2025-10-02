#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

void CreateAndAttachConsole()
{
  if (::AllocConsole())
  {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout))
    {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr))
    {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments()
{
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t **argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr)
  {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++)
  {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t *utf16_string)
{
  if (utf16_string == nullptr)
  {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
                                   CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
                                   -1, nullptr, 0, nullptr, nullptr) -
                               1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size())
  {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0)
  {
    return std::string();
  }
  return utf8_string;
}

// Convert LPWSTR (wide string) → UTF-8 std::string
std::string Utf8FromLPCWSTR(LPCWSTR wide)
{
  if (!wide)
    return {};
  int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  std::string result(len - 1, '\0'); // len includes null terminator
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, result.data(), len, nullptr, nullptr);
  return result;
}

// Helper functions for string conversion
std::string wideToUtf8(const std::wstring &wide)
{
  if (wide.empty())
    return std::string();

  int sizeNeeded = WideCharToMultiByte(CP_UTF8, 0, &wide[0],
                                       (int)wide.size(), nullptr, 0, nullptr, nullptr);
  std::string utf8(sizeNeeded, 0);
  WideCharToMultiByte(CP_UTF8, 0, &wide[0], (int)wide.size(),
                      &utf8[0], sizeNeeded, nullptr, nullptr);
  return utf8;
}

std::wstring utf8ToWide(const std::string &utf8)
{
  if (utf8.empty())
    return std::wstring();

  int sizeNeeded = MultiByteToWideChar(CP_UTF8, 0, &utf8[0],
                                       (int)utf8.size(), nullptr, 0);
  std::wstring wide(sizeNeeded, 0);
  MultiByteToWideChar(CP_UTF8, 0, &utf8[0], (int)utf8.size(),
                      &wide[0], sizeNeeded);
  return wide;
}