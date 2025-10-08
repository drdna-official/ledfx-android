import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

/// Sealed union of all events from the native bridge
sealed class RecordingEvent {
  const RecordingEvent();
}

class AudioEvent extends RecordingEvent {
  final Uint8List data;
  const AudioEvent(this.data);
}

class DevicesInfoEvent extends RecordingEvent {
  final List<AudioDevice> audioDevices;
  DevicesInfoEvent(List data)
    : audioDevices = (data as List? ?? [])
          .map((device) => AudioDevice.fromMap(device.cast<String, dynamic>()))
          .toList();
}

// Audio device model
class AudioDevice extends Equatable {
  final String id;
  final String name;
  final String description;
  final int defaultSampleRate;
  final bool isActive;
  final bool isDefault;
  final AudioDeviceType type;

  const AudioDevice({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultSampleRate,
    required this.isActive,
    required this.isDefault,
    required this.type,
  });

  factory AudioDevice.fromMap(Map<String, dynamic> map) {
    return AudioDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      isActive: map['isActive'] ?? false,
      defaultSampleRate: map['sampleRate'] ?? 44100,
      isDefault: map['isDefault'] ?? false,
      type: AudioDeviceType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AudioDeviceType.input,
      ),
    );
  }

  @override
  List<Object?> get props => [id];
}

enum AudioDeviceType { input, output }

enum AudioCaptureType { microphone, systemAudio }

class StateEvent extends RecordingEvent {
  /// e.g. "started", "paused", "resumed", "stopped"
  final String state;
  const StateEvent(this.state);
}

class ErrorEvent extends RecordingEvent {
  final String message;
  const ErrorEvent(this.message);
}

class AudioBridge {
  AudioBridge._() {
    _event.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        switch (event["type"]) {
          case "audio":
            _controller.add(AudioEvent(event["data"]));
            break;
          case "state":
            _controller.add(StateEvent(event["value"]));
            break;
          case "error":
            _controller.add(ErrorEvent(event["message"]));
            break;
          case "devicesInfo":
            _controller.add(DevicesInfoEvent(List.from(event["devices"])));
        }
      }
    });
  }
  static final AudioBridge instance = AudioBridge._();

  final _method = MethodChannel("system_audio_recorder/methods");
  final _event = EventChannel("system_audio_recorder/events");

  static final _controller = StreamController<RecordingEvent>.broadcast();

  /// Only one stream to listen to
  Stream<RecordingEvent> get events => _controller.stream;

  /// Ask Android to show the MediaProjection dialog (returns bool success)
  Future<bool> requestProjection() async {
    try {
      final res = await _method.invokeMethod<bool?>('requestProjection');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  // Convenience methods for native calls
  Future<bool?> getDevices() async =>
      await _method.invokeMethod<bool?>('requestDeviceList');
  Future<bool?> start([Map<String, dynamic>? args]) async =>
      await _method.invokeMethod<bool?>('startRecording', args);
  Future<bool?> stop() async => await _method.invokeMethod('stopRecording');
  Future<bool?> pause() async => await _method.invokeMethod('pauseRecording');
  Future<bool?> resume() async => await _method.invokeMethod('resumeRecording');
}
