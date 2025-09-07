import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:typed_data';

class VisualizerService {
  VisualizerService._();
  static final VisualizerService instance = VisualizerService._();

  final ValueNotifier<List<int>> rgb = ValueNotifier([]);
  AudioVisualizerProcessor? processor;

  // Config
  int ledCount = 150;
  InternetAddress? udpTarget;
  int udpPort = 21324;
  RawDatagramSocket? _socket;

  Future<void> start(Stream<Uint8List> pcmStream) async {
    await stop();
    // init UDP socket if WLED target set
    if (udpTarget != null) {
      _socket ??= await RawDatagramSocket.bind(udpTarget, 0);
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }

  void processChunk(AudioVisualizerProcessor processor, Uint8List chunk) {
    if (this.processor == null) this.processor = processor;
    final frames = processor.process(chunk);
    for (final frame in frames) {
      // Push last frame into ValueNotifier (or all, if you want)
      rgb.value = frame;
      // send to WLED if configured
      if (_socket != null && udpTarget != null) {
        _socket!.send(Uint8List.fromList(frame), udpTarget!, udpPort);
      }
    }
  }

  /// Optional: pipe the RGB stream to WLED via UDP.
  Future<void> sendToWLED({
    required List<int> rgbFrame,
    required InternetAddress target,
    int port = 19446, // typical WLED realtime UDP port
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(Uint8List.fromList(rgbFrame), target, port);
    } finally {
      socket.close();
    }
  }
}

/// ---------- MAPPING ENERGIES → LED FRAME ----------

class AudioVisualizerProcessor {
  final List<BandConfig> bands;
  final VisualConfig cfg;
  final VisualMapper _mapper;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  AudioVisualizerProcessor({required this.bands, required this.cfg})
    : _mapper = VisualMapper(bands, cfg);

  /// Call this for each PCM16 chunk (Uint8List) you receive.
  /// Returns one or more LED frames (`List<int>`) depending on how many hop windows fit.
  List<List<int>> process(Uint8List chunk) {
    final results = <List<int>>[];
    _buffer.add(chunk);

    final data = _buffer.toBytes();
    final samplesAvailable = data.lengthInBytes ~/ 2;
    int readSamples = 0;

    while (samplesAvailable - readSamples >= cfg.windowSize) {
      final startByte = readSamples * 2;
      final endByte = startByte + cfg.windowSize * 2;
      final view = ByteData.sublistView(
        Uint8List.sublistView(data, startByte, endByte),
      );
      final frame = Int16List(cfg.windowSize);
      for (int i = 0; i < cfg.windowSize; i++) {
        frame[i] = view.getInt16(i * 2, Endian.little);
      }

      // Compute band energies + RGB frame
      final energies = VisualMapper.estimateBandEnergies(bands, cfg, frame);
      final rgb = _mapper.makeFrame(energies);
      results.add(rgb);

      readSamples += cfg.hopSize;
    }

    // Keep leftover samples
    final keepBytes = (samplesAvailable - readSamples) * 2;
    final leftover = Uint8List.sublistView(
      data,
      readSamples * 2,
      readSamples * 2 + keepBytes,
    );
    _buffer.clear();
    _buffer.add(leftover);

    return results;
  }
}

class VisualMapper {
  final List<BandConfig> bands;
  final VisualConfig cfg;

  // Per-band smoother
  late final List<PeakSmoother> _smoothers;

  VisualMapper(this.bands, this.cfg) {
    final framePeriod = cfg.hopSize / cfg.sampleRate;
    _smoothers = List.generate(
      bands.length,
      (_) => PeakSmoother(
        attackTimeSec: cfg.attackTime,
        decayTimeSec: cfg.decayTime,
        framePeriodSec: framePeriod,
      ),
    );
  }

  /// Returns normalized band energies (0..1) for each band from one frame of PCM16 samples.
  static List<double> estimateBandEnergies(
    List<BandConfig> bands,
    VisualConfig cfg,
    Int16List frame, // mono PCM16 samples
  ) {
    // Normalize samples to -1..1
    final N = frame.length;
    if (N == 0) return List.filled(bands.length, 0);

    // Precompute probe frequencies per band (log spaced)
    List<List<double>> bandProbes = bands.map((b) {
      final fl = math.max(1.0, b.fLow);
      final fh = math.max(fl + 1.0, b.fHigh);
      final n = cfg.probesPerBand;
      return List.generate(n, (i) {
        final t = n == 1 ? 0.5 : i / (n - 1);
        final f = fl * math.pow(fh / fl, t);
        return f.toDouble();
      });
    }).toList();

    // Build Goertzels
    final gs = bandProbes
        .map(
          (probes) => probes
              .map((f) => Goertzel(_coeffForFreq(f, cfg.sampleRate)))
              .toList(),
        )
        .toList();

    // Process samples
    for (var i = 0; i < N; i++) {
      final x = (frame[i] / 32768.0); // -1..1
      for (final gBand in gs) {
        for (final g in gBand) {
          g.processSample(x);
        }
      }
    }

    // Aggregate energy per band
    List<double> energies = [];
    for (var bi = 0; bi < bands.length; bi++) {
      final gBand = gs[bi];
      double e = 0;
      for (final g in gBand) {
        e += g.magnitude2();
        g.reset();
      }
      // Normalize by window size and probes
      e /= (N * gBand.length);
      // Simple emphasis per band
      e *= bands[bi].emphasis;

      energies.add(e);
    }

    // Log-ish compression → 0..1
    final out = <double>[];
    for (final e in energies) {
      final nf = cfg.noiseFloor;
      final knee = cfg.softKnee;
      final v = ((e - nf) / (1e-12 + (1.0 - nf))).clamp(0.0, 1.0);
      // Soft knee via sqrt
      out.add(math.pow(v, 1.0 / (1.0 + 4.0 * knee)).toDouble());
    }

    return out;
  }

  /// Returns RGB bytes (length = totalLeds * 3).
  List<int> makeFrame(List<double> bandEnergies) {
    final smoothed = List<double>.generate(
      bandEnergies.length,
      (i) => _smoothers[i].update(bandEnergies[i]),
    );

    // Compute per-band lengths & brightness
    final bandLen = <int>[];
    final bandGain = <double>[];
    for (final v in smoothed) {
      final len = (cfg.minLen + v * (cfg.maxLen - cfg.minLen))
          .clamp(cfg.minLen.toDouble(), cfg.maxLen.toDouble())
          .round();
      bandLen.add(len);
      bandGain.add(v);
    }

    final usable = cfg.totalLeds;

    // Initial total requirement (including crossfades)
    final totalNeeded =
        bandLen[0] + bandLen[1] + bandLen[2] + 2 * cfg.crossfadeLeds;

    // Scale factor if overflow
    final scale = totalNeeded > usable ? usable / totalNeeded : 1.0;

    // Apply scaling to bands and crossfade widths
    final newLen0 = (bandLen[0] * scale).floor();
    final newLen1 = (bandLen[1] * scale).floor();
    final newLen2 = (bandLen[2] * scale).floor();
    final newXfade = (cfg.crossfadeLeds * scale).floor().clamp(
      0,
      cfg.crossfadeLeds,
    );

    // Recompute indices
    final s0 = 0;
    final e0 = s0 + newLen0;

    final s1 = e0 + newXfade;
    final e1 = s1 + newLen1;

    final s2 = e1 + newXfade;
    final e2 = s2 + newLen2;

    // Build LED buffer
    final leds = List<Rgb>.filled(cfg.totalLeds, const Rgb(0, 0, 0));
    final offset = 0;

    // Helper to set with brightness & master
    Rgb applyGain(Rgb base, double g) =>
        base.scale((g * cfg.masterBrightness).clamp(0.0, 1.0));

    // Bass segment
    for (int i = s0; i < e0 && (offset + i) < cfg.totalLeds; i++) {
      leds[offset + i] = applyGain(bands[0].color, bandGain[0]);
    }

    // Crossfade bass→mid
    for (int k = 0; k < newXfade; k++) {
      final pos = e0 + k;
      if ((offset + pos) >= cfg.totalLeds) break;
      final t = (k + 1) / (newXfade + 1);
      leds[offset + pos] = Rgb.lerp(
        bands[0].color.scale(bandGain[0]),
        bands[1].color.scale(bandGain[1]),
        t,
      );
    }

    // Mid segment
    for (int i = s1; i < e1 && (offset + i) < cfg.totalLeds; i++) {
      leds[offset + i] = applyGain(bands[1].color, bandGain[1]);
    }

    // Crossfade mid→treble
    for (int k = 0; k < newXfade; k++) {
      final pos = e1 + k;
      if ((offset + pos) >= cfg.totalLeds) break;
      final t = (k + 1) / (newXfade + 1);
      leds[offset + pos] = Rgb.lerp(
        bands[1].color.scale(bandGain[1]),
        bands[2].color.scale(bandGain[2]),
        t,
      );
    }

    // Treble segment
    for (int i = s2; i < e2 && (offset + i) < cfg.totalLeds; i++) {
      leds[offset + i] = applyGain(bands[2].color, bandGain[2]);
    }

    // Convert to RGB byte list
    final out = <int>[];
    for (final p in leds) {
      out
        ..add(p.r)
        ..add(p.g)
        ..add(p.b);
    }
    return out;
  }
}

/// ---------- CONFIG & MODELS ----------

class BandConfig {
  final String name;
  final double fLow; // Hz
  final double fHigh; // Hz
  final Rgb color; // base color for the band
  // Optionally weight within the band if you want (1.0 = flat)
  final double emphasis;

  const BandConfig({
    required this.name,
    required this.fLow,
    required this.fHigh,
    required this.color,
    this.emphasis = 1.0,
  });
}

class VisualConfig {
  final int totalLeds;

  /// Each band’s min/max LED length (exclusive of blanks).
  final int minLen;
  final int maxLen;

  /// Global brightness cap [0..1].
  final double masterBrightness;

  /// Overlap LEDs used for cross-fade between adjacent bands.
  final int crossfadeLeds;

  /// Audio framing (window/frame size in samples) and hop size.
  final int windowSize;
  final int hopSize;

  /// Smoothing (seconds). Separate attack/decay gives snappy rise, slow fall.
  final double attackTime;
  final double decayTime;

  /// Sample rate (Hz) of the PCM16 input.
  final int sampleRate;

  /// Number of probe frequencies per band for Goertzel.
  final int probesPerBand;

  /// Clamp + knee (soft compression) to stabilize visual.
  final double noiseFloor; // ignore energies below this (linear 0..1)
  final double softKnee; // 0..1, larger = more compression

  const VisualConfig({
    required this.totalLeds,
    required this.minLen,
    required this.maxLen,
    this.masterBrightness = 1.0,
    this.crossfadeLeds = 4,
    required this.windowSize,
    required this.hopSize,
    required this.sampleRate,
    this.attackTime = 0.02,
    this.decayTime = 0.18,
    this.probesPerBand = 6,
    this.noiseFloor = 0.02,
    this.softKnee = 0.35,
  });
}

class Rgb {
  final int r, g, b; // 0..255
  const Rgb(this.r, this.g, this.b);

  Rgb scale(double s) {
    final ss = s.clamp(0.0, 1.0);
    return Rgb(
      (r * ss).round().clamp(0, 255),
      (g * ss).round().clamp(0, 255),
      (b * ss).round().clamp(0, 255),
    );
  }

  static Rgb lerp(Rgb a, Rgb b, double t) {
    final tt = t.clamp(0.0, 1.0);
    return Rgb(
      (a.r + (b.r - a.r) * tt).round(),
      (a.g + (b.g - a.g) * tt).round(),
      (a.b + (b.b - a.b) * tt).round(),
    );
  }
}

/// ---------- SMOOTHING (ATTACK/DECAY) ----------

class PeakSmoother {
  final double attackAlpha; // per frame 0..1
  final double decayAlpha; // per frame 0..1
  double _y = 0.0;

  PeakSmoother({
    required double attackTimeSec,
    required double decayTimeSec,
    required double framePeriodSec,
  }) : attackAlpha =
           1.0 - math.exp(-framePeriodSec / (attackTimeSec.clamp(1e-4, 10.0))),
       decayAlpha =
           1.0 - math.exp(-framePeriodSec / (decayTimeSec.clamp(1e-4, 10.0)));

  double update(double x) {
    if (x > _y) {
      // attack (rise quickly)
      _y = _y + attackAlpha * (x - _y);
    } else {
      // decay (fall slowly)
      _y = _y + decayAlpha * (x - _y);
    }
    return _y;
  }
}

/// ---------- AUDIO → ENERGY (GOERTZEL) ----------

class Goertzel {
  final double coeff;
  double sPrev = 0.0;
  double sPrev2 = 0.0;

  Goertzel(this.coeff);

  void reset() {
    sPrev = 0.0;
    sPrev2 = 0.0;
  }

  void processSample(double x) {
    final s = x + coeff * sPrev - sPrev2;
    sPrev2 = sPrev;
    sPrev = s;
  }

  double magnitude2() {
    // |S[k]|^2 = sPrev^2 + sPrev2^2 - coeff*sPrev*sPrev2
    return sPrev * sPrev + sPrev2 * sPrev2 - coeff * sPrev * sPrev2;
  }
}

double _coeffForFreq(double f, int sampleRate) {
  final w = 2 * math.pi * f / sampleRate;
  return 2 * math.cos(w);
}
