#include "flutter_window.h"

#include <optional>
#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include <windows.h>
#include <comdef.h>
#include "utils.h"

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

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept
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
    auto float_audio_data = reinterpret_cast<std::vector<float> *>(wparam);

    if (event_sink_ && float_audio_data)
    {
      // Convert float vector to EncodableList for Flutter
      flutter::EncodableList audio_data;
      audio_data.reserve(float_audio_data->size());

      for (float sample : *float_audio_data)
      {
        audio_data.push_back(flutter::EncodableValue(static_cast<double>(sample)));
      }

      std::map<flutter::EncodableValue, flutter::EncodableValue> event_map;
      event_map[flutter::EncodableValue("type")] = flutter::EncodableValue("audio");
      event_map[flutter::EncodableValue("data")] = flutter::EncodableValue(audio_data);
      event_sink_->Success(flutter::EncodableValue(event_map));
    }
    {
      std::lock_guard<std::mutex> lock(events_mutex_);
      posted_audio_events_.erase(
          std::remove_if(posted_audio_events_.begin(), posted_audio_events_.end(),
                         [float_audio_data](const auto &ptr)
                         { return ptr.get() == float_audio_data; }),
          posted_audio_events_.end());
    }
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

void FlutterWindow::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &method_call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
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
      int blocksize = getIntArg("blockSize", 0); // 0 means use default
      std::cout << "sent blockSize: " << blocksize << " frames" << std::endl;

      // 4. Start recording
      StartAudioCapture(
          deviceIdOpt.value(),
          captureTypeOpt.value(),
          sampleRate,
          channels, blocksize);
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
void FlutterWindow::OnStreamListen(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
{
  event_sink_ = std::move(events);
}
void FlutterWindow::OnStreamCancel()
{

  event_sink_ = nullptr;
}
// Send audio data (PCM bytes) safely on platform thread
void FlutterWindow::SendAudioDataEvent(const std::vector<float> &ieee_float_data)
{
  if (!GetHandle())
    return;

  auto audio_copy = std::make_shared<std::vector<float>>(ieee_float_data);

  {
    std::lock_guard<std::mutex> lock(events_mutex_);
    posted_audio_events_.push_back(audio_copy);
  }

  // Post to main thread
  PostMessage(GetHandle(), WM_FLUTTER_AUDIO_DATA,
              reinterpret_cast<WPARAM>(audio_copy.get()), 0);
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

void FlutterWindow::SendDevicesInfoEvent(const std::vector<flutter::EncodableValue> &devices_info)
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

        int32_t sample_rate = 0;
        std::vector<BYTE> format_blob = GetDeviceFormatBlob(device);
        if (format_blob.size() >= sizeof(WAVEFORMATEX))
        {
          WAVEFORMATEX *wfx = reinterpret_cast<WAVEFORMATEX *>(format_blob.data());
          sample_rate = wfx->nSamplesPerSec;
        }
        device_info[flutter::EncodableValue("sampleRate")] = flutter::EncodableValue(sample_rate);

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

std::vector<BYTE> FlutterWindow::GetDeviceFormatBlob(IMMDevice *device)
{
  std::vector<BYTE> format_data;
  IPropertyStore *property_store = nullptr;
  // Use the key for the device's default audio format
  const PROPERTYKEY key = PKEY_AudioEngine_DeviceFormat;

  HRESULT hr = device->OpenPropertyStore(STGM_READ, &property_store);

  if (SUCCEEDED(hr))
  {
    PROPVARIANT pv;
    PropVariantInit(&pv);
    hr = property_store->GetValue(key, &pv);

    // Check for success AND the correct type (BLOB)
    if (SUCCEEDED(hr) && pv.vt == VT_BLOB && pv.blob.cbSize > 0)
    {
      // Copy the binary data into the vector
      format_data.assign(pv.blob.pBlobData, pv.blob.pBlobData + pv.blob.cbSize);
    }

    PropVariantClear(&pv);
    property_store->Release();
  }
  return format_data;
}

void FlutterWindow::StartAudioCapture(const std::string &deviceId, const std::string &captureType, int sampleRate, int channels, int blockSize)
{
  StopAudioCapture();

  current_device_id_ = deviceId;
  current_capture_type_ = captureType;
  sample_rate_ = sampleRate;
  channels_ = channels;
  target_blocksize_ = blockSize;

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
  custom_format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;               // Float
  custom_format.nChannels = static_cast<WORD>(channels_);          // 1=Mono, 2=Stereo
  custom_format.nSamplesPerSec = static_cast<DWORD>(sample_rate_); // Sample rate, e.g. 44100
  custom_format.wBitsPerSample = static_cast<WORD>(32);            // Bit depth
  custom_format.nBlockAlign = static_cast<WORD>(channels_ * 32 / 8);
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

  int device_sample_rate = mix_format ? mix_format->nSamplesPerSec : sample_rate_;

  std::cout << "Device SampleRate/Mic Rate " << device_sample_rate << " Hz" << std::endl;

  REFERENCE_TIME buffer_duration;
  if (target_blocksize_ > 0)
  {
    // Use specified blocksize
    buffer_duration = CalculateBufferDuration(device_sample_rate, target_blocksize_);

    std::cout << "Using blocksize: " << target_blocksize_ << " frames" << std::endl;
    std::cout << "Buffer duration: " << (buffer_duration / 10000.0) << " ms" << std::endl;
  }
  else
  {
    // Use default buffer duration
    buffer_duration = 10000000; // 1s in 100ns units
    std::cout << "blockSize not specified, using buffer duration: " << (buffer_duration / 10000.0) << " ms" << std::endl;
  }
  // Initialize audio client
  hr = audio_client_->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      streamFlags,
      buffer_duration,
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
  // Get actual buffer size that was allocated
  UINT32 actual_buffer_frame_size;
  hr = audio_client_->GetBufferSize(&actual_buffer_frame_size);
  if (SUCCEEDED(hr))
  {
    std::cout << "Requested buffer duration: " << (buffer_duration / 10000.0) << " ms" << std::endl;
    std::cout << "Actual buffer size: " << actual_buffer_frame_size << " frames" << std::endl;
    std::cout << "Actual buffer duration: " << (actual_buffer_frame_size * 1000.0 / sample_rate_) << " ms" << std::endl;
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

  // Clear/Reset ring buffer
  {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    audio_ring_buffer_.clear();
    audio_ring_buffer_.shrink_to_fit(); // optional
    ring_capacity_ = 0;
    ring_head_ = ring_tail_ = 0;
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

          UINT32 useFrames = frames_available; // use all available frames
          float *float_data = reinterpret_cast<float *>(data);
          UINT32 float_count = useFrames * mix_format->nChannels; // Number of float samples

          if (flags & AUDCLNT_BUFFERFLAGS_SILENT)
          {
            // produce zeros
            std::vector<float> zero_buf(float_count, 0.0f);
            RingBufferPush(zero_buf.data(), zero_buf.size());
          }
          else if (float_count > 0)
          {
            // push whatever we have into the ring (interleaved)
            RingBufferPush(float_data, float_count);
          }

          // Release the frames we read from WASAPI
          capture_client_->ReleaseBuffer(frames_available);

          // Now: while ring has enough samples to form one target block, pop and send
          // target_blocksize_ is frames; convert to sample count:
          size_t frames_needed = (target_blocksize_ > 0) ? target_blocksize_ : useFrames;
          if (frames_needed == 0)
            frames_needed = useFrames; // fallback
          size_t samples_needed = frames_needed * mix_format->nChannels;

          // Loop: produce as many full blocks as available
          while (RingBufferSize() >= samples_needed && is_capturing_)
          {
            // Pop exactly samples_needed floats
            std::vector<float> block = RingBufferPop(samples_needed);

            // If device is stereo and you want mono, convert here:
            if (mix_format->nChannels == 2)
            {
              std::vector<float> mono_block;
              mono_block.reserve(frames_needed);
              for (size_t i = 0; i + 1 < block.size(); i += 2)
              {
                float left = block[i];
                float right = block[i + 1];
                mono_block.push_back((left + right) * 0.5f);
              }
              SendAudioDataEvent(mono_block);
            }
            else
            {
              // If channels == 1, send as-is.
              SendAudioDataEvent(block);
            }
          }
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

REFERENCE_TIME FlutterWindow::CalculateBufferDuration(int device_sample_rate, int target_blocksize)
{

  double duration_seconds = static_cast<double>(target_blocksize) / static_cast<double>(device_sample_rate);

  // Convert to 100-nanosecond units (REFERENCE_TIME)
  REFERENCE_TIME buffer_duration = static_cast<REFERENCE_TIME>(duration_seconds * 10000000.0);

  // Ensure minimum buffer duration (Windows typically requires at least 3ms in exclusive mode, 10ms in shared mode)
  REFERENCE_TIME min_duration = 30000; // 3ms in 100ns units
  if (buffer_duration < min_duration)
  {
    buffer_duration = min_duration;
  }

  return buffer_duration;
}

// Ensure ring buffer capacity >= required_capacity
void FlutterWindow::EnsureRingCapacity(size_t required_capacity)
{
  std::lock_guard<std::mutex> lock(ring_mutex_);
  if (ring_capacity_ >= required_capacity)
    return;
  // grow to next power-of-two-ish or just the required * 2 size
  size_t new_capacity = required_capacity * 2;
  std::vector<float> new_buf(new_capacity);
  // If there is existing data, copy it into new buffer starting at 0
  size_t current_size = 0;
  if (ring_capacity_ > 0)
  {
    if (ring_head_ >= ring_tail_)
    {
      current_size = ring_head_ - ring_tail_;
      std::copy(audio_ring_buffer_.begin() + ring_tail_,
                audio_ring_buffer_.begin() + ring_head_,
                new_buf.begin());
    }
    else
    {
      // wrapped
      current_size = ring_capacity_ - ring_tail_ + ring_head_;
      size_t first_part = ring_capacity_ - ring_tail_;
      std::copy(audio_ring_buffer_.begin() + ring_tail_,
                audio_ring_buffer_.end(),
                new_buf.begin());
      std::copy(audio_ring_buffer_.begin(),
                audio_ring_buffer_.begin() + ring_head_,
                new_buf.begin() + first_part);
    }
  }
  audio_ring_buffer_.swap(new_buf);
  ring_capacity_ = new_capacity;
  ring_tail_ = 0;
  ring_head_ = current_size;
}
// push samples into ring buffer (samples vector is float samples interleaved)
void FlutterWindow::RingBufferPush(const float *samples, size_t count)
{
  std::lock_guard<std::mutex> lock(ring_mutex_);
  if (ring_capacity_ == 0)
  {
    // initial allocation: keep some headroom (e.g. 8 blocks)
    size_t desired = std::max<size_t>(count * 8, count * 2);
    audio_ring_buffer_.assign(desired, 0.0f);
    ring_capacity_ = desired;
    ring_head_ = 0;
    ring_tail_ = 0;
  }
  // if not enough space, grow
  size_t free_space = (ring_tail_ <= ring_head_) ? (ring_capacity_ - (ring_head_ - ring_tail_)) : (ring_tail_ - ring_head_);
  if (free_space <= count)
  {
    // grow to fit
    EnsureRingCapacity((ring_head_ >= ring_tail_ ? (ring_head_ - ring_tail_) : (ring_capacity_ - ring_tail_ + ring_head_)) + count);
  }

  // write possibly in two parts
  size_t first_write = std::min(count, ring_capacity_ - ring_head_);
  std::copy(samples, samples + first_write, audio_ring_buffer_.begin() + ring_head_);
  ring_head_ = (ring_head_ + first_write) % ring_capacity_;
  size_t remaining = count - first_write;
  if (remaining > 0)
  {
    std::copy(samples + first_write, samples + first_write + remaining, audio_ring_buffer_.begin() + ring_head_);
    ring_head_ = (ring_head_ + remaining) % ring_capacity_;
  }
}
// check how many floats currently stored
size_t FlutterWindow::RingBufferSize()
{
  std::lock_guard<std::mutex> lock(ring_mutex_);
  if (ring_capacity_ == 0)
    return 0;
  if (ring_head_ >= ring_tail_)
    return ring_head_ - ring_tail_;
  return ring_capacity_ - ring_tail_ + ring_head_;
}
// pop exactly 'count' floats (assumes count <= RingBufferSize()). Returned vector has length 'count'.
std::vector<float> FlutterWindow::RingBufferPop(size_t count)
{
  std::lock_guard<std::mutex> lock(ring_mutex_);
  std::vector<float> out;
  out.resize(count);
  if (count == 0)
    return out;
  size_t first_read = std::min(count, ring_capacity_ - ring_tail_);
  std::copy(audio_ring_buffer_.begin() + ring_tail_, audio_ring_buffer_.begin() + ring_tail_ + first_read, out.begin());
  ring_tail_ = (ring_tail_ + first_read) % ring_capacity_;
  size_t remaining = count - first_read;
  if (remaining > 0)
  {
    std::copy(audio_ring_buffer_.begin() + ring_tail_, audio_ring_buffer_.begin() + ring_tail_ + remaining, out.begin() + first_read);
    ring_tail_ = (ring_tail_ + remaining) % ring_capacity_;
  }
  return out;
}