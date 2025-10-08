import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/audio_reactive.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/gradient.dart';

class WavelengthEffect extends Effect
    with AudioReactiveEffect, GradientAudioEffect
    implements EffectMixin {
  WavelengthEffect({required super.ledfx, required super.config});
  late List<double> r;

  @override
  void onActivate(int pixelCount) {
    r = List<double>.filled(pixelCount, 0);
  }

  @override
  void audioDataUpdated(AudioAnalysisSource audio) {
    r = melbank(filtered: true);
  }

  @override
  void render() {
    pixels = applyGradient(r);
  }
}
