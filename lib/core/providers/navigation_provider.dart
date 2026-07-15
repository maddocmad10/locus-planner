import 'package:flutter_riverpod/flutter_riverpod.dart';

final navigationIndexProvider = StateProvider<int>((ref) => 0);

final selectedCalendarDayProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

final diarySelectedDateProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

final focusDurationProvider = StateProvider<int>((ref) => 25);
