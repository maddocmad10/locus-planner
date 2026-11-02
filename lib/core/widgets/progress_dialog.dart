import 'package:flutter/material.dart';

/// Shows a blocking progress dialog while a slow task (encryption, decryption
/// or import) runs, then removes it.
Future<T> runWithProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() task,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
