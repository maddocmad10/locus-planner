import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Source of "now". Production uses the system clock; tests override it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// How often the app checks whether the calendar day has changed.
final dayCheckIntervalProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 1),
);
