import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import 'calendar_projection.dart';

/// Read-only feed entries for one visible range, merged with local data by the
/// calendar page. The feed cache is never written back to the events table.
final calendarSubscriptionEntriesProvider = FutureProvider.autoDispose
    .family<List<CalendarEntry>, ({DateTime from, DateTime to})>((
      ref,
      range,
    ) async {
      final service = ref.watch(calendarSubscriptionServiceProvider);
      final sources = await service.sources();
      if (sources.isEmpty) return const [];
      final occurrences = await service.occurrencesBetween(
        range.from,
        range.to,
      );
      return buildSubscriptionEntries(
        occurrences: occurrences,
        sourceLabels: {for (final source in sources) source.id: source.label},
      );
    });
