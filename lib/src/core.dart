import 'package:ledfx/src/effects/melbank.dart';

class LEDFxConfig {
  List<Map<String, dynamic>>? melbankCollection;
  MelbankConfig? melbankConfig;
}

class LEDFx {
  final LEDFxConfig config;
  LEDFx({required this.config});
}
