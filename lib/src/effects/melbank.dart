import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ledfx/aubio.dart';
import 'package:ledfx/aubio_bindings.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/const.dart';
import 'package:ledfx/src/effects/math.dart';
import 'package:ledfx/src/effects/mel_utils.dart';
import 'package:ledfx/src/effects/utils.dart';

class MelbankConfig {
  MelbankConfig({
    required this.name,
    this.maxFreq = MAX_FREQ,
    this.minFreq = MIN_FREQ,
  });

  final String name;
  final int maxFreq;
  final int minFreq;
  late double peakIsolation;
  late CoeffType coeffType;
  late int samples;
  late List<int> maxFreqs;
}

enum CoeffType { mattmel }

// Creates a set of filterbanks to process FFT at different resolutions.
// A constant amount are used to ensure consistent performance.
// If each virtual had its own melbank, you could run into performance issues
// with a high number of virtuals.
class Melbanks {
  final LEDFx ledfx;
  final AudioAnalysisSource audio;

  final int samples;
  final double peakIsolation;
  final CoeffType coeffType;
  final List<int> maxFreqs;
  final int minFreq;

  late List<Map<String, dynamic>> melbankCollection;
  late List<Melbank> melbankProcessors;
  late MelbankConfig melbankConfig;

  late int melCount;
  late int melLength;

  late List<Float64List> melbanks;
  late List<Float64List> melbanksFiltered;
  late double minVolume;

  Melbanks({
    required this.ledfx,
    required this.audio,
    this.samples = 24,
    this.peakIsolation = 0.4,
    this.coeffType = CoeffType.mattmel,
    this.maxFreqs = MEL_MAX_FREQS,
    this.minFreq = MIN_FREQ,
  }) {
    melbankCollection = ledfx.config.melbankCollection ?? [];
    melbankProcessors = [];
    melbankConfig = MelbankConfig(name: "", maxFreq: MAX_FREQ)
      ..peakIsolation = peakIsolation
      ..coeffType = coeffType
      ..samples = samples
      ..maxFreqs = maxFreqs;

    if (melbankCollection.isEmpty) {
      for (var (i, freq) in maxFreqs.indexed) {
        melbankConfig = MelbankConfig(name: "Melbank $i", maxFreq: freq)
          ..peakIsolation = peakIsolation
          ..coeffType = coeffType
          ..samples = samples
          ..maxFreqs = maxFreqs;
        final melbank = Melbank(audio: audio, config: melbankConfig);
        melbankProcessors.add(melbank);
        melbankCollection.add({
          "id": generateId(melbank.config.name),
          "melbank_config": melbankConfig,
        });
      }
    } else {
      for (var melbank in melbankCollection) {
        melbankConfig = (melbank["melbank_config"] as MelbankConfig)
          ..peakIsolation = peakIsolation
          ..coeffType = coeffType
          ..samples = samples
          ..maxFreqs = maxFreqs;
        melbankProcessors.add(Melbank(audio: audio, config: melbankConfig));
      }
    }

    ledfx.config.melbankConfig = melbankConfig;
    melCount = maxFreqs.length;
    melLength = samples;

    melbanks = List<Float64List>.generate(
      melCount,
      (_) => Float64List(melLength),
    );
    melbanksFiltered = List<Float64List>.generate(
      melCount,
      (_) => Float64List(melLength),
    );

    minVolume = audio.minVolume;
  }

  execute() {
    final freqDomain = audio.freqDomain;
    final volumeThreshould = (audio.volume(filtered: true) > minVolume);

    if (volumeThreshould) {
      for (final (i, proc) in melbankProcessors.indexed) {
        proc.execute(freqDomain, melbanks[i], melbanksFiltered[i]);
      }
    } else {
      for (final melbank in melbanks) {
        melbank.fillRange(0, melbank.length, 0.0);
      }
      for (final melbank in melbanksFiltered) {
        melbank.fillRange(0, melbank.length, 0.0);
      }
    }
  }
}

// A single Melbank
class Melbank {
  final AudioAnalysisSource audio;
  final MelbankConfig config;

  late double powerFactor;
  late Pointer<aubio_filterbank_t> filterBank;
  late Float64List melbankFreqsFloat;
  late Int32List melbankFreqs;

  late int lowsIndex;
  late int midsIndex;
  late int highsIndex;

  late ExpFilter melGain;
  late ExpFilter melSmoothing;
  late ExpFilter commonFilter;
  late ExpFilter diffFilter;

  Melbank({required this.audio, required this.config}) {
    powerFactor = tan(0.5 * pi * (config.peakIsolation + 1) / 2);
    switch (config.coeffType) {
      case CoeffType.mattmel:
        final List<double> melbankMatt = equallySpacedDoublesList(
          hzTOmatt(config.minFreq.toDouble()),
          hzTOmatt(config.maxFreq.toDouble()),
          config.samples + 2,
        );
        melbankFreqsFloat = Float64List.fromList(
          melbankMatt.map((mel) => mattTOhz(mel)).toList(),
        );

        filterBank = Aubio.createFilterBank(config.samples, FFT_SIZE);
        filterBank.setTriangleBandsF32(
          freqs: melbankFreqsFloat,
          sampleRate: MIC_RATE,
        );
        melbankFreqsFloat = melbankFreqsFloat.sublist(
          1,
          melbankFreqsFloat.length - 1,
        );
    }

    melbankFreqs = Int32List.fromList(
      melbankFreqsFloat.map((i) => i.toInt()).toList(),
    );

    //Find the indexes for each of the frequency ranges
    lowsIndex = midsIndex = highsIndex = 1;
    for (int i = 0; i < melbankFreqs.length; i++) {
      if (melbankFreqs.elementAt(i) < FREQ_RANGE_SIMPLE[LOWS_RANGE]!.$2) {
        lowsIndex = i + 1;
      }
      if (melbankFreqs.elementAt(i) < FREQ_RANGE_SIMPLE[MIDS_RANGE]!.$2) {
        midsIndex = i + 1;
      }
      if (melbankFreqs.elementAt(i) < FREQ_RANGE_SIMPLE[HIGHS_RANGE]!.$2) {
        highsIndex = i + 1;
      }
    }

    // setup some of the common filters
    melGain = ExpFilter(alphaDecay: 0.01, alphaRise: 0.99);
    melSmoothing = ExpFilter(alphaDecay: 0.7, alphaRise: 0.99);
    commonFilter = ExpFilter(alphaDecay: 0.99, alphaRise: 0.01);
    diffFilter = ExpFilter(alphaDecay: 0.15, alphaRise: 0.99);
  }
  // computes the melbank curve for frequency domain .
  void execute(
    Pointer<cvec_t> freqDomain,
    Float64List melbank,
    Float64List filteredMelbank,
  ) {
    // copyListContents(melbank, filterBank.process(freqDomain, melbank.length));
    melbank.setAll(0, filterBank.process(freqDomain, melbank.length));

    for (int i = 0; i < melbank.length; i++) {
      melbank[i] = pow(melbank[i], powerFactor).toDouble();
    }
    melGain.update(maxOfList(fastBlurArray(melbank, 1.0)));

    final double gainValue = melGain.value.toDouble();
    for (int i = 0; i < melbank.length; i++) {
      // Check for near-zero division, which is crucial for stability
      if (gainValue.abs() > 1e-9) {
        melbank[i] /= gainValue;
      } else {
        melbank[i] = 0.0; // Prevent division by zero
      }
    }

    List<double> smoothedBanks = melSmoothing.update(melbank);
    copyListContents(melbank, smoothedBanks);

    commonFilter.update(melbank);

    List<double> differenceArray = List<double>.generate(melbank.length, (i) {
      return melbank[i] - commonFilter.value[i];
    });
    List<double> diffFiltered = diffFilter.update(differenceArray);
    copyListContents(filteredMelbank, diffFiltered);
  }
}

double hzTOmatt(double freq) {
  return 3700.0 * (log(1 + (freq / 230.0)) / log(12));
}

double mattTOhz(double matt) {
  return 230.0 * pow(12, (matt / 3700)).toDouble() - 230.0;
}
