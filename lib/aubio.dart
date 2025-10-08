import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'aubio_bindings.dart'; // Updated import path

/// Main aubio library class for audio analysis
///
/// This class provides access to aubio's audio analysis capabilities through
/// a high-level Dart API using FFI.
class Aubio {
  static AubioBindings? _bindings;
  static ffi.DynamicLibrary? _dylib;

  /// Initialize the aubio library
  ///
  /// This must be called before using any aubio functionality.
  /// The library will be loaded automatically based on the platform.
  static AubioBindings get bindings {
    if (_bindings != null) return _bindings!;

    _dylib = _loadLibrary();
    _bindings = AubioBindings(_dylib!);
    return _bindings!;
  }

  /// Load the native aubio library for the current platform
  static ffi.DynamicLibrary _loadLibrary() {
    var dylib = null;
    try {
      const libName = 'aubio';

      if (Platform.isMacOS || Platform.isIOS) {
        dylib = ffi.DynamicLibrary.open('lib$libName.dylib');
        print('aubio.dll loaded: $dylib');

        return dylib;
      } else if (Platform.isAndroid || Platform.isLinux) {
        dylib = ffi.DynamicLibrary.open('lib$libName.so');
        print('aubio.dll loaded: $dylib');

        return dylib;
      } else if (Platform.isWindows) {
        dylib = ffi.DynamicLibrary.open('$libName.dll');
        print('aubio.dll loaded: $dylib');
        return dylib;
      } else {
        throw UnsupportedError(
          'Unsupported platform: ${Platform.operatingSystem}',
        );
      }
    } catch (e) {
      print("dynamic library load failed error - ${e.toString()}");
    }
    return dylib;
  }

  /// Cleanup resources
  static void dispose() {
    _bindings = null;
    _dylib = null;
  }

  /// Get the version of the aubio library
  static String getVersion() {
    return '0.4.9';
  }

  static Pointer<aubio_pvoc_t> createPhaseVocoder(int windowSize, int hopSize) {
    return bindings.new_aubio_pvoc(windowSize, hopSize);
  }

  static void deletePhaseVocoder(Pointer<aubio_pvoc_t> pvoc) {
    bindings.del_aubio_pvoc(pvoc);
  }

  static int getPhaseVocoderWindowSize(Pointer<aubio_pvoc_t> pvoc) {
    return bindings.aubio_pvoc_get_win(pvoc);
  }

  static int getPhaseVocoderHopSize(Pointer<aubio_pvoc_t> pvoc) {
    return bindings.aubio_pvoc_get_win(pvoc);
  }

  static bool setPhaseVocoderWindow(
    Pointer<aubio_pvoc_t> pvoc,
    String windowType,
  ) {
    final windowPtr = windowType.toNativeUtf8();
    final result =
        bindings.aubio_pvoc_set_window(pvoc, windowPtr.cast<Char>()) == 0;
    calloc.free(windowPtr);
    return result;
  }

  // Phase vocoder analysis (time -> frequency domain)
  static Pointer<cvec_t> phaseVocoderAnalysis(
    Pointer<aubio_pvoc_t> pvoc,
    Float32List audioInput,
    int windowSize,
  ) {
    final inputVec = _createFvecFromData(audioInput);
    final fftGrain = bindings.new_cvec(windowSize);

    bindings.aubio_pvoc_do(pvoc, inputVec, fftGrain);

    bindings.del_fvec(inputVec);
    return fftGrain; // Caller must free this
  }

  // Phase vocoder synthesis (frequency -> time domain)
  static Float32List phaseVocoderSynthesis(
    Pointer<aubio_pvoc_t> pvoc,
    Pointer<cvec_t> fftGrain,
    int hopSize,
  ) {
    final outputVec = bindings.new_fvec(hopSize);

    bindings.aubio_pvoc_rdo(pvoc, fftGrain, outputVec);

    // Convert to Dart Float32List
    final result = Float32List(hopSize);
    for (int i = 0; i < hopSize; i++) {
      result[i] = bindings.fvec_get_sample(outputVec, i);
    }

    bindings.del_fvec(outputVec);
    return result;
  }

  // Extract magnitude and phase from complex vector
  static (Float32List, Float32List) extractMagnitudePhase(
    Pointer<cvec_t> fftGrain,
    int windowSize,
  ) {
    final length = (windowSize ~/ 2) + 1;
    final magnitudes = Float32List(length);
    final phases = Float32List(length);

    for (int i = 0; i < length; i++) {
      magnitudes[i] = bindings.cvec_norm_get_sample(fftGrain, i);
      phases[i] = bindings.cvec_phas_get_sample(fftGrain, i);
    }

    return (magnitudes, phases);
  }

  // Set magnitude and phase in complex vector
  static void setMagnitudePhase(
    Pointer<cvec_t> fftGrain,
    Float32List magnitudes,
    Float32List phases,
  ) {
    final length = magnitudes.length;
    for (int i = 0; i < length; i++) {
      bindings.cvec_norm_set_sample(fftGrain, magnitudes[i], i);
      bindings.cvec_norm_set_sample(fftGrain, phases[i], i);
    }
  }

  // Create and manage complex vectors
  static Pointer<cvec_t> createComplexVector(int length) {
    return bindings.new_cvec(length);
  }

  static void deleteComplexVector(Pointer<cvec_t> cvec) {
    bindings.del_cvec(cvec);
  }

  // Onset detection functionality
  static Pointer<aubio_onset_t> createOnset(
    String method,
    int bufSize,
    int hopSize,
    int sampleRate,
  ) {
    final methodPtr = method.toNativeUtf8();
    final onset = bindings.new_aubio_onset(
      methodPtr.cast<Char>(),
      bufSize,
      hopSize,
      sampleRate,
    );
    calloc.free(methodPtr);
    return onset;
  }

  static void deleteOnset(Pointer<aubio_onset_t> onset) {
    bindings.del_aubio_onset(onset);
  }

  static double detectOnset(
    Pointer<aubio_onset_t> onset,
    Float32List audioData,
  ) {
    final inputVec = _createFvecFromData(audioData);
    final outputVec = bindings.new_fvec(1);

    bindings.aubio_onset_do(onset, inputVec, outputVec);
    final result = bindings.fvec_get_sample(outputVec, 0);

    bindings.del_fvec(inputVec);
    bindings.del_fvec(outputVec);

    return result;
  }

  // Pitch detection functionality
  static Pointer<aubio_pitch_t> createPitch(
    String method,
    int bufSize,
    int hopSize,
    int sampleRate,
  ) {
    final methodPtr = method.toNativeUtf8();
    final pitch = bindings.new_aubio_pitch(
      methodPtr.cast<Char>(),
      bufSize,
      hopSize,
      sampleRate,
    );
    calloc.free(methodPtr);
    return pitch;
  }

  static void deletePitch(Pointer<aubio_pitch_t> pitch) {
    bindings.del_aubio_pitch(pitch);
  }

  static double detectPitch(
    Pointer<aubio_pitch_t> pitch,
    Float32List audioData,
  ) {
    final inputVec = _createFvecFromData(audioData);
    final outputVec = bindings.new_fvec(1);

    bindings.aubio_pitch_do(pitch, inputVec, outputVec);
    final result = bindings.fvec_get_sample(outputVec, 0);

    bindings.del_fvec(inputVec);
    bindings.del_fvec(outputVec);

    return result;
  }

  // Helper method to create fvec from Flutter data
  static Pointer<fvec_t> _createFvecFromData(Float32List data) {
    final vec = bindings.new_fvec(data.length);

    for (int i = 0; i < data.length; i++) {
      bindings.fvec_set_sample(vec, data[i], i);
    }

    return vec;
  }
}
