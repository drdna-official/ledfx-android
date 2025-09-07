import 'package:flutter/material.dart';

class VisualizerPainter extends CustomPainter {
  final List<int> rgb; // flat RGB buffer
  final int ledCount;

  VisualizerPainter({required this.rgb, required this.ledCount});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final ledW = size.width / ledCount;
    for (int i = 0; i < ledCount; i++) {
      final idx = i * 3;
      final r = idx < rgb.length ? rgb[idx] : 0;
      final g = idx + 1 < rgb.length ? rgb[idx + 1] : 0;
      final b = idx + 2 < rgb.length ? rgb[idx + 2] : 0;
      paint.color = Color.fromARGB(255, r, g, b);
      canvas.drawRect(Rect.fromLTWH(i * ledW, 0, ledW, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant VisualizerPainter old) => true;
}
