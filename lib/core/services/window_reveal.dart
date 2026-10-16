/// Brings the main window to the front from any state: minimized, hidden in
/// the tray, or already visible.
///
/// `show()` alone makes a hidden window visible but leaves a minimized one on
/// the taskbar, so a second launch or a tray click appeared to do nothing. The
/// operations are passed in, which keeps this testable without a window.
Future<void> revealWindow({
  required Future<bool> Function() isMinimized,
  required Future<void> Function() restore,
  required Future<void> Function() show,
  required Future<void> Function() focus,
}) async {
  var minimized = false;
  try {
    minimized = await isMinimized();
  } catch (_) {
    // If the state can't be read, showing and focusing is still the best try.
  }
  if (minimized) {
    try {
      await restore();
    } catch (_) {
      // A failed restore shouldn't stop the window being shown and focused.
    }
  }
  await show();
  await focus();
}
