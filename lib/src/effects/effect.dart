import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/effects/utils.dart';
import 'package:ledfx/src/virtual.dart';

class EffectConfig {
  String name;
  double blur;
  bool flip;
  bool mirror;
  double brightness;
  bool useBG;
  Color backgroudColor;
  double backgroundBrightness;
  bool diag;
  bool advanced;

  EffectConfig({
    required this.name,
    this.blur = 1.0,
    this.flip = false,
    this.mirror = false,
    this.brightness = 1.0,
    this.useBG = false,
    this.backgroudColor = Colors.black,
    this.backgroundBrightness = 1.0,
    this.diag = false,
    this.advanced = false,
  });
}

abstract interface class EffectMixin {
  void onActivate();
}

abstract class Effect {
  final LEDFx ledfx;
  final EffectConfig config;
  String get name => config.name;

  double passed = 0.0;

  bool _active = false;
  bool get isActive => _active;

  List<Float32List>? _pixels;
  List<Float32List>? get pixels => _pixels;
  set pixels(List<Float32List>? pixels) {
    _pixels = pixels;
  }

  int get pixelCount => _pixels?.length ?? 0;

  Virtual? _virtual;
  Virtual? get virtual => _virtual;

  Effect({required this.ledfx, required this.config});
  void activate(Virtual virtual) {
    _virtual = virtual;
    _pixels = List.filled(virtual.effectivePixelCount, Float32List(3));

    if (this is EffectMixin) {
      (this as EffectMixin).onActivate();
    }
    _active = true;
  }

  void del() {
    if (isActive) deactivate();
  }

  void deactivate() {
    _pixels = null;
    _active = false;
  }

  void render() {}

  List<Float32List>? getPixels() {
    if (virtual == null) return null;
    List<Float32List> tmpPixels = List.filled(
      virtual!.effectivePixelCount,
      Float32List(3),
    );
    if (pixels != null) {
      copyListContents(tmpPixels, pixels!);
      if (config.flip) tmpPixels = tmpPixels.reversed.toList();

      if (config.mirror) {
        List<Float32List> reversedPixels = tmpPixels.reversed.toList();
        List<Float32List> mirroredPixels = [...reversedPixels, ...tmpPixels];
        int outputRows = mirroredPixels.length ~/ 2;
        List<Float32List> finalPixels = List<Float32List>.generate(outputRows, (
          i,
        ) {
          // Get the two corresponding rows: one from the even index, one from the odd index
          Float32List evenRow =
              mirroredPixels[2 * i]; // mirrored_pixels[::2] element
          Float32List oddRow =
              mirroredPixels[2 * i + 1]; // mirrored_pixels[1::2] element

          // Create the result row for the maximums
          Float32List maxRow = Float32List(3);

          // Element-wise maximum (loop through columns)
          for (int j = 0; j < 3; j++) {
            maxRow[j] = max(evenRow[j], oddRow[j]); // np.maximum equivalent
          }

          return maxRow;
        });

        tmpPixels = finalPixels;
      }

      if (config.useBG) {
        for (final row in tmpPixels) {
          for (int j = 0; j < 3; j++) {
            // TODO: change o into bgColor[j]
            row[j] += 0;
          }
        }
      }
      // Brightness
      for (final row in tmpPixels) {
        for (int j = 0; j < 3; j++) {
          row[j] *= config.brightness;
        }
      }

      // TODO: Blur

      return tmpPixels;
    }

    return null;
  }
}

class Effects {
  final LEDFx ledfx;
  Effects({required this.ledfx}) {
    ledfx.audio = null;
  }
}
