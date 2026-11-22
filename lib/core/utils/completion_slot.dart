import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Portable semantics for the occurrence a completion closes.
abstract final class CompletionSlot {
  static const legacyInstant = 'legacy_instant';
  static const dateOnly = 'date_only';
  static const instant = 'instant';
  static const undated = 'undated';

  static bool isKnownKind(String? kind) =>
      kind == legacyInstant ||
      kind == dateOnly ||
      kind == instant ||
      kind == undated;

  static String civilDateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Drift stores seconds, so timed keys use the same precision.
  static String instantKey(DateTime value) {
    final utc = value.toUtc();
    final seconds = DateTime.fromMillisecondsSinceEpoch(
      (utc.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    return 'due:${seconds.toIso8601String()}';
  }

  /// Infers the new semantics for an explicit user edit. Midnight remains
  /// date-only, matching the current date-picker UI; other times are instants.
  static String inferKind(DateTime? due) {
    if (due == null) return undated;
    return due.hour == 0 &&
            due.minute == 0 &&
            due.second == 0 &&
            due.millisecond == 0 &&
            due.microsecond == 0
        ? dateOnly
        : instant;
  }

  static String keyFor({
    required String taskId,
    required String kind,
    DateTime? due,
    String? dateKey,
    String? generation,
  }) {
    switch (kind) {
      case dateOnly:
        return 'due:${dateKey ?? (due == null ? 'undated' : civilDateKey(due))}';
      case instant:
        return due == null ? 'undated:$taskId' : instantKey(due);
      case undated:
        return 'undated:${generation ?? taskId}';
      case legacyInstant:
      default:
        if (due == null) return 'undated:${generation ?? taskId}';
        final dateOnlyValue =
            due.hour == 0 &&
            due.minute == 0 &&
            due.second == 0 &&
            due.millisecond == 0 &&
            due.microsecond == 0;
        if (dateOnlyValue) return 'due:${civilDateKey(due)}';
        return 'due:${due.toUtc().toIso8601String()}';
    }
  }

  static String completionIdFor(String taskId, String occurrenceKey) {
    final digest = sha256
        .convert(utf8.encode('$taskId|$occurrenceKey'))
        .toString();
    return 'cmp_${digest.substring(0, 24)}';
  }

  static String newGeneration() => const Uuid().v4();

  /// Normalises the stored due value without changing its instant.
  static DateTime? dueFor({
    required String kind,
    DateTime? due,
    String? dateKey,
  }) {
    if (kind == dateOnly) {
      final key = dateKey;
      if (key != null) {
        final parsed = DateTime.tryParse(key);
        if (parsed != null) {
          return DateTime(parsed.year, parsed.month, parsed.day);
        }
      }
    }
    return due;
  }
}
