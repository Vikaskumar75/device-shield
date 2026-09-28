/// Runtime device-security checks for Flutter apps on Android and iOS.
///
/// ```dart
/// import 'package:device_shield/device_shield.dart';
///
/// final report = await DeviceShield.check();
/// if (report.root.detected) {
///   print(report.root.signals); // e.g. [su_binary_path (strong)]
/// }
///
/// await DeviceShield.setScreenshotProtection(true);
/// ```
library;

export 'src/device_shield.dart' show DeviceShield;
export 'src/results.dart';
