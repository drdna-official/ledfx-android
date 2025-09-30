import 'dart:math';
import 'dart:typed_data';

class Complex {
  final double re;
  final double im;
  const Complex(this.re, this.im);
  Complex operator +(Complex o) => Complex(re + o.re, im + o.im);
  Complex operator -(Complex o) => Complex(re - o.re, im - o.im);
  Complex operator *(Complex o) =>
      Complex(re * o.re - im * o.im, re * o.im + im * o.re);
  double get magnitude => sqrt(re * re + im * im);
  double get phase => atan2(im, re);
}

/// Frequency-domain container
class Cvec {
  final List<double> norm; // magnitudes
  final List<double> phas; // phases
  final int length;
  Cvec(this.length)
    : norm = List.filled(length, 0.0),
      phas = List.filled(length, 0.0);
  void fromSpectrum(List<Complex> spectrum) {
    for (int i = 0; i < length; i++) {
      norm[i] = spectrum[i].magnitude;
      phas[i] = spectrum[i].phase;
    }
  }
}

/// ---------- FILTERBANK ----------
class Filterbank {
  final int nBands;
  final int fftSize;
  List<List<double>> coeffs;

  Filterbank(this.nBands, this.fftSize)
    : coeffs = List.generate(nBands, (_) => List.filled(fftSize ~/ 2 + 1, 0.0));

  /// Triangular mel-style bands
  void setTriangleBands(Float32List freqs, int sampleRate) {
    if (freqs.length != nBands + 2) {
      throw Exception("Need nBands+2 frequencies for triangle bands");
    }
    for (int b = 0; b < nBands; b++) {
      double fLow = freqs[b];
      double fCenter = freqs[b + 1];
      double fHigh = freqs[b + 2];
      for (int i = 0; i < fftSize ~/ 2 + 1; i++) {
        double freq = i * sampleRate / fftSize;
        if (freq >= fLow && freq <= fCenter) {
          coeffs[b][i] = (freq - fLow) / (fCenter - fLow);
        } else if (freq > fCenter && freq <= fHigh) {
          coeffs[b][i] = (fHigh - freq) / (fHigh - fCenter);
        } else {
          coeffs[b][i] = 0.0;
        }
      }
    }
  }

  /// Set custom coeffs directly
  void setCoeffs(List<List<double>> newCoeffs) {
    if (newCoeffs.length != nBands) {
      throw Exception("Coeff size mismatch");
    }
    coeffs = newCoeffs;
  }

  /// Apply filterbank to a frequency-domain vector
  List<double> apply(Cvec cvec) {
    var bands = List.filled(nBands, 0.0);
    for (int b = 0; b < nBands; b++) {
      double sum = 0.0;
      for (int i = 0; i < cvec.norm.length; i++) {
        sum += cvec.norm[i] * coeffs[b][i];
      }
      bands[b] = sum;
    }
    return bands;
  }
}

/// Window functions
class Window {
  static List<double> hann(int n) =>
      List.generate(n, (i) => 0.5 * (1 - cos(2 * pi * i / (n - 1))));
}

/// FFT (recursive radix-2)
class FFTUtils {
  static List<Complex> fft(List<double> input) {
    int n = input.length;
    if (n == 1) return [Complex(input[0], 0.0)];
    if (n % 2 != 0) throw Exception("FFT length must be power of 2");
    var even = List.generate(n ~/ 2, (i) => input[2 * i]);
    var odd = List.generate(n ~/ 2, (i) => input[2 * i + 1]);
    var fftEven = fft(even);
    var fftOdd = fft(odd);
    var spectrum = List<Complex>.filled(n, Complex(0, 0));
    for (int k = 0; k < n ~/ 2; k++) {
      var twiddle =
          Complex(cos(-2 * pi * k / n), sin(-2 * pi * k / n)) * fftOdd[k];
      spectrum[k] = fftEven[k] + twiddle;
      spectrum[k + n ~/ 2] = fftEven[k] - twiddle;
    }
    return spectrum;
  }
}

/// ---------- ENERGY HELPERS ----------
class Energy {
  static double rms(List<double> frame) {
    double sum = frame.fold(0.0, (acc, v) => acc + v * v);
    return sqrt(sum / frame.length);
  }

  static double dbSpl(List<double> frame, {double eps = 1e-10}) {
    double rmsVal = rms(frame);
    return 20 * log(rmsVal / eps) / ln10;
  }
}

/// ---------- DIGITAL FILTER ----------
class Biquad {
  double b0, b1, b2, a1, a2;
  double x1 = 0.0, x2 = 0.0; // past inputs
  double y1 = 0.0, y2 = 0.0; // past outputs

  Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  double process(double x) {
    final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;

    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;

    return y;
  }

  void reset() {
    x1 = x2 = y1 = y2 = 0.0;
  }
}

class DigitalFilter {
  final List<Biquad> stages;

  DigitalFilter(int order)
    : stages = List.generate(order, (_) => Biquad(1, 0, 0, 0, 0));

  /// Configure a specific stage (like aubio.set_biquad)
  void setBiquad(
    int stage,
    double b0,
    double b1,
    double b2,
    double a1,
    double a2,
  ) {
    if (stage < 0 || stage >= stages.length) {
      throw ArgumentError("Stage out of range");
    }
    stages[stage] = Biquad(b0, b1, b2, a1, a2);
  }

  /// Process a single sample
  double processSample(double x) {
    double y = x;
    for (final biquad in stages) {
      y = biquad.process(y);
    }
    return y;
  }

  /// Process a frame (array of samples)
  Float32List processFrame(Float32List input) {
    return Float32List.fromList(input.map(processSample).toList());
  }

  void reset() {
    for (final bq in stages) {
      bq.reset();
    }
  }
}

enum PitchUnit { midi, hz }

/// ---------- DSP CLASS ----------
class AudioDSP {
  final int fftSize;
  final int hopSize;
  final int sampleRate;
  final List<double> window; // Pitch params
  double pitchTolerance = 0.15;
  PitchUnit pitchUnit = PitchUnit.hz; // Onset state
  List<double>? prevMag; // Tempo state

  final List<int> onsetFrames = [];
  AudioDSP(this.fftSize, this.hopSize, this.sampleRate)
    : window = Window.hann(fftSize);

  /// Phase vocoder frame -> cvec
  Cvec pvoc(Float32List frame) {
    var windowed = List.generate(frame.length, (i) => frame[i] * window[i]);
    var spectrum = FFTUtils.fft(windowed);
    var cvec = Cvec(fftSize ~/ 2 + 1);
    cvec.fromSpectrum(spectrum.sublist(0, fftSize ~/ 2 + 1));
    return cvec;
  }

  /// Pitch detection (yinfft style)
  double detectPitch(List<double> frame) {
    int n = frame.length;
    var yin = List.filled(n ~/ 2, 0.0);
    for (int tau = 1; tau < n ~/ 2; tau++) {
      double sum = 0;
      for (int i = 0; i < n ~/ 2; i++) {
        double d = frame[i] - frame[i + tau];
        sum += d * d;
      }
      yin[tau] = sum;
    }
    var cmnd = List.filled(n ~/ 2, 0.0);
    cmnd[0] = 1.0;
    double runningSum = 0.0;
    int tauEstimate = -1;
    for (int tau = 1; tau < n ~/ 2; tau++) {
      runningSum += yin[tau];
      cmnd[tau] = yin[tau] * tau / (runningSum == 0 ? 1 : runningSum);
      if (tau > 2 && cmnd[tau] < pitchTolerance) {
        tauEstimate = tau;
        while (tau + 1 < n ~/ 2 && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        break;
      }
    }
    if (tauEstimate == -1) return 0.0;
    double freq = sampleRate / tauEstimate;
    return (pitchUnit == PitchUnit.midi) ? hzToMidi(freq) : freq;
  }

  static double hzToMidi(double hz) =>
      (hz > 0) ? 69 + 12 * log(hz / 440.0) / ln2 : 0.0;

  /// Onset detection (spectral flux)
  bool detectOnset(Float32List frame) {
    var cvec = pvoc(frame);
    var mags = cvec.norm;
    if (prevMag == null) {
      prevMag = mags;
      return false;
    }
    double flux = 0.0;
    for (int i = 0; i < mags.length; i++) {
      double diff = mags[i] - prevMag![i];
      if (diff > 0) flux += diff;
    }
    prevMag = mags;
    return flux > 5.0; // threshold
  }

  /// Tempo estimation (BPM from onsets)
  double estimateTempo(Float32List frame, int frameIndex) {
    if (detectOnset(frame)) onsetFrames.add(frameIndex);
    if (onsetFrames.length < 2) return 0.0;
    var intervals = <int>[];
    for (int i = 1; i < onsetFrames.length; i++) {
      intervals.add(onsetFrames[i] - onsetFrames[i - 1]);
    }
    double avgHop = intervals.reduce((a, b) => a + b) / intervals.length;
    double secPerBeat = avgHop * (fftSize / sampleRate);
    return 60.0 / secPerBeat;
  }

  /// Analyze frame: returns pitch, onset, tempo, energy, dbSPL
  Map<String, dynamic> analyzeFrame(Float32List frame, int frameIndex) {
    return {
      "pitch": detectPitch(frame),
      "onset": detectOnset(frame),
      "tempo": estimateTempo(frame, frameIndex),
      "energy": Energy.rms(frame),
      "dbSpl": Energy.dbSpl(frame),
    };
  }
}
