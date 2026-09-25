import '../models/flutter_shield_exception.dart';
import 'dependency_resolver.dart';

enum _RegistrationKind { singleton, lazySingleton, factory }

class _Registration {
  _Registration.singleton(Object instance)
      : kind = _RegistrationKind.singleton,
        _instance = instance,
        _factory = null;

  _Registration.lazySingleton(Object Function() factory)
      : kind = _RegistrationKind.lazySingleton,
        _instance = null,
        _factory = factory;

  _Registration.factory(Object Function() factory)
      : kind = _RegistrationKind.factory,
        _instance = null,
        _factory = factory;

  final _RegistrationKind kind;
  Object? _instance;
  final Object Function()? _factory;

  Object resolve() {
    switch (kind) {
      case _RegistrationKind.singleton:
        return _instance!;
      case _RegistrationKind.lazySingleton:
        return _instance ??= _factory!();
      case _RegistrationKind.factory:
        return _factory!();
    }
  }
}

/// Type-keyed dependency injection container — the single lookup point
/// decoupling construction from use. See ARCHITECTURE_CONTRACTS.md's
/// `ServiceContainer` entry.
///
/// Three registration modes:
/// - [registerSingleton] — an already-constructed instance, returned as-is
///   on every [resolve].
/// - [registerLazySingleton] — a factory invoked once, on first [resolve];
///   the same instance is cached and returned thereafter.
/// - [registerFactory] — a factory invoked fresh on every [resolve]; no
///   caching.
///
/// Thread safety: every method here is synchronous (no `Future`, no
/// `await`). Dart's single-threaded event loop only preempts at `await`
/// points, so a synchronous method body can never be interleaved with
/// another call into this same container — there is no partial-mutation
/// window for two calls to race inside. This holds within one isolate,
/// which is the only supported usage: sharing one `ServiceContainer`
/// across isolates is not a pattern this SDK's architecture uses (see
/// ARCHITECTURE_CONTRACTS.md's concurrency model — all orchestration runs
/// on the Dart main isolate).
///
/// Public/Internal: internal.
class ServiceContainer {
  final Map<Type, _Registration> _registrations = {};
  final DependencyResolver _resolver = DependencyResolver();

  /// Registers an already-constructed [instance] for type [T].
  ///
  /// Throws [InitializationException] (`DUPLICATE_REGISTRATION`) if [T] is
  /// already registered — call [unregister] or [reset] first if replacing
  /// a registration is intentional.
  void registerSingleton<T>(T instance) {
    _assertNotRegistered<T>();
    _registrations[T] = _Registration.singleton(instance as Object);
  }

  /// Registers [factory] for type [T]; it runs once, on first [resolve],
  /// and the result is cached for every subsequent resolve.
  void registerLazySingleton<T>(T Function() factory) {
    _assertNotRegistered<T>();
    _registrations[T] = _Registration.lazySingleton(() => factory() as Object);
  }

  /// Registers [factory] for type [T]; it runs fresh on every [resolve] —
  /// no caching.
  void registerFactory<T>(T Function() factory) {
    _assertNotRegistered<T>();
    _registrations[T] = _Registration.factory(() => factory() as Object);
  }

  /// Whether a registration exists for [T].
  bool isRegistered<T>() => _registrations.containsKey(T);

  /// Returns the instance registered for [T].
  ///
  /// Throws [InitializationException] (`UNRESOLVED_DEPENDENCY`) if nothing
  /// is registered for [T], or (`CIRCULAR_DEPENDENCY`) if resolving [T]
  /// re-enters itself via a factory's own dependency chain.
  T resolve<T>() {
    final registration = _registrations[T];
    if (registration == null) {
      throw InitializationException(
        code: 'UNRESOLVED_DEPENDENCY',
        message: 'No registration found for type $T',
      );
    }
    return _resolver.guard<T>(() => registration.resolve() as T);
  }

  /// Removes the registration for [T], if present. A no-op if [T] was
  /// never registered.
  void unregister<T>() {
    _registrations.remove(T);
  }

  /// Clears every registration and cached lazy-singleton instance.
  void reset() {
    _registrations.clear();
  }

  void _assertNotRegistered<T>() {
    if (_registrations.containsKey(T)) {
      throw InitializationException(
        code: 'DUPLICATE_REGISTRATION',
        message: 'Type $T is already registered',
      );
    }
  }
}
