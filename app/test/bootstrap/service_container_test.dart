import 'package:flutter_shield/src/bootstrap/service_container.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_test/flutter_test.dart';

abstract class _Greeter {
  String greet();
}

class _EnglishGreeter implements _Greeter {
  @override
  String greet() => 'hello';
}

void main() {
  group('ServiceContainer registration modes', () {
    test('registerSingleton returns the same instance every resolve', () {
      final container = ServiceContainer();
      final instance = _EnglishGreeter();
      container.registerSingleton<_Greeter>(instance);

      expect(identical(container.resolve<_Greeter>(), instance), isTrue);
      expect(identical(container.resolve<_Greeter>(), instance), isTrue);
    });

    test('registerLazySingleton builds once and caches the result', () {
      final container = ServiceContainer();
      var buildCount = 0;
      container.registerLazySingleton<_Greeter>(() {
        buildCount++;
        return _EnglishGreeter();
      });

      final first = container.resolve<_Greeter>();
      final second = container.resolve<_Greeter>();

      expect(buildCount, 1);
      expect(identical(first, second), isTrue);
    });

    test('registerFactory builds a fresh instance every resolve', () {
      final container = ServiceContainer();
      var buildCount = 0;
      container.registerFactory<_Greeter>(() {
        buildCount++;
        return _EnglishGreeter();
      });

      final first = container.resolve<_Greeter>();
      final second = container.resolve<_Greeter>();

      expect(buildCount, 2);
      expect(identical(first, second), isFalse);
    });
  });

  group('ServiceContainer error contract', () {
    test('resolve throws UNRESOLVED_DEPENDENCY when nothing is registered',
        () {
      final container = ServiceContainer();
      expect(
        () => container.resolve<_Greeter>(),
        throwsA(isA<InitializationException>()
            .having((e) => e.code, 'code', 'UNRESOLVED_DEPENDENCY')),
      );
    });

    test('registering the same type twice throws DUPLICATE_REGISTRATION',
        () {
      final container = ServiceContainer();
      container.registerSingleton<_Greeter>(_EnglishGreeter());

      expect(
        () => container.registerSingleton<_Greeter>(_EnglishGreeter()),
        throwsA(isA<InitializationException>()
            .having((e) => e.code, 'code', 'DUPLICATE_REGISTRATION')),
      );
    });

    test('a circular factory dependency throws CIRCULAR_DEPENDENCY', () {
      final container = ServiceContainer();
      container.registerFactory<_A>(() => _A(container.resolve<_B>()));
      container.registerFactory<_B>(() => _B(container.resolve<_A>()));

      expect(
        () => container.resolve<_A>(),
        throwsA(isA<InitializationException>()
            .having((e) => e.code, 'code', 'CIRCULAR_DEPENDENCY')),
      );
    });
  });

  group('ServiceContainer lifecycle operations', () {
    test('isRegistered reflects current registration state', () {
      final container = ServiceContainer();
      expect(container.isRegistered<_Greeter>(), isFalse);

      container.registerSingleton<_Greeter>(_EnglishGreeter());
      expect(container.isRegistered<_Greeter>(), isTrue);
    });

    test('unregister removes a single registration', () {
      final container = ServiceContainer();
      container.registerSingleton<_Greeter>(_EnglishGreeter());

      container.unregister<_Greeter>();

      expect(container.isRegistered<_Greeter>(), isFalse);
      expect(
          () => container.resolve<_Greeter>(), throwsA(isA<Exception>()));
    });

    test('reset clears every registration', () {
      final container = ServiceContainer();
      container.registerSingleton<_Greeter>(_EnglishGreeter());
      container.registerSingleton<_A>(_A(_B(null)));

      container.reset();

      expect(container.isRegistered<_Greeter>(), isFalse);
      expect(container.isRegistered<_A>(), isFalse);
    });

    test('after reset, a type can be registered again without throwing', () {
      final container = ServiceContainer();
      container.registerSingleton<_Greeter>(_EnglishGreeter());
      container.reset();

      expect(
          () => container.registerSingleton<_Greeter>(_EnglishGreeter()),
          returnsNormally);
    });
  });
}

class _A {
  _A(this.b);
  final dynamic b;
}

class _B {
  _B(this.a);
  final dynamic a;
}
