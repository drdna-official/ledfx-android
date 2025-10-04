import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'ui/settings_page.dart';

void main() {
  runApp(const MyApp());
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
    ledfx.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Visualizer',
      theme: ThemeData.dark(),
      // home: const SettingsPage(),
      home: Center(
        child: ElevatedButton(
          onPressed: () {
            print(ledfx.config.devices.toString());
            print(ledfx.config.virtuals.toString());
          },
          child: Text("press me"),
        ),
      ),
    );
  }
}
