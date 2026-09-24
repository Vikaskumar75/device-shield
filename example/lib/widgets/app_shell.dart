import 'package:flutter/material.dart';

import '../screens/about_screen.dart';
import '../screens/callbacks_screen.dart';
import '../screens/debug_info_screen.dart';
import '../screens/detectors_screen.dart';
import '../screens/error_screen.dart';
import '../screens/events_screen.dart';
import '../screens/health_monitor_screen.dart';
import '../screens/home_screen.dart';
import '../screens/logs_screen.dart';
import '../screens/manual_test_screen.dart';
import '../screens/protection_screen.dart';
import '../screens/recording_demo_screen.dart';
import '../screens/runtime_controls_screen.dart';
import '../screens/screenshot_demo_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/statistics_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
}

final List<_Destination> _destinations = [
  _Destination('Home', Icons.home_outlined, Icons.home, (_) => const HomeScreen()),
  _Destination('Runtime Controls', Icons.tune_outlined, Icons.tune,
      (_) => const RuntimeControlsScreen()),
  _Destination('Settings', Icons.settings_outlined, Icons.settings,
      (_) => const SettingsScreen()),
  _Destination('Events', Icons.event_note_outlined, Icons.event_note,
      (_) => const EventsScreen()),
  _Destination('Callbacks', Icons.link_outlined, Icons.link,
      (_) => const CallbacksScreen()),
  _Destination('Detectors', Icons.radar_outlined, Icons.radar,
      (_) => const DetectorsScreen()),
  _Destination('Screenshot Demo', Icons.screenshot_outlined,
      Icons.screenshot, (_) => const ScreenshotDemoScreen()),
  _Destination('Recording Demo', Icons.fiber_smart_record_outlined,
      Icons.fiber_smart_record, (_) => const RecordingDemoScreen()),
  _Destination('Protection', Icons.shield_outlined, Icons.shield,
      (_) => const ProtectionScreen()),
  _Destination('Statistics', Icons.bar_chart_outlined, Icons.bar_chart,
      (_) => const StatisticsScreen()),
  _Destination('Logs', Icons.article_outlined, Icons.article,
      (_) => const LogsScreen()),
  _Destination('Errors', Icons.error_outline, Icons.error,
      (_) => const ErrorScreen()),
  _Destination('Manual Test', Icons.checklist_outlined, Icons.checklist,
      (_) => const ManualTestScreen()),
  _Destination('Health Monitor', Icons.monitor_heart_outlined,
      Icons.monitor_heart, (_) => const HealthMonitorScreen()),
  _Destination('Debug Info', Icons.bug_report_outlined, Icons.bug_report,
      (_) => const DebugInfoScreen()),
  _Destination('About', Icons.info_outline, Icons.info,
      (_) => const AboutScreen()),
];

/// The app's single navigation shell. Responsive: a permanent
/// [NavigationRail] on wide (tablet/desktop) layouts, a [Drawer] on
/// narrow (phone) layouts — one clean structure covering both, per the
/// "any clean structure is acceptable" requirement, without duplicating
/// the destination list.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final destination = _destinations[_index];
    final isWide = MediaQuery.sizeOf(context).width >= 840;

    final body = Builder(builder: (context) => destination.builder(context));

    if (isWide) {
      return Scaffold(
        appBar: AppBar(title: Text(destination.label)),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(destination.label)),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.shield, size: 40),
                  SizedBox(height: 8),
                  Text('FlutterShield',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('Reference example app'),
                ],
              ),
            ),
            for (var i = 0; i < _destinations.length; i++)
              ListTile(
                leading: Icon(
                    i == _index ? _destinations[i].selectedIcon : _destinations[i].icon),
                title: Text(_destinations[i].label),
                selected: i == _index,
                onTap: () {
                  setState(() => _index = i);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
      body: body,
    );
  }
}
