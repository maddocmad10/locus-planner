import 'package:flutter/material.dart';

import '../services/undo_service.dart';

class UndoSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    required UndoService service,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            final restored = await service.undo();
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  restored ? 'Restored successfully' : 'Could not restore item',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
