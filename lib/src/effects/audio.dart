import 'dart:async' show Timer;
import 'dart:math' show max, min;

import 'package:flutter/foundation.dart';
import 'package:ledfx/audio_bridge.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/effects/const.dart';
import 'package:ledfx/src/effects/dsp.dart';
import 'package:ledfx/src/effects/math.dart';
import 'package:ledfx/src/effects/melbank.dart';
import 'package:ledfx/src/effects/utils.dart'
    show CircularBuffer, FixedSizeQueue;

abstract class AudioInputSource {
  final LEDFx ledfx;
  final int sampleRate;
  final int fftSize;
  final double minVolume;
  final Duration delay;

  late AudioDSP dsp;
  AudioBridge? _audio;

  AudioInputSource({
    required this.ledfx,
    this.sampleRate = 60,
    this.fftSize = FFT_SIZE,
    this.minVolume = 0.2,
    this.delay = Duration.zero,
  });

  bool _audioStreamActive = false;
  final List<VoidCallback> _callbacks = [];
  Timer? _timer;
  int _subscriberThreshould = 0;

  late Cvec _freqDomainNull;
  late Cvec _freqDomain;
  Cvec get freqDomain => _freqDomain;

  late Float32List _rawAudioSample;
  late Float32List _processedAudioSample;
  Float32List audioSample({bool raw = false}) {
    return raw ? _rawAudioSample : _processedAudioSample;
  }

  late double _volume;
  final ExpFilter _volumeFilter = ExpFilter(
    val: -90,
    alphaDecay: 0.99,
    alphaRise: 0.99,
  );
  double volume({filtered = true}) {
    return filtered ? _volumeFilter.value : _volume;
  }

  late DigitalFilter preEmphasis;
  FixedSizeQueue? delayQueue;

  void activate() {
    // setup audio bridge event stream
    _audio ??= AudioBridge.instance;
    _audio!.events.listen((event) {
      switch (event) {
        case StateEvent(:final state):
          switch (state) {
            case "recordingStarted":
              break;
            case "recordingPaused":
              break;
            case "recordingResumed":
              break;
            case "recordingStopped":
              break;
          }
          break;

        case ErrorEvent(:final message):
          break;

        case AudioEvent(:final data):
          break;
        case DevicesInfoEvent(:final outputDevices, :final inputDevices):
          break;
      }
    });

    // Setup a pre-emphasis filter to balance the input volume of lows to highs
    preEmphasis = DigitalFilter(3);
    final selectedCoeff =
        ledfx.config.melbankConfig?.coeffType ?? CoeffType.mattmel;
    switch (selectedCoeff) {
      case CoeffType.mattmel:
        preEmphasis.setBiquad(0, 0.8268, -1.6536, 0.8268, -1.6536, 0.6536);
      // default:
      //   preEmphasis.setBiquad(0, 0.85870, -1.71740, 0.85870, -1.71605, 0.71874);
    }
    _rawAudioSample = Float32List.fromList(
      List.filled(MIC_RATE ~/ sampleRate, 0),
    );

    _freqDomainNull = Cvec(fftSize);
    _freqDomain = _freqDomainNull;

    final samplesToDelay = (0.001 * delay.inMilliseconds * sampleRate).toInt();
    if (samplesToDelay > 0) {
      delayQueue = FixedSizeQueue(samplesToDelay);
    } else {
      delayQueue = null;
    }
  }

  void deactivate() {
    _audioStreamActive = false;
  }

  void subscribe(VoidCallback callback) {
    _callbacks.add(callback);
    if (_callbacks.isNotEmpty && !_audioStreamActive) {
      activate();
    }
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  // NOtifies all subscribers
  void notify() {
    for (final callback in _callbacks) {
      callback();
    }
  }

  void unsubscribe(VoidCallback callback) {
    _callbacks.removeWhere((c) => c == callback);

    if (_callbacks.length <= _subscriberThreshould && _audioStreamActive) {
      if (_timer != null) _timer!.cancel();
      _timer = Timer(Duration(seconds: 5), checkAndDeactivate);
    }
  }

  void checkAndDeactivate() {
    if (_timer != null) {
      _timer!.cancel();
    }
    _timer = null;
    if (_callbacks.length <= _subscriberThreshould && _audioStreamActive) {
      deactivate();
    }
  }

  void invalidateCaches();

  // Pre-processing stage that will run on every sample, only
  // core functionality that will be used for every audio effect
  // should be done here. Everything else should be deferred until
  // queried by an effect.
  void preProcessAudio() {
    //Calculate the current volume for silence detection
    _volume = 1 + Energy.dbSpl(_rawAudioSample) / 100;
    _volume = max(0, min(1, _volume));
    _volumeFilter.update(_volume);

    // Calculate the frequency domain from the filtered data and
    // force all zeros when below the volume threshold
    if ((_volumeFilter.value as double) > minVolume) {
      _processedAudioSample = _rawAudioSample;
      // pre-emphasis
      _processedAudioSample = preEmphasis.processFrame(_rawAudioSample);

      //Pass into the phase vocoder to get a windowed FFT
      _freqDomain = dsp.pvoc(_processedAudioSample);
    } else {
      _freqDomain = _freqDomainNull;
    }
  }
}

enum PitchMethod { yinfft }

enum OnsetMethod { energy, hfc, complex }

enum TempoMethod { simple }

class AudioAnalysisSource extends AudioInputSource {
  // # some frequency constants
  // # beat, bass, mids, high
  static const freqMaxMels = [100, 250, 3000, 10000];

  final PitchMethod pitchMethod;
  final TempoMethod tempoMethod;
  final OnsetMethod onsetMethod;
  final double pitchTolerance;

  late Melbanks melbanks;
  //bar oscillator
  late int beatCounter;
  //beat oscillator
  late DateTime beatTimestamp;
  late int beatPeriod;
  // freq power
  late List<double> freqPowerRaw;
  late ExpFilter freqPowerFilter;
  late List<int> freqMelIndexs;
  // volume based beat detection
  late int beatMaxMelIndex;
  final double beatMinPercentDiff = 0.5;
  final Duration beatMinTimeScince = Duration(milliseconds: 100);
  late int beatPowerHistoryLen;
  late DateTime beatPreviousTime;
  late CircularBuffer<int> beatPowerHistory;

  AudioAnalysisSource({
    required super.ledfx,
    this.pitchMethod = PitchMethod.yinfft,
    this.tempoMethod = TempoMethod.simple,
    this.onsetMethod = OnsetMethod.hfc,
    this.pitchTolerance = 0.8,
  }) {
    initialiseAnalysis();

    subscribe(melbanks.execute);
    subscribe(setPitch);
    subscribe(setOnset);
    subscribe(barOscillator);
    subscribe(volumeBeatNow);
    subscribe(freqPower);

    _subscriberThreshould = _callbacks.length;
  }

  void initialiseAnalysis() {
    melbanks = Melbanks(ledfx: ledfx, audio: this);

    super.dsp = AudioDSP(fftSize, MIC_RATE ~/ sampleRate, sampleRate)
      ..pitchUnit = PitchUnit.midi
      ..pitchTolerance = pitchTolerance;

    //bar oscillator
    beatCounter = 0;
    //beat oscillator
    beatTimestamp = DateTime.now();
    beatPeriod = 2;
    //freq power
    freqPowerRaw = List.filled(freqMaxMels.length, 0.0, growable: false);
    freqPowerFilter = ExpFilter(
      val: List.filled(freqMaxMels.length, 0.0, growable: false),
      alphaDecay: 0.2,
      alphaRise: 0.97,
    );
    freqMelIndexs = [];
    for (final freq in freqMelIndexs) {
      assert(melbanks.melbankConfig.maxFreqs[2] >= freq);
      final index = melbanks.melbankProcessors[2].melbankFreqs.indexWhere(
        (f) => f > freq,
      );
      freqMelIndexs.add(
        (index == -1)
            ? melbanks.melbankProcessors[2].melbankFreqs.length
            : index,
      );
    }

    //volume based beat detection
    final tmpIndex = melbanks.melbankProcessors[0].melbankFreqs.indexWhere(
      (f) => f > freqMaxMels[0],
    );
    beatMaxMelIndex = (tmpIndex == -1)
        ? melbanks.melbankProcessors[0].melbankFreqs.last
        : tmpIndex - 1;
    beatPowerHistoryLen = beatPowerHistoryLen = (sampleRate * 0.2).toInt();
    beatPowerHistory = CircularBuffer(beatPowerHistoryLen);
  }

  @override
  void invalidateCaches() {
    _pitch = null;
    _onset = null;
  }

  double? _pitch;
  double? get pitch => _pitch;
  void setPitch() {
    try {
      _pitch = dsp.detectPitch(audioSample(raw: true));
    } catch (e) {
      debugPrint(e.toString());
      _pitch = null;
    }
  }

  bool? _onset;
  bool? get onset => _onset;
  void setOnset() {
    try {
      _onset = dsp.detectOnset(audioSample(raw: true));
    } catch (e) {
      debugPrint(e.toString());
      _onset = null;
    }
  }

  void barOscillator() {}

  void volumeBeatNow() {}

  void freqPower() {}
}
