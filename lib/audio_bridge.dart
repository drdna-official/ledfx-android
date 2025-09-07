import 'dart:async';
import 'package:flutter/services.dart';

/// Sealed union of all events from the native bridge
sealed class RecordingEvent {
  const RecordingEvent();
}

class AudioEvent extends RecordingEvent {
  final Uint8List data;
  const AudioEvent(this.data);
}

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
  Future<bool?> start() async =>
      await _method.invokeMethod<bool?>('startRecording');
  Future<bool?> stop() async => await _method.invokeMethod('stopRecording');
  Future<bool?> pause() async => await _method.invokeMethod('pauseRecording');
  Future<bool?> resume() async => await _method.invokeMethod('resumeRecording');
}
