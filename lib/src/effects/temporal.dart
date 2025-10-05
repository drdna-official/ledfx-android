import 'dart:async';

import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/utils.dart';

// ignore: constant_identifier_names
const DEFAULT_RATE = 1.0 / 10.0;

abstract class TemporalEffect extends Effect implements EffectMixin {
  final double speed;

  TemporalEffect({
    required super.ledfx,
    required super.config,
    this.speed = 1.0,
  });

  bool _active = false;
  Timer? _loopTimer;
  double? _interval;
  int currentIntervalInMiliS = 1;
  void _loopFunction(Timer timer) {
    if (!_active) {
      timer.cancel();
      return;
    }
    final currentTime = DateTime.now().microsecondsSinceEpoch;

    var sleepInterval = effectLoop();
    sleepInterval = (sleepInterval ?? 1.0) * DEFAULT_RATE;

    _interval =
        ((sleepInterval / speed) -
        (DateTime.now().microsecondsSinceEpoch - currentTime) * 0.000001);
    if (_interval! < 0.001) _interval = 0.001;

    final intervalInMili = (_interval! * 1000).round();

    if (intervalInMili != currentIntervalInMiliS) {
      currentIntervalInMiliS = intervalInMili;
      timer.cancel();
      _loopTimer = Timer.periodic(
        Duration(milliseconds: currentIntervalInMiliS),
        _loopFunction,
      );
    }
  }

  // # Treat the return value of the effect loop as a speed modifier
  // # such that effects that are naturally faster or slower can have
  // # a consistent feel.
  double? effectLoop();

  @override
  void onActivate() {
    _active = true;
    _loopTimer = Timer.periodic(
      Duration(milliseconds: currentIntervalInMiliS),
      _loopFunction,
    );
  }

  @override
  void deactivate() {
    if (_active) {
      _active = false;
      _loopTimer?.cancel();
      _loopTimer = null;
    }
    super.deactivate();
  }
}

class RainbowEffect extends TemporalEffect {
  double freq;
  RainbowEffect({
    required super.ledfx,
    required super.config,
    super.speed,
    this.freq = 1.0,
  });

  double _hue = 0.1;

  @override
  double? effectLoop() {
    double hueDelta = freq / pixelCount;
    pixels = fillRainbow(pixels!, _hue, hueDelta);

    _hue = _hue + 0.01;
    return null;
  }
}
