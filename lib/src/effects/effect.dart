import 'package:ledfx/src/core.dart';

abstract class Effect {
  Effect();
  bool _active = false;
  bool get isActive => _active;

  void activate(int channel) {}

  void deactivate(int channel) {}
}

class Effects {
  final LEDFx ledfx;
  Effects({required this.ledfx});
}
