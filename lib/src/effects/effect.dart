abstract class Effect {
  Effect();
  bool _active = false;
  bool get isActive => _active;

  void activate(int channel) {}

  void deactivate(int channel) {}
}
