import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

String _buildMode() {
  if (kReleaseMode) return 'release';
  if (kProfileMode) return 'profile';
  return 'debug';
}

/// Raw platform/runtime facts — every value here comes from `dart:io`,
/// `dart:ffi`, or `package:flutter/foundation.dart` directly, never
/// invented. Useful when filing a bug report against either the SDK or
/// this example app.
class DebugInfoScreen extends StatelessWidget {
  const DebugInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SectionCard(
              title: 'Platform',
              children: [
                StatusRow(
                  label: 'Operating system',
                  value: Platform.operatingSystem,
                ),
                StatusRow(
                  label: 'OS version',
                  value: Platform.operatingSystemVersion,
                ),
                StatusRow(
                  label: 'Reported platform version',
                  value: controller.platformVersion,
                ),
                StatusRow(label: 'Locale', value: Platform.localeName),
              ],
            ),
            SectionCard(
              title: 'Runtime',
              children: [
                StatusRow(label: 'Dart version', value: Platform.version),
                StatusRow(label: 'Build mode', value: _buildMode()),
                StatusRow(
                  label: 'Architecture (ABI)',
                  value: Abi.current().toString(),
                ),
                StatusRow(
                  label: 'Number of processors',
                  value: '${Platform.numberOfProcessors}',
                ),
              ],
            ),
            SectionCard(
              title: 'SDK',
              children: [
                StatusRow(label: 'SDK state', value: controller.status.name),
                const StatusRow(label: 'Package version', value: '0.0.1'),
              ],
            ),
          ],
        );
      },
    );
  }
}
