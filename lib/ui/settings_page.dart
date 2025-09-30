import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ledfx/audio_bridge.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ledfx/visualizer/visualizer_painter.dart';
import 'package:ledfx/visualizer/visualizer_service.dart';

Future<bool> requestNotificationPermission() async {
  if (await Permission.notification.isGranted) return true;
  final status = await Permission.notification.request();
  return status.isGranted;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool running = false;
  bool paused = false;
  String? errorMsg;
  late StreamSubscription<RecordingEvent> sub;
  List<AudioDevice>? devices;
  // Configure three bands with your desired colors.
  final bands = <BandConfig>[
    BandConfig(
      name: 'bass',
      fLow: 20,
      fHigh: 40,
      color: const Rgb(255, 0, 0),
    ), // red-orange
    BandConfig(
      name: 'mid',
      fLow: 100,
      fHigh: 2000,
      color: const Rgb(0, 255, 0),
    ), // cyan
    BandConfig(
      name: 'treble',
      fLow: 100,
      fHigh: 2000,
      color: const Rgb(0, 0, 255),
    ), // violet
  ];

  final cfg = VisualConfig(
    totalLeds: 150,
    minLen: 4,
    maxLen: 42,
    masterBrightness: 1.0,
    crossfadeLeds: 20,
    windowSize: 735, // ~23ms @ 44.1k
    hopSize: 2048, // 50% overlap
    sampleRate: 44100, // must match your native stream
    attackTime: 0.02, // fast rise
    decayTime: 5.0, // gentle fall
    probesPerBand: 6,
    noiseFloor: 0.02,
    softKnee: 0.35,
  );

  @override
  void initState() {
    super.initState();
    sub = AudioBridge.instance.events.listen((event) async {
      switch (event) {
        case StateEvent(:final state):
          switch (state) {
            case "recordingStarted":
              setState(() {
                running = true;
                paused = false;
              });
              break;
            case "recordingPaused":
              setState(() {
                paused = true;
              });
              break;
            case "recordingResumed":
              setState(() {
                paused = false;
              });
              break;
            case "recordingStopped":
              setState(() {
                running = false;
                paused = false;
              });

              break;
          }
          break;

        case ErrorEvent(:final message):
          setState(() {
            errorMsg = message;
            // show snackbar outside setState to avoid rebuild issues
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("Error: $message")));
            });
          });
          break;

        case AudioEvent(:final data):
          await VisualizerService.instance.stop();
          // Process chunks
          VisualizerService.instance.processChunk(
            AudioVisualizerProcessor(bands: bands, cfg: cfg),
            data,
          );
          break;
        case DevicesInfoEvent(:final outputDevices, :final inputDevices):
          setState(() {
            devices ??= [];
            devices!.addAll([...outputDevices, ...inputDevices]);
            devices!.toSet();
          });
          break;
      }
    });

    if (devices == null) {
      AudioBridge.instance.getDevices();
    }
  }

  @override
  void dispose() async {
    await _stop();
    sub.cancel();
    super.dispose();
  }

  Future<void> _requestAndStart() async {
    final p = await Permission.microphone.request();
    if (!p.isGranted) return;

    final notif = await requestNotificationPermission();
    if (!notif) return;

    final ok = await AudioBridge.instance.requestProjection();
    if (!ok) return;

    final started = await AudioBridge.instance.start();
    if (started == null || !started) return;
  }

  Future<void> _stop() async {
    VisualizerService.instance.stop();
    await AudioBridge.instance.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Audio Visualizer")),
      body: Column(
        children: [
          Text(devices?.first.name ?? ""),
          ElevatedButton(
            onPressed: () async {
              await AudioBridge.instance.getDevices();
            },
            child: Text("device get"),
          ),
          ElevatedButton(
            onPressed: () async {
              await AudioBridge.instance.start({
                "deviceId": devices?.first.id,
                "captureType": "systemAudio",
              });
            },
            child: Text("Test"),
          ),
          ElevatedButton(
            onPressed: running ? _stop : _requestAndStart,
            child: Text(running ? "Stop" : "Start"),
          ),
          if (running)
            ElevatedButton(
              onPressed: paused
                  ? AudioBridge.instance.resume
                  : AudioBridge.instance.pause,
              child: Text(paused ? "Resume" : "Pause"),
            ),
          if (errorMsg != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "⚠️ $errorMsg",
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: Center(
              child: ValueListenableBuilder<List<int>>(
                valueListenable: VisualizerService.instance.rgb,
                builder: (_, rgb, __) {
                  return CustomPaint(
                    painter: VisualizerPainter(
                      rgb: rgb,
                      ledCount: VisualizerService.instance.ledCount,
                    ),
                    size: const Size(double.infinity, 200),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
