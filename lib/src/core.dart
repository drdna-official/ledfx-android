import 'package:flutter/foundation.dart';
import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/melbank.dart';
import 'package:ledfx/src/events.dart';
import 'package:n_dimensional_array/domain/models/nd_array.dart';

enum Transmission { base64Compressed, uncompressed }

class LEDFxConfig {
  List<Map<String, dynamic>>? melbankCollection;
  MelbankConfig? melbankConfig;

  final int visualizationFPS;
  final int visualisationMaxLen;
  final Transmission transmissionMode;
  LEDFxConfig({
    this.visualizationFPS = 24,
    this.visualisationMaxLen = 1,
    this.transmissionMode = Transmission.uncompressed,
  });
}

class LEDFx {
  final LEDFxConfig config;
  AudioAnalysisSource? audio;
  late final LEDFxEvents events;

  late VoidCallback virtualListener;
  late VoidCallback deviceListener;
  late void Function(LEDFxEvent) visualisationUpdateListener;

  LEDFx({required this.config}) {
    events = LEDFxEvents(this);
    setupVisualisationEvents();
  }

  setupVisualisationEvents() async {
    final minTimeSince = 1 / config.visualizationFPS * 1000_000;
    final timeSinceLast = {};
    final maxLen = config.visualisationMaxLen;

    void handleVisualisationUpdate(LEDFxEvent event) {
      final isDevice = event.eventType == LEDFxEvent.DEVICE_UPDATE;
      final timeNow = DateTime.now();
      final visID = isDevice
          ? (event as DeviceUpdateEvent).deviceID
          : (event as VirtualUpdateEvent).virtualID;
      if (timeSinceLast[visID] == null) {
        timeSinceLast[visID] == timeNow.microsecond;
        return;
      }
      final timeSince = timeNow.microsecond - timeSinceLast[visID];
      if (timeSince < minTimeSince) return;
      timeSinceLast[visID] == timeNow.microsecond;

      //TODO: implement virtuals
      final rows = 1;

      NdArray pixels = isDevice
          ? (event as DeviceUpdateEvent).pixels
          : (event as VirtualUpdateEvent).pixels;
      final pixelsLen = pixels.length;
      List<int> shape = [rows, (pixelsLen / rows).toInt()];

      if (pixelsLen > maxLen) {}

      if (config.transmissionMode == Transmission.base64Compressed) {
      } else {
        if (pixels.isEmpty || pixels[0].isEmpty) {
          return;
        }

        final List<int> pixelsShape = pixels.shape;

        List<List<int>> transposedAndCasted = List.generate(
          pixelsShape[1],
          (j) => List<int>.filled(pixelsShape[0], 0),
        );

        for (int i = 0; i < pixelsShape[0]; i++) {
          for (int j = 0; j < pixelsShape[1]; j++) {
            // Get the value, ensure it's clamped and converted to 0-255 integer (uint8)
            double val = pixels[i][j];

            // Clamp values between 0 and 255 and cast to int
            int uint8Value = val.clamp(0.0, 255.0).round().toInt();

            // Place into the transposed position
            transposedAndCasted[j][i] = uint8Value;
          }
        }
        pixels = NdArray.fromList(transposedAndCasted);
      }

      events.fireEvent(
        VisualisationUpdateEvent(visID, pixels, shape, isDevice),
      );
    }

    visualisationUpdateListener = handleVisualisationUpdate;
    deviceListener = await events.addListener(
      visualisationUpdateListener,
      LEDFxEvent.DEVICE_UPDATE,
    );
    virtualListener = await events.addListener(
      visualisationUpdateListener,
      LEDFxEvent.VIRTUAL_UPDATE,
    );
  }
}
