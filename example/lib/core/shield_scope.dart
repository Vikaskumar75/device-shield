import 'package:flutter/widgets.dart';

import 'shield_controller.dart';

/// Makes the single app-wide [ShieldController] available to every screen
/// via `ShieldScope.of(context)`, without a third-party state-management
/// dependency — [InheritedNotifier] is already part of the Flutter SDK and
/// is sufficient for this app's needs (one shared, observable controller).
class ShieldScope extends InheritedNotifier<ShieldController> {
  const ShieldScope({
    super.key,
    required ShieldController controller,
    required super.child,
  }) : super(notifier: controller);

  static ShieldController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShieldScope>();
    assert(scope != null, 'No ShieldScope found in context');
    return scope!.notifier!;
  }
}
