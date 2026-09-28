import 'dart:async';

import '../models/sdk_state.dart';
import 'lifecycle.dart';

/// Real, complete implementation of [Lifecycle] — the SDK's single source
/// of truth for status. Enforces exactly the transition table frozen in
/// ARCHITECTURE_CONTRACTS.md Part 3. No security/detection/policy content —
/// this is a pure state machine.
class DefaultSecurityStateManager implements Lifecycle {
  SDKState _current = SDKState.uninitialized;
  final StreamController<SDKState> _controller =
      StreamController<SDKState>.broadcast();

  /// The frozen transition table — every key's value set is exactly the
  /// set of states reachable from it. Any request not in this table throws.
  static const Map<SDKState, Set<SDKState>> _allowedTransitions = {
    SDKState.uninitialized: {SDKState.initializing, SDKState.destroyed},
    SDKState.initializing: {
      SDKState.initialized,
      SDKState.failure,
      SDKState.destroyed,
    },
    SDKState.initialized: {
      SDKState.running,
      SDKState.stopped,
      SDKState.destroyed,
    },
    SDKState.running: {
      SDKState.paused,
      SDKState.stopped,
      SDKState.failure,
      SDKState.destroyed,
    },
    SDKState.paused: {SDKState.running, SDKState.stopped, SDKState.destroyed},
    SDKState.stopped: {SDKState.running, SDKState.destroyed},
    SDKState.failure: {
      SDKState.initialized,
      SDKState.stopped,
      SDKState.destroyed,
    },
    SDKState.destroyed: {},
  };

  @override
  SDKState get current => _current;

  @override
  Stream<SDKState> get stateStream => _controller.stream;

  @override
  void transitionTo(SDKState next) {
    final allowed = _allowedTransitions[_current] ?? const {};
    if (!allowed.contains(next)) {
      throw StateError('Illegal SDK state transition: $_current -> $next');
    }
    _current = next;
    _controller.add(next);
  }

  /// Closes the state stream. Call only after transitioning to
  /// [SDKState.destroyed] — never while a transition might still need to
  /// broadcast.
  void dispose() => _controller.close();
}
