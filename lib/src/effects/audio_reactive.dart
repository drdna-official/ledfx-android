import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/virtual.dart';

abstract class AudioReactiveEffect extends Effect {
  AudioAnalysisSource? audio;
  AudioReactiveEffect({required super.ledfx, required super.config}) {
    audio = null;
  }

  @override
  void activate(Virtual virtual) {
    super.activate(virtual);
    ledfx.audio ??= AudioAnalysisSource(ledfx: ledfx);
    audio = ledfx.audio;
    ledfx.audio!.subscribe(_audioDataUpdated);
  }

  void _audioDataUpdated() {
    if (isActive && audio != null) audioDataUpdated(audio!);
  }

  void audioDataUpdated(AudioAnalysisSource audio);
}
