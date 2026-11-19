part of '../mobile_app.dart';

class _RemindersCard extends ConsumerStatefulWidget {
  const _RemindersCard();

  @override
  ConsumerState<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends ConsumerState<_RemindersCard>
    with WidgetsBindingObserver {
  ReminderCapabilities? _capabilities;
  bool _enabled = true;
  bool _tasksEnabled = true;
  bool _exactEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from one of Android's settings screens: show what changed there.
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final service = ref.read(mobileReminderServiceProvider);
    final enabled = await service.isEnabled();
    final tasksEnabled = await service.tasksEnabled();
    final capabilities = await ref
        .read(reminderPlatformProvider)
        .capabilities();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _tasksEnabled = tasksEnabled;
      _exactEnabled = capabilities.exactAlarmsEnabled;
      _capabilities = capabilities;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await ref.read(mobileReminderServiceProvider).setEnabled(value);
  }

  Future<void> _setTasksEnabled(bool value) async {
    setState(() => _tasksEnabled = value);
    await ref.read(mobileReminderServiceProvider).setTasksEnabled(value);
  }

  Future<void> _setExactEnabled(bool value) async {
    setState(() => _exactEnabled = value);
    await ref.read(reminderPlatformProvider).setExactAlarmsEnabled(value);
    await _load();
  }

  Future<void> _allowNotifications() async {
    await ref
        .read(appLockControllerProvider.notifier)
        .runExternal(
          () => ref
              .read(reminderPlatformProvider)
              .requestNotificationPermission(),
        );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    // Nothing to show until the Android side has answered, or without it.
    if (capabilities == null || !capabilities.supported) {
      return const SizedBox.shrink();
    }
    final platform = ref.read(reminderPlatformProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Event reminders'),
              subtitle: const Text(
                'Notify me before events that have a reminder, even when '
                'Locus is closed.',
              ),
              value: _enabled,
              onChanged: _setEnabled,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Task reminders'),
              subtitle: const Text(
                'Notify me at a to-do reminder time, even when Locus is '
                'closed.',
              ),
              value: _tasksEnabled,
              onChanged: _setTasksEnabled,
            ),
            if (_enabled || _tasksEnabled)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exact reminder timing'),
                subtitle: Text(
                  !capabilities.exactAlarmsAllowed
                      ? 'Android is restricting exact alarms, so reminders may '
                            'arrive a few minutes late.'
                      : _exactEnabled
                      ? 'Fire at the exact minute. Turn off to save battery; '
                            'reminders may then arrive a few minutes late.'
                      : 'Approximate timing is on; reminders may arrive a few '
                            'minutes late.',
                ),
                value: _exactEnabled && capabilities.exactAlarmsAllowed,
                onChanged: capabilities.exactAlarmsAllowed
                    ? _setExactEnabled
                    : null,
              ),
            if ((_enabled || _tasksEnabled) &&
                !capabilities.notificationsAllowed) ...[
              Text(
                'Notifications are turned off for Locus, so reminders cannot '
                'appear.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _allowNotifications,
                    child: const Text('Allow notifications'),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(appLockControllerProvider.notifier)
                        .runExternal(platform.openNotificationSettings),
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ],
            if ((_enabled || _tasksEnabled) &&
                capabilities.notificationsAllowed &&
                !capabilities.exactAlarmsAllowed) ...[
              const Text(
                'Reminders can arrive a few minutes late. Allow alarms and '
                'reminders for Locus to get them on time.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref
                      .read(appLockControllerProvider.notifier)
                      .runExternal(platform.openExactAlarmSettings),
                  child: const Text('Allow exact timing'),
                ),
              ),
            ],
            if (_enabled || _tasksEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'Locus plans reminders for the next 30 days. On Windows, '
                'reminders require the app to be running; Android uses native '
                'alarms.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
