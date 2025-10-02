import 'package:ledfx/src/core.dart';

class Virtual {
  bool _active = false;
  bool get active => _active;

  int _refreshRate = 0;
  int get refreshRate => _refreshRate;

  final String id;
  Virtual({required this.id});
}

class Virtuals {
  // Singleton instance
  static late final Virtuals instance;
  Virtuals._({required this.ledfx});

  final LEDFx ledfx;
  bool _initialised = false;
  bool _paused = false;
  Map _virtuals = {};

  static void initialize({required LEDFx ledfx}) {
    instance = Virtuals._(ledfx: ledfx);
    bool _initialised = true;
    bool _paused = false;
    Map _virtuals = {};
  }
}
