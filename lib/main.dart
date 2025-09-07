import 'package:flutter/material.dart';
import 'ui/settings_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Visualizer',
      theme: ThemeData.dark(),
      home: const SettingsPage(),
    );
  }
}
