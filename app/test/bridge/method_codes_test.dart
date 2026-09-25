import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MethodCodes', () {
    test('checkEmulator has its established value', () {
      expect(MethodCodes.checkEmulator, 'checkEmulator');
    });

    test('checkDebugger has its established value', () {
      expect(MethodCodes.checkDebugger, 'checkDebugger');
    });

    test('setScreenshotProtection has the expected value', () {
      expect(MethodCodes.setScreenshotProtection, 'setScreenshotProtection');
    });

    test('isScreenCaptureActive has the expected value', () {
      expect(MethodCodes.isScreenCaptureActive, 'isScreenCaptureActive');
    });

    test('every method-name constant is unique — no two features can '
        'accidentally collide on the same native method name', () {
      const values = [
        MethodCodes.checkEmulator,
        MethodCodes.checkDebugger,
        MethodCodes.setScreenshotProtection,
        MethodCodes.isScreenCaptureActive,
      ];
      expect(values.toSet(), hasLength(values.length));
    });
  });
}
