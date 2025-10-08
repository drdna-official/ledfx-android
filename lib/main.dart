import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ledfx/aubio.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/ui/adaptive_layout.dart';

void main() {
  runApp(const MyApp());

  // Phase vocoder parameters
  final int windowSize = 1024;
  final int hopSize = 256;

  // Create phase vocoder
  final pvoc = Aubio.createPhaseVocoder(windowSize, hopSize);

  // Set window type (options: hanning, hamming, hanningz, blackman, etc.)
  Aubio.setPhaseVocoderWindow(pvoc, 'hanning');

  print('Phase Vocoder created:');
  print('Window size: ${Aubio.getPhaseVocoderWindowSize(pvoc)}');
  print('Hop size: ${Aubio.getPhaseVocoderHopSize(pvoc)}');

  // Generate example audio signal (sine wave)
  final audioInput = Float32List(hopSize);
  for (int i = 0; i < hopSize; i++) {
    audioInput[i] = sin(2 * pi * 440 * i / 44100); // 440 Hz sine wave
  }

  // Analysis: Convert time domain to frequency domain
  final fftGrain = Aubio.phaseVocoderAnalysis(pvoc, audioInput, windowSize);

  // Extract magnitude and phase spectra
  final (magnitudes, phases) = Aubio.extractMagnitudePhase(
    fftGrain,
    windowSize,
  );

  print('\nSpectral Analysis:');
  print('Number of frequency bins: ${magnitudes.length}');
  print('Peak magnitude: ${magnitudes.reduce(max)}');

  // Spectral manipulation example: Scale magnitudes
  final modifiedMagnitudes = Float32List(magnitudes.length);
  for (int i = 0; i < magnitudes.length; i++) {
    modifiedMagnitudes[i] = magnitudes[i] * 0.5; // Reduce amplitude by half
  }

  // Set modified spectra back to complex vector
  Aubio.setMagnitudePhase(fftGrain, modifiedMagnitudes, phases);

  // Synthesis: Convert frequency domain back to time domain
  final synthesized = Aubio.phaseVocoderSynthesis(pvoc, fftGrain, hopSize);

  print('\nSynthesis completed:');
  print('Output samples: ${synthesized.length}');
  print(
    'Output RMS: ${sqrt(synthesized.map((x) => x * x).reduce((a, b) => a + b) / synthesized.length)}',
  );

  // Cleanup
  Aubio.deleteComplexVector(fftGrain);
  Aubio.deletePhaseVocoder(pvoc);

  // Example: Real-time spectral processing loop
  demonstrateSpectralProcessingLoop();
}

void demonstrateSpectralProcessingLoop() {
  final int windowSize = 1024;
  final int hopSize = 256;
  final int sampleRate = 44100;

  print('\n--- Spectral Processing Loop Example ---');

  // Create phase vocoder for real-time processing
  final pvoc = Aubio.createPhaseVocoder(windowSize, hopSize);
  Aubio.setPhaseVocoderWindow(pvoc, 'hanning');

  // Simulate multiple audio blocks
  for (int block = 0; block < 10; block++) {
    // Generate audio block (simulated microphone input)
    final audioBlock = Float32List(hopSize);
    for (int i = 0; i < hopSize; i++) {
      // Mix of frequencies for demonstration
      audioBlock[i] =
          sin(2 * pi * 440 * (block * hopSize + i) / sampleRate) * 0.5 +
          sin(2 * pi * 880 * (block * hopSize + i) / sampleRate) * 0.3;
    }

    // Analysis
    final fftGrain = Aubio.phaseVocoderAnalysis(pvoc, audioBlock, windowSize);

    // Get spectral data
    final (mags, phases) = Aubio.extractMagnitudePhase(fftGrain, windowSize);

    // Find peak frequency bin
    double maxMag = 0;
    int peakBin = 0;
    for (int i = 0; i < mags.length; i++) {
      if (mags[i] > maxMag) {
        maxMag = mags[i];
        peakBin = i;
      }
    }

    final peakFrequency = (peakBin * sampleRate) / windowSize;

    // Apply spectral effect: High-pass filter
    final filteredMags = Float32List(mags.length);
    final cutoffBin = (500 * windowSize) ~/ sampleRate; // 500 Hz cutoff
    for (int i = 0; i < mags.length; i++) {
      filteredMags[i] = i < cutoffBin ? 0 : mags[i];
    }

    // Set modified spectrum
    Aubio.setMagnitudePhase(fftGrain, filteredMags, phases);

    // Synthesis
    final processed = Aubio.phaseVocoderSynthesis(pvoc, fftGrain, hopSize);

    print(
      'Block $block: Peak at ${peakFrequency.toStringAsFixed(1)} Hz, '
      'Processed ${processed.length} samples',
    );

    // Cleanup complex vector for this block
    Aubio.deleteComplexVector(fftGrain);
  }

  // Final cleanup
  Aubio.deletePhaseVocoder(pvoc);
  print('Spectral processing loop completed');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late LEDFx ledfx;
  @override
  void initState() {
    super.initState();
    ledfx = LEDFx(config: LEDFxConfig());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Visualizer',
      theme: ThemeData.dark(),
      // home: const SettingsPage(),
      home: Scaffold(
        body: Center(
          child: FutureBuilder(
            future: ledfx.start(),
            builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      Text('Starting LEDFx'),
                    ],
                  ),
                );
              } else if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              } else if (snapshot.connectionState == ConnectionState.done) {
                return AdaptiveNavigationLayout(ledfx: ledfx);

                // Center(
                //   child:

                //   CustomScrollView(
                //     slivers: <Widget>[
                //       SliverPersistentHeader(
                //         pinned: true, // Make it sticky/pinned
                //         delegate: AutoSizeStickyHeaderDelegate(
                //           // The sticky header will always be this height
                //           minHeight: fixedHeaderHeight,
                //           // And will not expand beyond this height
                //           maxHeight: fixedHeaderHeight,
                //           child: _buildStickyContent(),
                //         ),
                //       ),
                //       SliverList(
                //         delegate: SliverChildBuilderDelegate(
                //           (BuildContext context, int index) {
                //             // Build a ListTile for each item
                //             return ListTile(
                //               leading: CircleAvatar(
                //                 child: Text('${index + 1}'),
                //               ),
                //               title: Text('List Item $index'),
                //               subtitle: const Text(
                //                 'This section is scrollable.',
                //               ),
                //             );
                //           },
                //           // The total number of list items to generate
                //           childCount: 50,
                //         ),
                //       ),
                //     ],
                //   ),

                // );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
