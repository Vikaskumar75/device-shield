import '../models/device_shield_exception.dart';

/// Detects circular dependencies during [ServiceContainer] resolution.
///
/// A cycle can only arise when a registered factory calls back into the
/// container to resolve another type while it is itself still being
/// constructed (e.g. factory A resolves B, whose factory resolves A again
/// before A's first resolution completed). This tracks an in-progress
/// resolution stack and throws the moment a type reappears on it.
///
/// Public/Internal: internal — used exclusively by [ServiceContainer].
class DependencyResolver {
  final List<Type> _resolutionStack = [];

  /// Runs [resolve] for [T], guarding against re-entrant resolution of the
  /// same type. Throws [InitializationException] (`CIRCULAR_DEPENDENCY`) if
  /// [T] is already being resolved further up the call stack.
  T guard<T>(T Function() resolve) {
    if (_resolutionStack.contains(T)) {
      throw InitializationException(
        code: 'CIRCULAR_DEPENDENCY',
        message:
            'Circular dependency detected while resolving $T: '
            '${_resolutionStack.join(' -> ')} -> $T',
      );
    }
    _resolutionStack.add(T);
    try {
      return resolve();
    } finally {
      _resolutionStack.removeLast();
    }
  }
}
