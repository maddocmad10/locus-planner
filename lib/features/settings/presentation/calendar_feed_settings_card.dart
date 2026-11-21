import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/services/calendar_subscription_service.dart';

/// Desktop-only read-only iCalendar subscriptions. Separate from the one-off
/// ICS import/export actions.
class CalendarFeedSettingsCard extends ConsumerStatefulWidget {
  const CalendarFeedSettingsCard({super.key});

  @override
  ConsumerState<CalendarFeedSettingsCard> createState() =>
      _CalendarFeedSettingsCardState();
}

class _CalendarFeedSettingsCardState
    extends ConsumerState<CalendarFeedSettingsCard> {
  List<CalendarSource>? _sources;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await ref
        .read(calendarSubscriptionServiceProvider)
        .sources();
    if (mounted) setState(() => _sources = sources);
  }

  Future<void> _add() async {
    final label = TextEditingController();
    final url = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add calendar subscription'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'HTTPS iCalendar URL',
                  hintText: 'https://example.com/calendar.ics',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'The URL is stored in the operating-system-protected secret '
                'store. Feed entries stay on this PC and are read-only.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      label.dispose();
      url.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(calendarSubscriptionServiceProvider)
          .addSource(label: label.text, url: Uri.parse(url.text.trim()));
      await _load();
    } catch (error) {
      if (mounted) _message('Could not add the feed: $error');
    } finally {
      label.dispose();
      url.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(CalendarSource source) async {
    setState(() => _busy = true);
    try {
      await ref.read(calendarSubscriptionServiceProvider).refresh(source.id);
      await _load();
    } catch (error) {
      if (mounted) _message('Refresh failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(CalendarSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect calendar?'),
        content: Text(
          'Remove “${source.label}”, its cached events and its stored URL.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(calendarSubscriptionServiceProvider).disconnect(source.id);
    await _load();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Read-only calendar subscriptions'),
            subtitle: const Text(
              'Desktop only. Feed events appear in Calendar and Today and are '
              'never published, synced or included in backups.',
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _add,
              child: const Text('Add feed'),
            ),
          ),
          if (sources == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (sources.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No subscriptions yet.'),
            )
          else
            for (final source in sources)
              ListTile(
                dense: true,
                leading: Icon(
                  source.lastError == null
                      ? Icons.rss_feed_outlined
                      : Icons.warning_amber_outlined,
                ),
                title: Text(source.label),
                subtitle: Text(
                  [
                    if (source.lastSuccess != null)
                      'Refreshed '
                          '${DateFormat.yMMMd().add_jm().format(source.lastSuccess!.toLocal())}'
                    else
                      'Never refreshed',
                    if (source.isStale) 'Stale',
                    if (source.lastError != null) 'Error: ${source.lastError}',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Refresh now',
                      onPressed: _busy ? null : () => _refresh(source),
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Disconnect',
                      onPressed: _busy ? null : () => _disconnect(source),
                      icon: const Icon(Icons.link_off),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
