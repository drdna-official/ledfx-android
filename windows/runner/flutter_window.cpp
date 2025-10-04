#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
// CRITICAL: Include initguid.h FIRST to define GUIDs instead of just declaring them
// #include <initguid.h>

// Now include Windows headers and COM interfaces
#include <windows.h>
// #include <objbase.h>
#include <comdef.h>
// #include <mmdeviceapi.h>
// #include <audioclient.h>
// #include <audiopolicy.h>
// #include <functiondiscoverykeys_devpkey.h>
// #include <avrt.h>
#include "utils.h"

// Link required libraries
// #pragma comment(lib, "ole32.lib")
// #pragma comment(lib, "oleaut32.lib")
// #pragma comment(lib, "uuid.lib")
// #pragma comment(lib, "winmm.lib")

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project)
{
  // Initialize COM
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  // Create device enumerator
  CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                   __uuidof(IMMDeviceEnumerator), (void **)&device_enumerator_);
}

FlutterWindow::~FlutterWindow()
{

  if (audio_client_)
  {
    audio_client_->Release();
    audio_client_ = nullptr;
  }

  StopAudioCapture();

  if (device_enumerator_)
  {
    device_enumerator_->Release();
    device_enumerator_ = nullptr;
  }

  CoUninitialize();
}

bool FlutterWindow::OnCreate()
{

  if (!Win32Window::OnCreate())
  {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view())
  {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Set up method channel
  auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "system_audio_recorder/methods",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel->SetMethodCallHandler([this](const auto &call, auto result)
                                       { HandleMethodCall(call, std::move(result)); });

  // Set up event channel
  auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "system_audio_recorder/events",
      &flutter::StandardMethodCodec::GetInstance());

  event_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](auto arguments, auto events) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
          {
            OnStreamListen(std::move(events));
            return nullptr;
          },
          [this](auto arguments) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
          {
            OnStreamCancel();
            return nullptr;
          }));

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]()
                                                      { this->Show(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy()
{
  StopAudioCapture();
  if (flutter_controller_)
  {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LPCSTR MessageToString(UINT message)
{
  switch (message)
  {
  case WM_FONTCHANGE:
    return "WM_FONTCHANGE";
  case WM_PAINT:
    return "WM_PAINT";
  case WM_DESTROY:
    return "WM_DESTROY";
  case WM_FLUTTER_AUDIO_DATA:
    return "WM_FLUTTER_AUDIO_DATA";
  case WM_FLUTTER_STATE_EVENT:
    return "WM_FLUTTER_STATE_EVENT";
  case WM_FLUTTER_ERROR_EVENT:
    return "WM_FLUTTER_ERROR_EVENT";
  case WM_FLUTTER_DEVICES_EVENT:
    return "WM_FLUTTER_DEVICES_EVENT";
    // Add other message mappings as needed

  default:
    return "UNKNOWN_MESSAGE";
  }
}
LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept
{
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_)
  {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result)
    {
      return *result;
    }
  }

  switch (message)
  {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;

  case WM_FLUTTER_AUDIO_DATA:
  {
    auto audio_data = reinterpret_cast<std::vector<uint8_t> *>(wparam);
    if (event_sink_ && audio_data)
    {
      std::map<flutter::EncodableValue, flutter::EncodableValue> event_map;
      event_map[flutter::EncodableValue("type")] = flutter::EncodableValue("audio");
      event_map[flutter::EncodableValue("data")] = flutter::EncodableValue(*audio_data);
      event_sink_->Success(flutter::EncodableValue(event_map));
    }
    // Remove from posted events
    posted_audio_events_.erase(
        std::remove_if(posted_audio_events_.begin(), posted_audio_events_.end(),
                       [audio_data](const auto &ptr)
                       { return ptr.get() == audio_data; }),
        posted_audio_events_.end());
    return 0;
  }

  case WM_FLUTTER_STATE_EVENT:
  {
    auto msg = reinterpret_cast<std::string *>(wparam);
    if (event_sink_ && msg)
    {
      std::map<flutter::EncodableValue, flutter::EncodableValue> map{
          {flutter::EncodableValue("type"), flutter::EncodableValue("state")},
          {flutter::EncodableValue("value"), flutter::EncodableValue(*msg)}};
      event_sink_->Success(flutter::EncodableValue(map));
    }
    posted_state_events_.erase(
        std::remove_if(posted_state_events_.begin(), posted_state_events_.end(),
                       [msg](const auto &ptr)
                       { return ptr.get() == msg; }),
        posted_state_events_.end());
    return 0;
  }

  case WM_FLUTTER_ERROR_EVENT:
  {
    auto msg = reinterpret_cast<std::string *>(wparam);
    if (event_sink_ && msg)
    {
      std::map<flutter::EncodableValue, flutter::EncodableValue> map{
          {flutter::EncodableValue("type"), flutter::EncodableValue("error")},
          {flutter::EncodableValue("message"), flutter::EncodableValue(*msg)}};
      event_sink_->Success(flutter::EncodableValue(map));
    }
    posted_error_events_.erase(
        std::remove_if(posted_error_events_.begin(), posted_error_events_.end(),
                       [msg](const auto &ptr)
                       { return ptr.get() == msg; }),
        posted_error_events_.end());
    return 0;
  }

  case WM_FLUTTER_DEVICES_EVENT:
  {
    auto data = reinterpret_cast<std::vector<flutter::EncodableValue> *>(wparam);
    if (event_sink_ && data)
    {
      std::map<flutter::EncodableValue, flutter::EncodableValue> map{
          {flutter::EncodableValue("type"), flutter::EncodableValue("devicesInfo")},
          {flutter::EncodableValue("devices"), flutter::EncodableValue(*data)}};
      event_sink_->Success(flutter::EncodableValue(map));
    }
    posted_devices_events_.erase(
        std::remove_if(posted_devices_events_.begin(), posted_devices_events_.end(),
                       [data](const auto &ptr)
                       { return ptr.get() == data; }),
        posted_devices_events_.end());
    return 0;
  }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{

  if (method_call.method_name() == "requestDeviceList")
  {

    try
    {

      auto devices = EnumerateAudioDevices();
      SendDevicesInfoEvent(devices);
      result->Success();
    }
    catch (const std::exception &e)
    {
      SendErrorEvent("Failed to enumerate devices: " + std::string(e.what()));
      result->Error("DEVICE_ENUMERATION_ERROR", "Failed to enumerate devices");
    }
  }
  else if (method_call.method_name() == "startRecording")
  {
    try
    {
      // 1. Make sure we have arguments
      const auto *args_ptr =
          std::get_if<std::map<flutter::EncodableValue, flutter::EncodableValue>>(
              method_call.arguments());

      if (!args_ptr)
      {
        result->Error("INVALID_ARGUMENTS", "Expected argument map for startRecording");
        return;
      }

      const auto &args = *args_ptr;

      // 2. Safe extractor lambdas
      auto getStringArg = [&](const std::string &key) -> std::optional<std::string>
      {
        auto it = args.find(flutter::EncodableValue(key));
        if (it != args.end())
        {
          if (auto val = std::get_if<std::string>(&it->second))
          {
            return *val; // wrap in std::optional
          }
        }
        return std::nullopt;
      };

      auto getIntArg = [&](const std::string &key, int def = 0) -> int
      {
        auto it = args.find(flutter::EncodableValue(key));
        if (it != args.end())
        {
          if (auto val = std::get_if<int>(&it->second))
          {
            return *val;
          }
        }
        return def;
      };

      // 3. Read arguments safely (with defaults)
      std::optional<std::string> deviceIdOpt = getStringArg("deviceId");
      std::optional<std::string> captureTypeOpt = getStringArg("captureType");

      if (!deviceIdOpt.has_value() || deviceIdOpt->empty())
      {
        result->Error("MISSING_ARGUMENT", "Missing required argument: deviceId");
        return;
      }
      if (!captureTypeOpt.has_value() || captureTypeOpt->empty())
      {
        result->Error("MISSING_ARGUMENT", "Missing required argument: captureType - capture | loopback");
        return;
      }
      int sampleRate = getIntArg("sampleRate", 44100);
      int channels = getIntArg("channels", 1);
      int bitsPerSample = getIntArg("bitsPerSample", 16);

      // 4. Start recording
      StartAudioCapture(
          deviceIdOpt.value(),
          captureTypeOpt.value(),
          sampleRate,
          channels,
          bitsPerSample);
      result->Success();
    }
    catch (const std::exception &e)
    {
      SendErrorEvent("Failed to start capture: " + std::string(e.what()));
      result->Error("CAPTURE_START_ERROR", "Failed to start capture");
    }
  }
  else if (method_call.method_name() == "stopRecording")
  {
    try
    {
      StopAudioCapture();
      result->Success();
    }
    catch (const std::exception &e)
    {
      SendErrorEvent("Failed to stop capture: " + std::string(e.what()));
      result->Error("CAPTURE_STOP_ERROR", "Failed to stop capture");
    }
  }
  else
  {
    result->NotImplemented();
  }
}

// Send audio data (PCM bytes) safely on platform thread
void FlutterWindow::SendAudioDataEvent(const std::vector<uint8_t> &pcm16_data)
{
  if (!GetHandle())
    return;

  auto audio_copy = std::make_shared<std::vector<uint8_t>>(pcm16_data);

  // Post to main thread
  PostMessage(GetHandle(), WM_FLUTTER_AUDIO_DATA,
              reinterpret_cast<WPARAM>(audio_copy.get()), 0);

  // Keep shared_ptr alive until processed
  posted_audio_events_.push_back(audio_copy);
}

void FlutterWindow::SendStateEvent(const std::string &state_message)
{
  if (!GetHandle())
    return;

  auto msg = std::make_shared<std::string>(state_message);
  PostMessage(GetHandle(), WM_FLUTTER_STATE_EVENT,
              reinterpret_cast<WPARAM>(msg.get()), 0);

  posted_state_events_.push_back(msg);
}

void FlutterWindow::SendDevicesInfoEvent(
    const std::vector<flutter::EncodableValue> &devices_info)
{
  if (!GetHandle())
    return;

  auto data_copy = std::make_shared<std::vector<flutter::EncodableValue>>(devices_info);

  PostMessage(GetHandle(), WM_FLUTTER_DEVICES_EVENT, reinterpret_cast<WPARAM>(data_copy.get()), 0);

  posted_devices_events_.push_back(data_copy);
}

void FlutterWindow::SendErrorEvent(const std::string &error_message)
{
  if (!GetHandle())
    return;

  auto msg = std::make_shared<std::string>(error_message);
  PostMessage(GetHandle(), WM_FLUTTER_ERROR_EVENT,
              reinterpret_cast<WPARAM>(msg.get()), 0);

  posted_error_events_.push_back(msg);
}

std::vector<flutter::EncodableValue> FlutterWindow::EnumerateAudioDevices()
{
  std::vector<flutter::EncodableValue> devices;
  auto inputDevices = EnumerateDevices(eCapture);
  auto outputDevices = EnumerateDevices(eRender);
  devices.insert(devices.end(), inputDevices.begin(), inputDevices.end());
  devices.insert(devices.end(), outputDevices.begin(), outputDevices.end());
  return devices;
}

std::vector<flutter::EncodableValue> FlutterWindow::EnumerateDevices(EDataFlow dataFlow)
{
  std::vector<flutter::EncodableValue> devices;

  if (!device_enumerator_)
    return devices;

  IMMDeviceCollection *device_collection = nullptr;
  HRESULT hr = device_enumerator_->EnumAudioEndpoints(dataFlow, DEVICE_STATE_ACTIVE, &device_collection);

  if (SUCCEEDED(hr))
  {
    UINT device_count = 0;
    device_collection->GetCount(&device_count);

    // Get default device
    IMMDevice *default_device = nullptr;
    device_enumerator_->GetDefaultAudioEndpoint(dataFlow, eConsole, &default_device);
    LPWSTR default_id = nullptr;
    if (default_device)
    {
      default_device->GetId(&default_id);
    }

    for (UINT i = 0; i < device_count; i++)
    {
      IMMDevice *device = nullptr;
      hr = device_collection->Item(i, &device);

      if (SUCCEEDED(hr))
      {
        LPWSTR device_id = nullptr;
        device->GetId(&device_id);

        std::map<flutter::EncodableValue, flutter::EncodableValue> device_info;
        device_info[flutter::EncodableValue("id")] = flutter::EncodableValue(Utf8FromLPCWSTR(device_id));
        device_info[flutter::EncodableValue("name")] = flutter::EncodableValue(GetDeviceProperty(device, PKEY_Device_FriendlyName));
        device_info[flutter::EncodableValue("description")] = flutter::EncodableValue(GetDeviceProperty(device, PKEY_Device_DeviceDesc));
        device_info[flutter::EncodableValue("isActive")] = flutter::EncodableValue(true);
        device_info[flutter::EncodableValue("isDefault")] = flutter::EncodableValue(
            default_id && wcscmp(device_id, default_id) == 0);
        device_info[flutter::EncodableValue("type")] = flutter::EncodableValue(
            dataFlow == eCapture ? "input" : "output");

        devices.push_back(flutter::EncodableValue(device_info));

        CoTaskMemFree(device_id);
        device->Release();
      }
    }

    if (default_device)
    {
      CoTaskMemFree(default_id);
      default_device->Release();
    }
    device_collection->Release();
  }

  return devices;
}

std::string FlutterWindow::GetDeviceProperty(IMMDevice *device, const PROPERTYKEY &key)
{
  std::string result;
  IPropertyStore *property_store = nullptr;

  HRESULT hr = device->OpenPropertyStore(STGM_READ, &property_store);
  if (SUCCEEDED(hr))
  {
    PROPVARIANT prop_variant;
    PropVariantInit(&prop_variant);

    hr = property_store->GetValue(key, &prop_variant);
    if (SUCCEEDED(hr) && prop_variant.vt == VT_LPWSTR)
    {
      result = Utf8FromLPCWSTR(prop_variant.pwszVal);
    }

    PropVariantClear(&prop_variant);
    property_store->Release();
  }

  return result;
}

void FlutterWindow::StartAudioCapture(const std::string &deviceId, const std::string &captureType,
                                      int sampleRate, int channels, int bitsPerSample)
{
  StopAudioCapture();

  current_device_id_ = deviceId;
  current_capture_type_ = captureType;
  sample_rate_ = sampleRate;
  channels_ = channels;
  bits_per_sample_ = bitsPerSample;

  is_capturing_ = true;
  capture_thread_ = std::thread(&FlutterWindow::AudioCaptureThread, this);
}

void FlutterWindow::StopAudioCapture()
{
  is_capturing_ = false;

  if (capture_thread_.joinable())
  {
    capture_thread_.join();
  }

  if (capture_client_)
  {
    capture_client_->Release();
    capture_client_ = nullptr;
  }

  if (audio_client_)
  {
    audio_client_->Stop();
    audio_client_->Release();
    audio_client_ = nullptr;
  }

  SendStateEvent("recordingStopped");
}

void FlutterWindow::AudioCaptureThread()
{
  if (!device_enumerator_)
  {
    SendErrorEvent("Device enumerator not available");
    return;
  }

  // Get device by ID
  IMMDevice *device = nullptr;
  std::wstring wide_id = std::wstring(current_device_id_.begin(), current_device_id_.end());
  HRESULT hr = device_enumerator_->GetDevice(wide_id.c_str(), &device);

  if (SUCCEEDED(hr))
  {
    try
    {
      if (current_capture_type_ == "capture")
      {
        CaptureAudio(device, false);
      }
      else if (current_capture_type_ == "loopback")
      {
        CaptureAudio(device, true);
      }
    }
    catch (const std::exception &e)
    {
      SendErrorEvent("Capture error: " + std::string(e.what()));
    }
    device->Release();
  }
  else
  {
    SendErrorEvent("Failed to get audio device");
  }
}

void FlutterWindow::CaptureAudio(IMMDevice *device, bool loopback)
{
  HRESULT hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void **)&audio_client_);
  if (FAILED(hr))
  {
    SendErrorEvent("Failed to activate audio client");
    return;
  }

  WAVEFORMATEX custom_format = {};
  custom_format.wFormatTag = WAVE_FORMAT_PCM;                         // PCM
  custom_format.nChannels = static_cast<WORD>(channels_);             // 1=Mono, 2=Stereo
  custom_format.nSamplesPerSec = static_cast<WORD>(sample_rate_);     // Sample rate, e.g. 44100
  custom_format.wBitsPerSample = static_cast<WORD>(bits_per_sample_); // Bit depth
  custom_format.nBlockAlign = custom_format.nChannels * custom_format.wBitsPerSample / 8;
  custom_format.nAvgBytesPerSec = custom_format.nSamplesPerSec * custom_format.nBlockAlign;
  custom_format.cbSize = 0;

  // Get mix format
  WAVEFORMATEX *mix_format = &custom_format;
  // Check if supported
  WAVEFORMATEX *closest_supported = nullptr;
  hr = audio_client_->IsFormatSupported(
      AUDCLNT_SHAREMODE_SHARED,
      mix_format,
      (WAVEFORMATEX **)&closest_supported);
  if (hr == S_FALSE && closest_supported)
  {
    // Use closest supported format
    mix_format = closest_supported;
  }
  else if (FAILED(hr))
  {
    SendErrorEvent("Requested audio format not supported");
    return;
  }

  // hr = audio_client_->GetMixFormat(&mix_format);
  // if (FAILED(hr) || !mix_format)
  // {
  //   SendErrorEvent("Failed to get mix format");
  //   return;
  // }

  // Create event handle
  HANDLE hEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  if (!hEvent)
  {
    // CoTaskMemFree(mix_format);
    if (closest_supported && mix_format == closest_supported)
      CoTaskMemFree(closest_supported);
    SendErrorEvent("Failed to create event handle");
    return;
  }

  // Pick flags based on capture type
  DWORD streamFlags = loopback
                          ? (AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK)
                          : AUDCLNT_STREAMFLAGS_EVENTCALLBACK;

  // Initialize audio client
  hr = audio_client_->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      streamFlags,
      10000000, // 1 second buffer
      0,
      mix_format,
      nullptr);
  if (FAILED(hr))
  {
    CloseHandle(hEvent);
    if (closest_supported && mix_format == closest_supported)
      CoTaskMemFree(closest_supported);
    // CoTaskMemFree(mix_format);
    SendErrorEvent(loopback
                       ? "Failed to initialize audio client (system loopback)"
                       : "Failed to initialize audio client (microphone)");
    return;
  }

  // Set event handle
  hr = audio_client_->SetEventHandle(hEvent);
  if (FAILED(hr))
  {
    CloseHandle(hEvent);
    CoTaskMemFree(mix_format);
    SendErrorEvent("Failed to set event handle");
    return;
  }

  // Get capture client
  hr = audio_client_->GetService(__uuidof(IAudioCaptureClient), (void **)&capture_client_);
  if (FAILED(hr))
  {
    CloseHandle(hEvent);
    // CoTaskMemFree(mix_format);
    SendErrorEvent("Failed to get capture client");
    return;
  }

  // Start capture
  audio_client_->Start();
  SendStateEvent("recordingStarted");

  // Capture loop
  while (is_capturing_)
  {
    DWORD waitResult = WaitForSingleObject(hEvent, INFINITE);
    if (waitResult == WAIT_OBJECT_0 && is_capturing_)
    {
      UINT32 packet_length = 0;
      hr = capture_client_->GetNextPacketSize(&packet_length);

      while (packet_length != 0 && is_capturing_)
      {
        BYTE *data = nullptr;
        UINT32 frames_available = 0;
        DWORD flags = 0;

        hr = capture_client_->GetBuffer(&data, &frames_available, &flags, nullptr, nullptr);
        if (SUCCEEDED(hr))
        {
          UINT32 buffer_size = frames_available * mix_format->nBlockAlign;

          if (buffer_size > 0)
          {
            std::vector<uint8_t> audio_data(data, data + buffer_size);
            SendAudioDataEvent(audio_data);
          }

          capture_client_->ReleaseBuffer(frames_available);
        }

        hr = capture_client_->GetNextPacketSize(&packet_length);
      }
    }
  }

  // Cleanup
  audio_client_->Stop();
  CloseHandle(hEvent);
  // CoTaskMemFree(mix_format);
  if (closest_supported && mix_format == closest_supported)
    CoTaskMemFree(closest_supported);
}

void FlutterWindow::OnStreamListen(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
{
  event_sink_ = std::move(events);
}

void FlutterWindow::OnStreamCancel()
{

  event_sink_ = nullptr;
}
