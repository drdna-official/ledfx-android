import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/effect.dart';

abstract class AudioReactiveEffect extends Effect {
  final LEDFx ledfx;

  AudioAnalysisSource? audio;
  AudioReactiveEffect({required this.ledfx}) {
    audio = null;
  }

  @override
  void activate(int channel) {
    super.activate(channel);
    ledfx.audio ??= AudioAnalysisSource(ledfx: ledfx);
    audio = ledfx.audio;
    ledfx.audio!.subscribe(_audioDataUpdated);
  }

  void _audioDataUpdated() {
    if (isActive && audio != null) audioDataUpdated(audio!);
  }

  void audioDataUpdated(AudioAnalysisSource audio);
}
