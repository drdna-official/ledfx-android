import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/ui/adaptive_layout.dart';

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
