import 'package:flutter/material.dart';

/// A button wired to an async SDK action, showing a loading spinner while
/// running and a success/failure [SnackBar] afterward — every Runtime
/// Controls button uses this so "every button should show success/
/// failure" holds uniformly, without duplicating the same
/// loading/try/catch/SnackBar boilerplate at every call site.
class ShieldActionButton extends StatefulWidget {
  const ShieldActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.successMessage,
    this.filled = false,
    this.color,
  });

  final String label;
  final Future<bool> Function() onPressed;
  final IconData? icon;
  final String? successMessage;
  final bool filled;
  final Color? color;

  @override
  State<ShieldActionButton> createState() => _ShieldActionButtonState();
}

class _ShieldActionButtonState extends State<ShieldActionButton> {
  bool _running = false;

  Future<void> _handleTap() async {
    if (_running) return;
    setState(() => _running = true);
    final success = await widget.onPressed();
    if (!mounted) return;
    setState(() => _running = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(success
          ? (widget.successMessage ?? '${widget.label} succeeded')
          : '${widget.label} failed — see Logs/Errors for detail'),
      backgroundColor: success
          ? Colors.green.shade700
          : Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final child = _running
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.play_arrow, size: 18);

    if (widget.filled) {
      return FilledButton.icon(
        onPressed: _running ? null : _handleTap,
        icon: child,
        label: Text(widget.label),
        style: widget.color != null
            ? FilledButton.styleFrom(backgroundColor: widget.color)
            : null,
      );
    }
    return OutlinedButton.icon(
      onPressed: _running ? null : _handleTap,
      icon: child,
      label: Text(widget.label),
    );
  }
}
