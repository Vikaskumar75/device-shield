import 'package:flutter_shield/src/managers/detection_cache.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionResult _result(String type, {bool detected = false}) =>
    DetectionResult(
      type: type,
      detected: detected,
      confidence: detected ? 0.9 : 0.0,
      timestamp: DateTime.now(),
    );

void main() {
  group('DetectionCache — put/get/remove/clear', () {
    test('get returns null for a key that was never put', () {
      final cache = DetectionCache();
      expect(cache.get('alpha'), isNull);
    });

    test('put then get returns the stored result', () {
      final cache = DetectionCache();
      final result = _result('alpha');

      cache.put('alpha', result);

      expect(cache.get('alpha'), same(result));
    });

    test('put replaces a previous entry for the same key', () {
      final cache = DetectionCache();
      cache.put('alpha', _result('alpha'));
      final replacement = _result('alpha', detected: true);

      cache.put('alpha', replacement);

      expect(cache.get('alpha'), same(replacement));
    });

    test('remove deletes the entry for that key only', () {
      final cache = DetectionCache();
      cache.put('alpha', _result('alpha'));
      cache.put('beta', _result('beta'));

      cache.remove('alpha');

      expect(cache.get('alpha'), isNull);
      expect(cache.get('beta'), isNotNull);
    });

    test('remove is safe to call for a key that was never put', () {
      final cache = DetectionCache();
      expect(() => cache.remove('nonexistent'), returnsNormally);
    });

    test('clear removes every entry', () {
      final cache = DetectionCache();
      cache.put('alpha', _result('alpha'));
      cache.put('beta', _result('beta'));

      cache.clear();

      expect(cache.get('alpha'), isNull);
      expect(cache.get('beta'), isNull);
    });
  });

  group('DetectionCache — contains', () {
    test('is false for a key that was never put', () {
      final cache = DetectionCache();
      expect(cache.contains('alpha'), isFalse);
    });

    test('is true for a freshly put, unexpired key', () {
      final cache = DetectionCache();
      cache.put('alpha', _result('alpha'));
      expect(cache.contains('alpha'), isTrue);
    });

    test('is false once the entry has expired', () async {
      final cache = DetectionCache(ttl: const Duration(milliseconds: 10));
      cache.put('alpha', _result('alpha'));

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cache.contains('alpha'), isFalse);
    });
  });

  group('DetectionCache — cache hit / miss', () {
    test('cache hit: a valid entry is returned by get', () {
      final cache = DetectionCache(ttl: const Duration(seconds: 30));
      final result = _result('alpha');
      cache.put('alpha', result);

      expect(cache.get('alpha'), same(result));
    });

    test('cache miss: an unknown key returns null', () {
      final cache = DetectionCache();
      expect(cache.get('unknown'), isNull);
    });
  });

  group('DetectionCache — TTL expiration', () {
    test('an entry within its TTL is still returned', () async {
      final cache = DetectionCache(ttl: const Duration(milliseconds: 200));
      final result = _result('alpha');
      cache.put('alpha', result);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cache.get('alpha'), same(result));
    });

    test('an entry past its TTL is treated as absent (expired refresh '
        'path)', () async {
      final cache = DetectionCache(ttl: const Duration(milliseconds: 10));
      cache.put('alpha', _result('alpha'));

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cache.get('alpha'), isNull);

      // A fresh put after expiration is honored normally — the entry was
      // discarded, not left in some stuck state.
      final refreshed = _result('alpha', detected: true);
      cache.put('alpha', refreshed);
      expect(cache.get('alpha'), same(refreshed));
    });
  });
}
