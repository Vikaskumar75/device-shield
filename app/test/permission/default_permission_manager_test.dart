import 'package:device_shield/src/permission/default_permission_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultPermissionManager — construction defaults', () {
    test('requiredPermissions defaults to empty', () {
      final manager = DefaultPermissionManager();
      expect(manager.requiredPermissions, isEmpty);
    });
  });

  group('DefaultPermissionManager — initialize / requestPermissions '
      '(empty set)', () {
    test(
      'initialize trivially succeeds when no permissions are required',
      () async {
        final manager = DefaultPermissionManager();
        await expectLater(manager.initialize(), completes);
      },
    );

    test(
      'requestPermissions with an empty set completes without throwing',
      () async {
        final manager = DefaultPermissionManager();
        await expectLater(manager.requestPermissions({}), completes);
      },
    );

    test('grantedPermissions is empty after an empty request', () async {
      final manager = DefaultPermissionManager();
      await manager.initialize();
      expect(manager.grantedPermissions, isEmpty);
    });

    test(
      'isGranted is false for any permission when nothing was requested',
      () async {
        final manager = DefaultPermissionManager();
        await manager.initialize();
        expect(manager.isGranted('camera'), isFalse);
      },
    );
  });

  group('DefaultPermissionManager — a non-empty request is honestly '
      'unimplemented, never silently auto-granted', () {
    test('requestPermissions with a non-empty set throws '
        'UnimplementedError', () async {
      final manager = DefaultPermissionManager(requiredPermissions: {'camera'});

      await expectLater(
        manager.requestPermissions({'camera'}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('initialize with a non-empty requiredPermissions set throws '
        'the same way', () async {
      final manager = DefaultPermissionManager(
        requiredPermissions: {'location'},
      );

      await expectLater(
        manager.initialize(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('a denied/unavailable permission is never reflected in '
        'grantedPermissions', () async {
      final manager = DefaultPermissionManager(requiredPermissions: {'camera'});

      await expectLater(manager.initialize(), throwsA(anything));
      expect(manager.grantedPermissions, isEmpty);
      expect(manager.isGranted('camera'), isFalse);
    });
  });

  group('DefaultPermissionManager — dispose', () {
    test('dispose clears granted permissions and is safe to call even '
        'with none granted', () async {
      final manager = DefaultPermissionManager();
      await manager.initialize();

      await expectLater(manager.dispose(), completes);
      expect(manager.grantedPermissions, isEmpty);
    });
  });
}
