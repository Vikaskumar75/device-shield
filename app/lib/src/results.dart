import 'signal_strengths.dart';

/// The device check a [CheckResult] belongs to.
enum CheckType {
  /// Root access on Android.
  root,

  /// A jailbroken iOS device.
  jailbreak,

  /// An Android emulator or the iOS Simulator.
  emulator,

  /// An attached debugger.
  debugger,

  /// A mocked (fake) location.
  mockLocation,
}

/// The outcome of a single check.
enum CheckStatus {
  /// Enough evidence fired to treat the device as affected. See
  /// [CheckResult.detected] for the rule.
  detected,

  /// The check ran and found too little evidence. [CheckResult.signals] may
  /// still list weak signals.
  clear,

  /// The check doesn't exist on this platform, such as root detection on iOS.
  notApplicable,

  /// The check couldn't run (timeout, platform error, unsupported platform).
  /// This is not a clean result.
  failed,
}

/// How much a signal says about the device on its own.
enum SignalStrength {
  /// Rarely seen on unmodified devices. One is enough to detect.
  strong,

  /// Suggestive. Two together are enough to detect.
  medium,

  /// Common on legitimate devices (custom ROMs, debug builds). Reported, but
  /// never decides the result.
  weak,
}

/// One piece of evidence a check found, such as `su_binary_path`.
class Signal {
  /// Creates a signal. Normally created by the SDK, not by apps.
  const Signal(this.id, this.strength);

  /// Stable identifier. The full list is on the docs site's signals page.
  final String id;

  /// How much this signal counts towards [CheckStatus.detected].
  final SignalStrength strength;

  @override
  bool operator ==(Object other) =>
      other is Signal && other.id == id && other.strength == strength;

  @override
  int get hashCode => Object.hash(id, strength);

  @override
  String toString() => '$id (${strength.name})';
}

/// The result of one device check.
class CheckResult {
  /// Creates a result. Normally created by the SDK, not by apps.
  const CheckResult({
    required this.type,
    required this.status,
    this.signals = const [],
    this.error,
  });

  /// Builds a result from the signal ids a native check reported, applying
  /// the detection rule described on [detected].
  factory CheckResult.fromSignalIds(CheckType type, Iterable<String> ids) {
    final signals = [for (final id in ids) Signal(id, strengthOf(id))];
    return CheckResult(
      type: type,
      status: statusFor(signals),
      signals: signals,
    );
  }

  /// Which check this is.
  final CheckType type;

  /// Whether the check found the device affected, clear, not applicable or
  /// couldn't run.
  final CheckStatus status;

  /// Every signal that fired, including weak ones that didn't affect
  /// [status].
  final List<Signal> signals;

  /// Why the check failed, when [status] is [CheckStatus.failed].
  final String? error;

  /// Whether the check detected the condition: at least one strong signal,
  /// or at least two medium ones. Weak signals alone never count.
  bool get detected => status == CheckStatus.detected;

  @override
  String toString() =>
      'CheckResult(${type.name}: ${status.name}'
      '${signals.isEmpty ? '' : ', $signals'}'
      '${error == null ? '' : ', error: $error'})';
}

/// The mock-location check's result, with what the check could observe.
class MockLocationResult extends CheckResult {
  /// Creates a result. Normally created by the SDK, not by apps.
  const MockLocationResult({
    required super.status,
    super.signals,
    super.error,
    this.locationPermissionGranted = false,
    this.locationAvailable = false,
  }) : super(type: CheckType.mockLocation);

  /// Whether your app holds location permission. Without it, only signals
  /// that don't need a location can fire. The SDK never requests it.
  final bool locationPermissionGranted;

  /// Whether a recent location was available to inspect.
  final bool locationAvailable;
}

/// The results of every device check, from `DeviceShield.check()`.
class SecurityReport {
  /// Creates a report. Normally created by the SDK, not by apps.
  const SecurityReport({
    required this.root,
    required this.jailbreak,
    required this.emulator,
    required this.debugger,
    required this.mockLocation,
  });

  /// Root detection (Android; not applicable on iOS).
  final CheckResult root;

  /// Jailbreak detection (iOS; not applicable on Android).
  final CheckResult jailbreak;

  /// Emulator or simulator detection.
  final CheckResult emulator;

  /// Debugger detection.
  final CheckResult debugger;

  /// Mock location detection.
  final MockLocationResult mockLocation;

  /// Every result in this report.
  List<CheckResult> get all => [
    root,
    jailbreak,
    emulator,
    debugger,
    mockLocation,
  ];

  /// The results with [CheckStatus.detected].
  List<CheckResult> get detections => all.where((r) => r.detected).toList();

  /// Whether any check detected its condition.
  bool get anyDetected => all.any((r) => r.detected);

  /// Whether any check failed to run. Treat the report as incomplete.
  bool get anyFailed => all.any((r) => r.status == CheckStatus.failed);
}

/// The outcome of turning a screen protection on or off.
enum ProtectionResult {
  /// The platform confirmed the change is in effect.
  applied,

  /// This protection isn't available on this platform.
  unsupported,

  /// The change couldn't be made, for example because no activity or window
  /// exists yet. Try again once your UI is showing.
  failed,
}
