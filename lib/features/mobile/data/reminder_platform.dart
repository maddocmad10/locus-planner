import 'package:flutter/services.dart';

import 'reminder_planner.dart';

/// What the phone currently allows reminders to do.
class ReminderCapabilities {
  const ReminderCapabilities({
    required this.supported,
    this.notificationsAllowed = true,
    this.exactAlarmsAllowed = true,
  });

  /// False when there is no Android reminder support behind the channel (other
  /// platforms, tests).
  final bool supported;

  /// False while the user has notifications for Locus turned off.
  final bool notificationsAllowed;

  /// False when Android only lets the app set approximate alarms, so a
  /// reminder can arrive a few minutes late.
  final bool exactAlarmsAllowed;

  static const unsupported = ReminderCapabilities(supported: false);
}

/// The Android side of event reminders: alarms and notifications.
abstract interface class ReminderPlatform {
  /// Replaces every pending reminder with [reminders].
  Future<void> replaceAll(List<PlannedReminder> reminders);

  Future<void> cancelAll();

  Future<ReminderCapabilities> capabilities();

  /// Asks for the notification permission (Android 13 and newer). Returns
  /// whether notifications are allowed afterwards.
  Future<bool> requestNotificationPermission();

  Future<void> openExactAlarmSettings();

  Future<void> openNotificationSettings();
}

/// Talks to `MainActivity.kt` over a method channel.
class MethodChannelReminderPlatform implements ReminderPlatform {
  MethodChannelReminderPlatform([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'locus_planner/reminders';

  final MethodChannel _channel;

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) =>
      _channel.invokeMethod<void>('replaceAll', {
        'reminders': [for (final reminder in reminders) reminder.toMap()],
      });

  @override
  Future<void> cancelAll() => _channel.invokeMethod<void>('cancelAll');

  @override
  Future<ReminderCapabilities> capabilities() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'capabilities',
      );
      if (result == null) return ReminderCapabilities.unsupported;
      return ReminderCapabilities(
        supported: true,
        notificationsAllowed: result['notificationsAllowed'] != false,
        exactAlarmsAllowed: result['exactAlarmsAllowed'] != false,
      );
    } on MissingPluginException {
      return ReminderCapabilities.unsupported;
    } on PlatformException {
      return ReminderCapabilities.unsupported;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod<void>('openExactAlarmSettings');
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // The settings screen is not available on this device.
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // The settings screen is not available on this device.
    }
  }
}
