import 'package:flutter/material.dart';

import 'core/shield_controller.dart';
import 'core/shield_scope.dart';
import 'widgets/app_shell.dart';

/// Root widget: owns the single [ShieldController] for the app's lifetime,
/// exposes it via [ShieldScope], and sets up Material 3 theming with
/// light/dark support (the platform's own brightness, matching the
/// "adaptive" / "dark mode" / "light mode" requirements without a manual
/// theme-switcher widget the SDK itself has no bearing on).
class FlutterShieldExampleApp extends StatefulWidget {
  const FlutterShieldExampleApp({super.key});

  @override
  State<FlutterShieldExampleApp> createState() =>
      _FlutterShieldExampleAppState();
}

class _FlutterShieldExampleAppState extends State<FlutterShieldExampleApp> {
  late final ShieldController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShieldController();
    _controller.loadPlatformVersion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShieldScope(
      controller: _controller,
      child: MaterialApp(
        title: 'FlutterShield Example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const AppShell(),
      ),
    );
  }
}
