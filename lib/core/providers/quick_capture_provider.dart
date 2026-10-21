import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/quick_capture_service.dart';

final quickCaptureServiceProvider = Provider<QuickCaptureService>((ref) {
  final service = QuickCaptureService();
  ref.onDispose(() {
    // Riverpod disposal is synchronous; main shutdown explicitly awaits this
    // service before disposing the container. This remains a safety net.
    unawaited(service.dispose());
  });
  return service;
});

/// Incremented each time the global hotkey asks the UI to open the dialog.
///
/// A counter (rather than a boolean) lets repeated presses open the dialog
/// again after it has been dismissed.
class QuickCaptureRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final quickCaptureRequestProvider =
    NotifierProvider<QuickCaptureRequestNotifier, int>(
      QuickCaptureRequestNotifier.new,
    );

/// Prevents repeated global-hotkey events from stacking multiple dialogs.
class QuickCaptureDialogGate {
  bool _held = false;

  bool tryAcquire() {
    if (_held) return false;
    _held = true;
    return true;
  }

  void release() => _held = false;
}
