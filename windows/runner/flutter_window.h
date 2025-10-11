#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/encodable_value.h>

#include <initguid.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiopolicy.h>
#include <functiondiscoverykeys_devpkey.h>

#include <mutex>
#include <memory>
#include <thread>
#include <atomic>

#include "win32_window.h"

#define WM_FLUTTER_AUDIO_DATA (WM_APP + 236)
#define WM_FLUTTER_STATE_EVENT (WM_APP + 237)
#define WM_FLUTTER_ERROR_EVENT (WM_APP + 238)
#define WM_FLUTTER_DEVICES_EVENT (WM_APP + 239)

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window
{
public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject &project);
  virtual ~FlutterWindow();

protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

private:
  // The project to run.
  flutter::DartProject project_;
  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  // Audio capture state
  std::atomic<bool> is_capturing_{false};
  std::thread capture_thread_;
  std::string current_device_id_;
  std::string current_capture_type_;
  int sample_rate_ = 48000;
  int channels_ = 1;
  int target_blocksize_ = 0;

  // Ring buffer
  std::vector<float> audio_ring_buffer_;
  size_t ring_head_ = 0;     // index of next write
  size_t ring_tail_ = 0;     // index of next read
  size_t ring_capacity_ = 0; // capacity of audio_ring_buffer_ in floats
  std::mutex ring_mutex_;

  std::mutex events_mutex_;
  std::vector<std::shared_ptr<std::vector<float>>> posted_audio_events_;
  std::vector<std::shared_ptr<std::string>> posted_state_events_;
  std::vector<std::shared_ptr<std::string>> posted_error_events_;
  std::vector<std::shared_ptr<std::vector<flutter::EncodableValue>>> posted_devices_events_;

  // WASAPI interfaces
  IMMDeviceEnumerator *device_enumerator_ = nullptr;
  IAudioClient *audio_client_ = nullptr;
  IAudioCaptureClient *capture_client_ = nullptr;

  // Platform channel handlers
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Event channel handlers
  void OnStreamListen(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events);
  void OnStreamCancel();

  // Event emission helpers
  void SendAudioDataEvent(const std::vector<float> &ieee_float_data);
  void SendStateEvent(const std::string &state_message);
  void SendDevicesInfoEvent(const std::vector<flutter::EncodableValue> &devices_info);
  void SendErrorEvent(const std::string &error_message);

  // Audio device enumeration
  std::vector<flutter::EncodableValue> EnumerateAudioDevices();
  std::vector<flutter::EncodableValue> EnumerateDevices(EDataFlow dataFlow);
  std::string GetDeviceProperty(IMMDevice *device, const PROPERTYKEY &key);
  std::vector<BYTE> GetDeviceFormatBlob(IMMDevice *device);

  // Audio capture methods
  void StartAudioCapture(const std::string &deviceId, const std::string &captureType,
                         int sampleRate, int channels, int blockSize);
  void StopAudioCapture();
  void AudioCaptureThread();

  // Audio capture
  void CaptureAudio(IMMDevice *device, bool loopback);
  REFERENCE_TIME CalculateBufferDuration(int device_sample_rate, int target_blocksize);

  // Ring buffer
  void EnsureRingCapacity(size_t required_capacity);
  void RingBufferPush(const float *samples, size_t count);
  size_t RingBufferSize();
  std::vector<float> RingBufferPop(size_t count);
};

#endif // RUNNER_FLUTTER_WINDOW_H_
