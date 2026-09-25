import 'package:flutter/material.dart';

/// Every alert presentation style this reference app demonstrates. Kept
/// as a single enum + dispatcher so the Screenshot/Recording demo screens
/// can offer "switch alert style" without duplicating six near-identical
/// trigger methods each.
enum AlertStyle { snackBar, dialog, bottomSheet, banner, overlay, fullscreen }

extension AlertStyleLabel on AlertStyle {
  String get label => switch (this) {
        AlertStyle.snackBar => 'SnackBar',
        AlertStyle.dialog => 'Dialog',
        AlertStyle.bottomSheet => 'Bottom Sheet',
        AlertStyle.banner => 'Banner',
        AlertStyle.overlay => 'Overlay',
        AlertStyle.fullscreen => 'Fullscreen Warning',
      };
}

/// Fires a security-style alert in whichever [style] is currently
/// selected. This is presentation only — it never touches the SDK; the
/// caller decides *when* to show it (e.g. on a screenshot/recording
/// event).
void showSecurityAlert(
  BuildContext context, {
  required AlertStyle style,
  required String title,
  required String message,
}) {
  switch (style) {
    case AlertStyle.snackBar:
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$title — $message'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
      ));
      break;
    case AlertStyle.dialog:
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.security, color: Colors.red),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
      break;
    case AlertStyle.bottomSheet:
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.security, color: Colors.red),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      break;
    case AlertStyle.banner:
      ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
        leading: const Icon(Icons.security, color: Colors.red),
        content: Text('$title — $message'),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ));
      break;
    case AlertStyle.overlay:
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.red.shade700,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('$title — $message',
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      Future.delayed(const Duration(seconds: 3), () {
        if (entry.mounted) entry.remove();
      });
      break;
    case AlertStyle.fullscreen:
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: title,
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: Colors.red.shade900,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security, color: Colors.white, size: 72),
                    const SizedBox(height: 24),
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(message,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Dismiss',
                          style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      break;
  }
}
