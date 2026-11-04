import 'package:locus_planner/features/mobile/data/reminder_planner.dart';
import 'package:locus_planner/features/mobile/data/reminder_platform.dart';

/// Records what the app asks the Android side to do.
class FakeReminderPlatform implements ReminderPlatform {
  final List<List<PlannedReminder>> replaced = [];
  int cancelled = 0;
  int permissionRequests = 0;
  final List<bool> exactAlarmsEnabledRequests = <bool>[];
  bool failing = false;
  ReminderCapabilities capabilitiesResult = const ReminderCapabilities(
    supported: true,
  );

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    // Yield, as a real channel call would, so overlapping calls are possible.
    await Future<void>.delayed(Duration.zero);
    if (failing) throw StateError('platform unavailable');
    replaced.add(List.of(reminders));
  }

  @override
  Future<void> cancelAll() async {
    await Future<void>.delayed(Duration.zero);
    if (failing) throw StateError('platform unavailable');
    cancelled++;
  }

  @override
  Future<ReminderCapabilities> capabilities() async => capabilitiesResult;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    return capabilitiesResult.notificationsAllowed;
  }

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> setExactAlarmsEnabled(bool enabled) async {
    exactAlarmsEnabledRequests.add(enabled);
    capabilitiesResult = ReminderCapabilities(
      supported: capabilitiesResult.supported,
      notificationsAllowed: capabilitiesResult.notificationsAllowed,
      exactAlarmsAllowed: capabilitiesResult.exactAlarmsAllowed,
      exactAlarmsEnabled: enabled,
    );
  }

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<String?> launchTab() async => null;

  @override
  Stream<String> get requestedTabs => const Stream.empty();
}
