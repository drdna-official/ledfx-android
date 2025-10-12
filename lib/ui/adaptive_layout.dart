import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/ui/home_body.dart';

// Recommended Material Design Breakpoints
const double kMediumBreakpoint = 600.0;
const double kExpandedBreakpoint = 840.0;

class AdaptiveNavigationLayout extends StatelessWidget {
  final LEDFx ledfx;
  const AdaptiveNavigationLayout({super.key, required this.ledfx});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        if (width < kMediumBreakpoint) {
          // 1. COMPACT (Mobile) View: Uses Drawer and shows the hamburger icon
          return Scaffold(
            appBar: AppBar(
              title: const Text('Compact View (Drawer)'),
              // Hamburger icon is automatically shown because 'drawer' is present
            ),
            drawer: const AppNavigationDrawer(),
            body: CompactLayout(ledfx: ledfx),
          );
        } else if (width < kExpandedBreakpoint) {
          // 2. MEDIUM (Tablet) View: Uses Navigation Rail, NO Drawer needed.
          return Scaffold(
            appBar: AppBar(
              title: const Text('Medium View (Nav Rail)'),
              // Since 'drawer' is null, NO hamburger icon is shown
            ),
            // Explicitly set drawer to null
            drawer: null,
            body: MediumLayout(ledfx: ledfx),
          );
        } else {
          // 3. EXPANDED (Desktop) View: Uses Permanent Sidebar, NO Drawer needed.
          return Scaffold(
            appBar: AppBar(
              title: const Text('Expanded View (Sidebar)'),
              // Since 'drawer' is null, NO hamburger icon is shown
            ),
            // Explicitly set drawer to null
            drawer: null,
            body: ExpandedLayout(ledfx: ledfx),
          );
        }
      },
    );
  }
}

class CompactLayout extends StatelessWidget {
  final LEDFx ledfx;
  const CompactLayout({super.key, required this.ledfx});

  @override
  Widget build(BuildContext context) {
    return HomeBody(ledfx: ledfx);
  }
}

class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: const [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.red),
            child: Text(
              'LEDFx',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.devices_other_rounded),
            title: Text('Devices'),
          ),
          ListTile(leading: Icon(Icons.send), title: Text('Sent')),
        ],
      ),
    );
  }
}

class MediumLayout extends StatefulWidget {
  final LEDFx ledfx;
  const MediumLayout({super.key, required this.ledfx});

  @override
  State<MediumLayout> createState() => _MediumLayoutState();
}

class _MediumLayoutState extends State<MediumLayout> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Navigation Rail
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          labelType: NavigationRailLabelType.all,

          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: Text('Home'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: Text('Likes'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: Text('Settings'),
            ),
          ],
        ),

        // Main Content
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: HomeBody(ledfx: widget.ledfx)),
      ],
    );
  }
}

class ExpandedLayout extends StatelessWidget {
  final LEDFx ledfx;
  const ExpandedLayout({super.key, required this.ledfx});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Permanent Navigation Sidebar (Wider, custom widget)
        SizedBox(
          width: 250, // Dedicated wider space for the sidebar
          child: ListView(
            padding: EdgeInsets.zero,
            children: const [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Permanent Navigation',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(Icons.dashboard),
                title: Text('Dashboard'),
              ),
              ListTile(
                leading: Icon(Icons.analytics),
                title: Text('Analytics'),
              ),
              ListTile(leading: Icon(Icons.message), title: Text('Messages')),
            ],
          ),
        ),

        const VerticalDivider(thickness: 1, width: 1),

        // Main Content
        Expanded(child: HomeBody(ledfx: ledfx)),
      ],
    );
  }
}
