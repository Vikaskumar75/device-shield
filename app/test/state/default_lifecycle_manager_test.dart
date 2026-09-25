import 'package:device_shield/src/state/default_lifecycle_manager.dart';
import 'package:device_shield/src/state/lifecycle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingHandler implements SecurityLifecycleHandler {
  final List<String> calls = [];

  @override
  Future<void> onResume() async => calls.add('resume');
  @override
  Future<void> onInactive() async => calls.add('inactive');
  @override
  Future<void> onPause() async => calls.add('pause');
  @override
  Future<void> onDetached() async => calls.add('detached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultLifecycleManager', () {
    test('forwards each AppLifecycleState to the correct handler callback', () {
      final manager = DefaultLifecycleManager();
      final handler = _RecordingHandler();
      manager.attach(handler);

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      manager.didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(handler.calls, ['resume', 'inactive', 'pause', 'detached']);
      manager.detach();
    });

    test('detach stops forwarding to the handler', () {
      final manager = DefaultLifecycleManager();
      final handler = _RecordingHandler();
      manager.attach(handler);
      manager.detach();

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(handler.calls, isEmpty);
    });

    test('attach can be called again with a new handler after detach', () {
      final manager = DefaultLifecycleManager();
      final first = _RecordingHandler();
      final second = _RecordingHandler();
      manager.attach(first);
      manager.detach();

      manager.attach(second);
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(first.calls, isEmpty);
      expect(second.calls, ['resume']);
      manager.detach();
    });
  });
}
