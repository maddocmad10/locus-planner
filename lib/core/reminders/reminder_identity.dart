import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/reminder_kind.dart';

/// Canonical identity of one reminder occurrence.
///
/// The OS scheduler and the missed-reminder inbox must agree on what "the same
/// occurrence" means, otherwise one occurrence can be owned twice (a toast plus
/// an in-process fallback). [occurrenceStart] is therefore the event start time
/// or the task's reminder time, never the derived fire time.
class ReminderOccurrence {
  const ReminderOccurrence({
    required this.kind,
    required this.entityId,
    required this.occurrenceStart,
  });

  final ReminderKind kind;
  final String entityId;
  final DateTime occurrenceStart;

  /// Human-readable, stable key persisted in inbox/snooze state.
  String get key =>
      '${kind.name}:$entityId@${occurrenceStart.millisecondsSinceEpoch}';

  /// The 16-character id Windows accepts for a scheduled toast.
  String get stableId => stableIdForKey(key);

  /// The entity-level suppression key (`kind:entityId`).
  String get entityKey => '${kind.name}:$entityId';

  static ReminderOccurrence? tryParse(String key) {
    final at = key.lastIndexOf('@');
    if (at <= 0 || at == key.length - 1) return null;
    final separator = key.indexOf(':');
    if (separator <= 0 || separator >= at) return null;
    final kindName = key.substring(0, separator);
    ReminderKind? kind;
    for (final value in ReminderKind.values) {
      if (value.name == kindName) kind = value;
    }
    if (kind == null) return null;
    final millis = int.tryParse(key.substring(at + 1));
    if (millis == null) return null;
    final entityId = key.substring(separator + 1, at);
    if (entityId.isEmpty) return null;
    return ReminderOccurrence(
      kind: kind,
      entityId: entityId,
      occurrenceStart: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

/// Builds the canonical key without constructing an object.
String canonicalReminderKey(
  ReminderKind kind,
  String entityId,
  DateTime occurrenceStart,
) => '${kind.name}:$entityId@${occurrenceStart.millisecondsSinceEpoch}';

/// Deterministic 16-character OS id derived from a canonical occurrence key:
/// base32(SHA256(key))[0..16].
String stableIdForKey(String key) {
  final digest = sha256.convert(utf8.encode(key)).bytes;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final out = StringBuffer();
  for (final byte in digest) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
      if (out.length >= 16) return out.toString();
    }
  }
  return out.toString().padRight(16, 'A').substring(0, 16);
}
