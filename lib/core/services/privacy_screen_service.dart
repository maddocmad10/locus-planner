import 'dart:io';

import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// Controls whether the operating system may expose this app's window contents
/// in screenshots and the recent-apps thumbnail.
abstract interface class PrivacyScreen {
  Future<void> setSecure(bool secure);
}

/// Android implementation: toggles `FLAG_SECURE`.
///
/// Every other platform, and an Android build without the channel, is a no-op.
/// Failing to set the flag must never stop the app from locking, so platform
/// errors are swallowed.
class MethodChannelPrivacyScreen implements PrivacyScreen {
  const MethodChannelPrivacyScreen();

  static const _channel = MethodChannel('locus_planner/privacy');
  static int? _windowsHandle;

  @override
  Future<void> setSecure(bool secure) async {
    if (Platform.isWindows) {
      // Windows 10 2004+ can exclude the window from screen capture entirely.
      // Keep the handle first observed while the app is active; a later
      // background lock must not pick another application's window.
      final handle = _windowsHandle ??= GetActiveWindow();
      if (handle != 0) {
        SetWindowDisplayAffinity(
          handle,
          secure ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE,
        );
      }
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Older builds without the privacy channel.
    } on PlatformException {
      // The flag is best-effort; the Dart lock screen still covers content.
    }
  }
}
