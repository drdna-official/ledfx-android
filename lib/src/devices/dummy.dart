import 'dart:typed_data';

import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/ui/home_body.dart' show rgb;

class DummyDevice extends Device {
  DummyDevice({required super.id, required super.ledfx, required super.config});

  @override
  void flush(List<Float64List> data) {
    final int totalBytes = data.length * 3;
    final Uint8List byteData = Uint8List(totalBytes);
    int byteIndex = 0;

    for (final Float64List pixelRow in data) {
      for (final double value in pixelRow) {
        byteData[byteIndex++] = value.toInt().clamp(0, 255);
      }
    }
    rgb.value = byteData.toList();
    super.flush(data);
  }
}
