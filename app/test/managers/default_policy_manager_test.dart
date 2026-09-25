import 'package:flutter_shield/src/core/console_logger.dart';
import 'package:flutter_shield/src/managers/default_policy_manager.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/security_action.dart';
import 'package:flutter_shield/src/registry/rule.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRule implements Rule {
  _FakeRule(
    this.id, {
    required this.action,
    this.priority = 0,
    this.matcher,
    this.throwsOnMatch = false,
  });

  @override
  final String id;
  @override
  final SecurityAction action;
  @override
  final int priority;
  final bool Function(DetectionResult)? matcher;
  final bool throwsOnMatch;

  @override
  bool matches(DetectionResult result) {
    if (throwsOnMatch) throw Exception('boom');
    return matcher?.call(result) ?? false;
  }
}

DetectionResult _result({String type = 'x', bool detected = true, double confidence = 0.9}) {
  return DetectionResult(
    type: type,
    detected: detected,
    confidence: confidence,
    timestamp: DateTime.now(),
  );
}

void main() {
  group('DefaultPolicyManager — coordination only, no rule content', () {
    test('evaluate returns the placeholder ignore action with no rules registered', () async {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());

      final action = await manager.evaluate(_result());

      expect(action, SecurityAction.ignore);
    });

    test('evaluate returns the first matching rule\'s action, in priority order', () async {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());
      await manager.addRule(_FakeRule('low-priority',
          action: SecurityAction.terminate,
          priority: 10,
          matcher: (r) => true));
      await manager.addRule(_FakeRule('high-priority',
          action: SecurityAction.warn, priority: 1, matcher: (r) => true));

      final action = await manager.evaluate(_result());

      expect(action, SecurityAction.warn);
    });

    test('a rule that does not match is skipped', () async {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());
      await manager.addRule(_FakeRule('never',
          action: SecurityAction.terminate, matcher: (r) => false));

      final action = await manager.evaluate(_result());

      expect(action, SecurityAction.ignore);
    });

    test('a rule that throws is treated as no-match and does not block others', () async {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());
      await manager.addRule(_FakeRule('broken',
          action: SecurityAction.terminate, priority: 0, throwsOnMatch: true));
      await manager.addRule(_FakeRule('fallback',
          action: SecurityAction.warn, priority: 1, matcher: (r) => true));

      final action = await manager.evaluate(_result());

      expect(action, SecurityAction.warn);
    });

    test('removeRule excludes it from subsequent evaluation', () async {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());
      await manager.addRule(_FakeRule('r1',
          action: SecurityAction.block, matcher: (r) => true));

      await manager.removeRule('r1');
      final action = await manager.evaluate(_result());

      expect(action, SecurityAction.ignore);
    });

    test('executeAction does not throw (placeholder execution)', () async {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());
      await expectLater(
        manager.executeAction(SecurityAction.warn, _result()),
        completes,
      );
    });

    test('calculateRiskScore averages confidence across detected results only', () {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());

      final score = manager.calculateRiskScore([
        _result(detected: true, confidence: 0.8),
        _result(detected: true, confidence: 0.4),
        _result(detected: false, confidence: 0.9),
      ]);

      expect(score, closeTo(0.6, 0.0001));
    });

    test('calculateRiskScore returns 0.0 when nothing was detected', () {
      final manager = DefaultPolicyManager(logger: ConsoleLogger());
      final score = manager
          .calculateRiskScore([_result(detected: false), _result(detected: false)]);
      expect(score, 0.0);
    });
  });
}
