import 'package:device_shield_example/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('device_shield/native_bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'checkRoot' => {
          'signals': ['su_binary_path'],
          'applicable': true,
        },
        'checkJailbreak' => {'signals': <String>[], 'applicable': false},
        'checkMockLocation' => {
          'signals': <String>[],
          'applicable': true,
          'permissionGranted': false,
        },
        'isScreenCaptureActive' => {'isCaptured': false, 'supported': false},
        'setScreenshotProtection' => {'applied': true},
        _ => {'signals': <String>[]},
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// A viewport tall enough to build the whole (lazy) list.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows each check with its status and signals', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Detected'), findsOneWidget);
    expect(find.text('su_binary_path · strong'), findsOneWidget);
    expect(find.text('Not applicable'), findsOneWidget);
    expect(
      find.text('No location permission: location signals skipped'),
      findsOneWidget,
    );
    expect(find.text('Unknown on this platform'), findsOneWidget);
  });

  testWidgets('turning on screenshot protection logs the result', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Screenshot protection'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Screenshot protection on: applied'),
      findsOneWidget,
    );
  });
}
