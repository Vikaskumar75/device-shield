import 'package:flutter/widgets.dart';

import 'lifecycle.dart';

/// Real implementation of [LifecycleManager] — the only component
/// listening to Flutter's own app lifecycle, via [WidgetsBindingObserver].
///
/// Holds nothing but a [SecurityLifecycleHandler] reference (narrow
/// callback contract, not `SecurityManager` itself — see
/// ARCHITECTURE_CONTRACTS.md's circular-dependency fix). Never
/// constructs a `SecurityEvent`, never references `EventManager`, never
/// calls `NativeBridge` — its entire job is translating
/// [AppLifecycleState] into calls on whatever handler is attached.
class DefaultLifecycleManager extends WidgetsBindingObserver
    implements LifecycleManager {
  SecurityLifecycleHandler? _handler;
  bool _observing = false;

  @override
  void attach(SecurityLifecycleHandler handler) {
    _handler = handler;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  @override
  void detach() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _handler = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handler?.onResume();
        break;
      case AppLifecycleState.inactive:
        _handler?.onInactive();
        break;
      case AppLifecycleState.hidden:
        // No dedicated SecurityLifecycleHandler callback exists for
        // `hidden` (added to AppLifecycleState after the frozen
        // four-callback contract) — `inactive` is the closest existing
        // semantic (app not currently visible/interactive, not yet
        // backgrounded).
        _handler?.onInactive();
        break;
      case AppLifecycleState.paused:
        _handler?.onPause();
        break;
      case AppLifecycleState.detached:
        _handler?.onDetached();
        break;
    }
  }
}
