import '../utils/app_clock.dart';
import '../utils/day_math.dart';
import '../utils/recurrence.dart';

/// Importance parsed from a quick-add phrase.
enum QuickAddPriority {
  none(0),
  low(1),
  medium(2),
  high(3);

  const QuickAddPriority(this.value);

  final int value;
}

/// Everything the quick-add parser could understand from one line.
///
/// The result is deliberately data-only: the same parse drives the desktop
/// dialog, the mobile sheet and the tests. Nothing here performs I/O or reads
/// the clock except through [NaturalLanguageQuickAdd.parse].
class NaturalLanguageCapture {
  const NaturalLanguageCapture({
    required this.title,
    this.date,
    this.allDay = false,
    this.recurrenceRule,
    this.priority = QuickAddPriority.none,
    this.tags = const <String>[],
    this.projectHint,
    this.hints = const <String>[],
  });

  /// Title with the recognised date, time, repeat, priority and tag tokens
  /// removed. Falls back to the original text when everything was consumed.
  final String title;

  /// Event start or task due date. Date-only values are local midnight.
  final DateTime? date;

  /// True when a date was recognised without a time.
  final bool allDay;

  /// One of the `Recurrence` rule strings, or null.
  final String? recurrenceRule;

  final QuickAddPriority priority;
  final List<String> tags;
  final String? projectHint;

  /// Short human-readable labels for the confirmation preview.
  final List<String> hints;

  bool get hasSchedule => date != null;
  bool get hasRecurrence => recurrenceRule != null;
  bool get hasDetails =>
      date != null ||
      recurrenceRule != null ||
      priority != QuickAddPriority.none ||
      tags.isNotEmpty ||
      projectHint != null;

  NaturalLanguageCapture copyWith({String? title}) => NaturalLanguageCapture(
    title: title ?? this.title,
    date: date,
    allDay: allDay,
    recurrenceRule: recurrenceRule,
    priority: priority,
    tags: tags,
    projectHint: projectHint,
    hints: hints,
  );
}

/// Pure, offline parser for short natural-language captures.
///
/// Supported grammar (intentionally small and predictable):
///
/// * dates: today, tomorrow, day after tomorrow, next week, next Monday,
///   Monday, in N days/weeks;
/// * times: 9am, 9:30 pm, 14:00, at 9, at 14:30, noon, midnight;
/// * repeats: daily/every day, weekdays/every weekday, weekly/every week,
///   every other week, every 2 weeks, every Monday, monthly, yearly;
/// * priority: !!!/high priority, !!/medium priority, !/low priority;
/// * tags (`#tag`) and a project hint (`@project`).
///
/// Anything outside this subset stays in the title. There is no network code.
abstract final class NaturalLanguageQuickAdd {
  static const _weekdayNumbers = <String, int>{
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  static const _weekdayPattern =
      'monday|tuesday|wednesday|thursday|friday|saturday|sunday';

  static NaturalLanguageCapture parse(String input, {DateTime? now}) {
    final source = input.trim();
    if (source.isEmpty) {
      return const NaturalLanguageCapture(title: '');
    }
    final clock = now ?? AppClock.now();
    final state = _ParseState(source);

    // Repeats first: "every Monday" both repeats and anchors the first date.
    _parseRecurrence(state);
    _parseDate(state, clock);
    _parseTime(state);
    _parsePriority(state);
    _parseTagsAndProject(state);

    final date = _resolveDate(state, clock);
    final hints = <String>[];
    if (state.dateHint != null) hints.add(state.dateHint!);
    if (state.time != null) {
      hints.add(
        '${state.time!.hour.toString().padLeft(2, '0')}:'
        '${state.time!.minute.toString().padLeft(2, '0')}',
      );
    }
    if (state.recurrence != null) {
      hints.add(Recurrence.label(state.recurrence));
    }
    if (state.priority != QuickAddPriority.none) {
      hints.add(switch (state.priority) {
        QuickAddPriority.high => 'High priority',
        QuickAddPriority.medium => 'Medium priority',
        QuickAddPriority.low => 'Low priority',
        QuickAddPriority.none => '',
      });
    }
    for (final tag in state.tags) {
      hints.add('#$tag');
    }
    if (state.projectHint != null) hints.add('@${state.projectHint}');

    return NaturalLanguageCapture(
      title: state.cleanTitle(source),
      date: date,
      allDay: date != null && state.time == null,
      recurrenceRule: state.recurrence,
      priority: state.priority,
      tags: List<String>.unmodifiable(state.tags),
      projectHint: state.projectHint,
      hints: List<String>.unmodifiable(hints),
    );
  }

  static void _parseRecurrence(_ParseState state) {
    if (state.take(RegExp(r'\bevery\s+other\s+week\b', caseSensitive: false))) {
      state.recurrence = Recurrence.biweekly;
      return;
    }
    if (state.take(RegExp(r'\bevery\s+2\s+weeks?\b', caseSensitive: false))) {
      state.recurrence = Recurrence.biweekly;
      return;
    }
    if (state.take(
      RegExp(r'\bevery\s+weekdays?\b|\bweekdays\b', caseSensitive: false),
    )) {
      state.recurrence = Recurrence.weekdays;
      return;
    }
    if (state.take(
      RegExp(r'\bdaily\b|\bevery\s+day\b', caseSensitive: false),
    )) {
      state.recurrence = Recurrence.daily;
      return;
    }
    if (state.take(
      RegExp(r'\bweekly\b|\bevery\s+week\b', caseSensitive: false),
    )) {
      state.recurrence = Recurrence.weekly;
      return;
    }
    if (state.take(
      RegExp(r'\bmonthly\b|\bevery\s+month\b', caseSensitive: false),
    )) {
      state.recurrence = Recurrence.monthly;
      return;
    }
    if (state.take(
      RegExp(r'\byearly\b|\bannually\b|\bevery\s+year\b', caseSensitive: false),
    )) {
      state.recurrence = Recurrence.yearly;
      return;
    }

    final weekday = RegExp(
      '\\bevery\\s+($_weekdayPattern)\\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (weekday != null) {
      state.recurrence = Recurrence.weekly;
      state.recurrenceWeekday =
          _weekdayNumbers[weekday.group(1)!.toLowerCase()];
      state.remove(weekday);
      state.dateHint = 'Every ${_titleCase(weekday.group(1)!)}';
    }
  }

  static void _parseDate(_ParseState state, DateTime now) {
    final base = DayMath.dateOnly(now);
    final dayAfterTomorrow = RegExp(
      r'\bday\s+after\s+tomorrow\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (dayAfterTomorrow != null) {
      state.date = DayMath.addDays(base, 2);
      state.dateHint = 'Day after tomorrow';
      state.remove(dayAfterTomorrow);
      return;
    }
    final tomorrow = RegExp(
      r'\btomorrow\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (tomorrow != null) {
      state.date = DayMath.addDays(base, 1);
      state.dateHint = 'Tomorrow';
      state.remove(tomorrow);
      return;
    }
    final today = RegExp(
      r'\btoday\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (today != null) {
      state.date = base;
      state.dateHint = 'Today';
      state.remove(today);
      return;
    }
    final nextWeek = RegExp(
      r'\bnext\s+week\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (nextWeek != null) {
      state.date = DayMath.addDays(base, 7);
      state.dateHint = 'Next week';
      state.remove(nextWeek);
      return;
    }

    final nextWeekday = RegExp(
      '\\bnext\\s+($_weekdayPattern)\\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (nextWeekday != null) {
      final weekday = _weekdayNumbers[nextWeekday.group(1)!.toLowerCase()]!;
      state.date = _startOfNextWeek(base).add(Duration(days: weekday - 1));
      state.dateHint = 'Next ${_titleCase(nextWeekday.group(1)!)}';
      state.remove(nextWeekday);
      return;
    }

    final weekday = RegExp(
      '\\b(?:on\\s+)?($_weekdayPattern)\\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (weekday != null) {
      final number = _weekdayNumbers[weekday.group(1)!.toLowerCase()]!;
      state.date = _nextWeekday(base, number);
      state.dateHint = _titleCase(weekday.group(1)!);
      state.remove(weekday);
      return;
    }

    final inDays = RegExp(
      r'\bin\s+(\d{1,3})\s+days?\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (inDays != null) {
      final count = int.parse(inDays.group(1)!);
      state.date = DayMath.addDays(base, count);
      state.dateHint = count == 1 ? 'Tomorrow' : 'In $count days';
      state.remove(inDays);
      return;
    }
    final inWeeks = RegExp(
      r'\bin\s+(\d{1,3})\s+weeks?\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (inWeeks != null) {
      final count = int.parse(inWeeks.group(1)!);
      state.date = DayMath.addDays(base, count * 7);
      state.dateHint = 'In $count week${count == 1 ? '' : 's'}';
      state.remove(inWeeks);
    }
  }

  static void _parseTime(_ParseState state) {
    final noon = RegExp(
      r'\b(?:at\s+)?noon\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (noon != null) {
      state.time = const _ClockTime(12, 0);
      state.remove(noon);
      return;
    }
    final midnight = RegExp(
      r'\b(?:at\s+)?midnight\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (midnight != null) {
      state.time = const _ClockTime(0, 0);
      state.remove(midnight);
      return;
    }

    final amPm = RegExp(
      r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (amPm != null) {
      var hour = int.parse(amPm.group(1)!);
      final minute = int.tryParse(amPm.group(2) ?? '') ?? 0;
      final meridiem = amPm.group(3)!.toLowerCase();
      if (hour >= 1 && hour <= 12 && minute < 60) {
        if (meridiem == 'pm' && hour != 12) hour += 12;
        if (meridiem == 'am' && hour == 12) hour = 0;
        state.time = _ClockTime(hour, minute);
        state.remove(amPm);
        return;
      }
    }

    final atHour = RegExp(
      r'\bat\s+(\d{1,2})(?::(\d{2}))?\b',
      caseSensitive: false,
    ).firstMatch(state.text);
    if (atHour != null) {
      final hour = int.parse(atHour.group(1)!);
      final minute = int.tryParse(atHour.group(2) ?? '') ?? 0;
      if (hour < 24 && minute < 60) {
        state.time = _ClockTime(hour, minute);
        state.remove(atHour);
        return;
      }
    }

    final twentyFour = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(state.text);
    if (twentyFour != null) {
      final hour = int.parse(twentyFour.group(1)!);
      final minute = int.parse(twentyFour.group(2)!);
      if (hour < 24 && minute < 60) {
        state.time = _ClockTime(hour, minute);
        state.remove(twentyFour);
      }
    }
  }

  static void _parsePriority(_ParseState state) {
    for (final entry in <(RegExp, QuickAddPriority)>[
      (
        RegExp(
          r'(?:!!!|\bp1\b|\bhigh\s+priority\b|\burgent\b)',
          caseSensitive: false,
        ),
        QuickAddPriority.high,
      ),
      (
        RegExp(r'(?:!!|\bp2\b|\bmedium\s+priority\b)', caseSensitive: false),
        QuickAddPriority.medium,
      ),
      (
        RegExp(r'(?:!|\bp3\b|\blow\s+priority\b)', caseSensitive: false),
        QuickAddPriority.low,
      ),
    ]) {
      if (state.take(entry.$1)) {
        state.priority = entry.$2;
        return;
      }
    }
  }

  static void _parseTagsAndProject(_ParseState state) {
    final tagPattern = RegExp(r'(?:^|\s)#([A-Za-z0-9_-]{1,32})');
    while (true) {
      final match = tagPattern.firstMatch(state.text);
      if (match == null) break;
      final tag = match.group(1)!;
      if (!state.tags.any(
        (value) => value.toLowerCase() == tag.toLowerCase(),
      )) {
        state.tags.add(tag);
      }
      state.remove(match);
    }
    final project = RegExp(
      r'(?:^|\s)@([A-Za-z0-9_-]{1,64})',
    ).firstMatch(state.text);
    if (project != null) {
      state.projectHint = project.group(1);
      state.remove(project);
    }
  }

  static DateTime? _resolveDate(_ParseState state, DateTime now) {
    final base = DayMath.dateOnly(now);
    if (state.date != null) {
      return state.time == null
          ? state.date
          : DateTime(
              state.date!.year,
              state.date!.month,
              state.date!.day,
              state.time!.hour,
              state.time!.minute,
            );
    }
    if (state.recurrenceWeekday != null) {
      final anchor = _nextWeekday(base, state.recurrenceWeekday!);
      return state.time == null
          ? anchor
          : DateTime(
              anchor.year,
              anchor.month,
              anchor.day,
              state.time!.hour,
              state.time!.minute,
            );
    }
    if (state.time != null) {
      var candidate = DateTime(
        base.year,
        base.month,
        base.day,
        state.time!.hour,
        state.time!.minute,
      );
      if (!candidate.isAfter(now)) {
        candidate = DayMath.addDays(candidate, 1);
      }
      return candidate;
    }
    if (state.recurrence != null) {
      return base;
    }
    return null;
  }

  static DateTime _startOfNextWeek(DateTime day) =>
      DayMath.addDays(DayMath.startOfWeek(day), 7);

  static DateTime _nextWeekday(DateTime day, int weekday) {
    final base = DayMath.dateOnly(day);
    final delta = (weekday - base.weekday + 7) % 7;
    return DayMath.addDays(base, delta);
  }

  static String _titleCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _ClockTime {
  const _ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;
}

class _ParseState {
  _ParseState(this.text);

  String text;
  DateTime? date;
  _ClockTime? time;
  String? recurrence;
  int? recurrenceWeekday;
  QuickAddPriority priority = QuickAddPriority.none;
  final List<String> tags = <String>[];
  String? projectHint;
  String? dateHint;

  bool take(RegExp pattern) {
    final match = pattern.firstMatch(text);
    if (match == null) return false;
    remove(match);
    return true;
  }

  void remove(Match match) {
    text = text.replaceRange(match.start, match.end, ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
  }

  String cleanTitle(String original) {
    var title = text.trim();
    title = title.replaceFirst(RegExp(r'^[\s,;:\-]+'), '');
    title = title.replaceFirst(RegExp(r'[\s,;:\-]+$'), '');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? original : title;
  }
}
