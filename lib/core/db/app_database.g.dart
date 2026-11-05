// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
    'end_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('general'),
  );
  static const VerificationMeta _hasReminderMeta = const VerificationMeta(
    'hasReminder',
  );
  @override
  late final GeneratedColumn<bool> hasReminder = GeneratedColumn<bool>(
    'has_reminder',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_reminder" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reminderMinutesMeta = const VerificationMeta(
    'reminderMinutes',
  );
  @override
  late final GeneratedColumn<int> reminderMinutes = GeneratedColumn<int>(
    'reminder_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(10),
  );
  static const VerificationMeta _recurrenceRuleMeta = const VerificationMeta(
    'recurrenceRule',
  );
  @override
  late final GeneratedColumn<String> recurrenceRule = GeneratedColumn<String>(
    'recurrence_rule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _allDayMeta = const VerificationMeta('allDay');
  @override
  late final GeneratedColumn<bool> allDay = GeneratedColumn<bool>(
    'all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _recurrenceEndMeta = const VerificationMeta(
    'recurrenceEnd',
  );
  @override
  late final GeneratedColumn<DateTime> recurrenceEnd =
      GeneratedColumn<DateTime>(
        'recurrence_end',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _recurrenceExceptionsMeta =
      const VerificationMeta('recurrenceExceptions');
  @override
  late final GeneratedColumn<String> recurrenceExceptions =
      GeneratedColumn<String>(
        'recurrence_exceptions',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    description,
    startTime,
    endTime,
    category,
    hasReminder,
    reminderMinutes,
    recurrenceRule,
    allDay,
    recurrenceEnd,
    recurrenceExceptions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('has_reminder')) {
      context.handle(
        _hasReminderMeta,
        hasReminder.isAcceptableOrUnknown(
          data['has_reminder']!,
          _hasReminderMeta,
        ),
      );
    }
    if (data.containsKey('reminder_minutes')) {
      context.handle(
        _reminderMinutesMeta,
        reminderMinutes.isAcceptableOrUnknown(
          data['reminder_minutes']!,
          _reminderMinutesMeta,
        ),
      );
    }
    if (data.containsKey('recurrence_rule')) {
      context.handle(
        _recurrenceRuleMeta,
        recurrenceRule.isAcceptableOrUnknown(
          data['recurrence_rule']!,
          _recurrenceRuleMeta,
        ),
      );
    }
    if (data.containsKey('all_day')) {
      context.handle(
        _allDayMeta,
        allDay.isAcceptableOrUnknown(data['all_day']!, _allDayMeta),
      );
    }
    if (data.containsKey('recurrence_end')) {
      context.handle(
        _recurrenceEndMeta,
        recurrenceEnd.isAcceptableOrUnknown(
          data['recurrence_end']!,
          _recurrenceEndMeta,
        ),
      );
    }
    if (data.containsKey('recurrence_exceptions')) {
      context.handle(
        _recurrenceExceptionsMeta,
        recurrenceExceptions.isAcceptableOrUnknown(
          data['recurrence_exceptions']!,
          _recurrenceExceptionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_time'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      hasReminder: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_reminder'],
      )!,
      reminderMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_minutes'],
      )!,
      recurrenceRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_rule'],
      ),
      allDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_day'],
      )!,
      recurrenceEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recurrence_end'],
      ),
      recurrenceExceptions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_exceptions'],
      )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class Event extends DataClass implements Insertable<Event> {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime? endTime;
  final String category;
  final bool hasReminder;
  final int reminderMinutes;

  /// Recurrence vocabulary (`daily`, `weekly`, ...); null or `none` means a
  /// one-off event.
  final String? recurrenceRule;

  /// Date-only event. The UI hides the clock, and reminders treat the start as
  /// all-day rather than a midnight appointment.
  final bool allDay;

  /// Last allowed occurrence start, inclusive. Covers RRULE `UNTIL` and a
  /// `COUNT` converted to an end date. Null means the series does not end.
  final DateTime? recurrenceEnd;

  /// JSON array of `YYYY-MM-DD` local dates removed from the series (EXDATE).
  final String recurrenceExceptions;
  const Event({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    this.endTime,
    required this.category,
    required this.hasReminder,
    required this.reminderMinutes,
    this.recurrenceRule,
    required this.allDay,
    this.recurrenceEnd,
    required this.recurrenceExceptions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['start_time'] = Variable<DateTime>(startTime);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    map['category'] = Variable<String>(category);
    map['has_reminder'] = Variable<bool>(hasReminder);
    map['reminder_minutes'] = Variable<int>(reminderMinutes);
    if (!nullToAbsent || recurrenceRule != null) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule);
    }
    map['all_day'] = Variable<bool>(allDay);
    if (!nullToAbsent || recurrenceEnd != null) {
      map['recurrence_end'] = Variable<DateTime>(recurrenceEnd);
    }
    map['recurrence_exceptions'] = Variable<String>(recurrenceExceptions);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      startTime: Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      category: Value(category),
      hasReminder: Value(hasReminder),
      reminderMinutes: Value(reminderMinutes),
      recurrenceRule: recurrenceRule == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceRule),
      allDay: Value(allDay),
      recurrenceEnd: recurrenceEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceEnd),
      recurrenceExceptions: Value(recurrenceExceptions),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      category: serializer.fromJson<String>(json['category']),
      hasReminder: serializer.fromJson<bool>(json['hasReminder']),
      reminderMinutes: serializer.fromJson<int>(json['reminderMinutes']),
      recurrenceRule: serializer.fromJson<String?>(json['recurrenceRule']),
      allDay: serializer.fromJson<bool>(json['allDay']),
      recurrenceEnd: serializer.fromJson<DateTime?>(json['recurrenceEnd']),
      recurrenceExceptions: serializer.fromJson<String>(
        json['recurrenceExceptions'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'category': serializer.toJson<String>(category),
      'hasReminder': serializer.toJson<bool>(hasReminder),
      'reminderMinutes': serializer.toJson<int>(reminderMinutes),
      'recurrenceRule': serializer.toJson<String?>(recurrenceRule),
      'allDay': serializer.toJson<bool>(allDay),
      'recurrenceEnd': serializer.toJson<DateTime?>(recurrenceEnd),
      'recurrenceExceptions': serializer.toJson<String>(recurrenceExceptions),
    };
  }

  Event copyWith({
    String? id,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? startTime,
    Value<DateTime?> endTime = const Value.absent(),
    String? category,
    bool? hasReminder,
    int? reminderMinutes,
    Value<String?> recurrenceRule = const Value.absent(),
    bool? allDay,
    Value<DateTime?> recurrenceEnd = const Value.absent(),
    String? recurrenceExceptions,
  }) => Event(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    startTime: startTime ?? this.startTime,
    endTime: endTime.present ? endTime.value : this.endTime,
    category: category ?? this.category,
    hasReminder: hasReminder ?? this.hasReminder,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    recurrenceRule: recurrenceRule.present
        ? recurrenceRule.value
        : this.recurrenceRule,
    allDay: allDay ?? this.allDay,
    recurrenceEnd: recurrenceEnd.present
        ? recurrenceEnd.value
        : this.recurrenceEnd,
    recurrenceExceptions: recurrenceExceptions ?? this.recurrenceExceptions,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      category: data.category.present ? data.category.value : this.category,
      hasReminder: data.hasReminder.present
          ? data.hasReminder.value
          : this.hasReminder,
      reminderMinutes: data.reminderMinutes.present
          ? data.reminderMinutes.value
          : this.reminderMinutes,
      recurrenceRule: data.recurrenceRule.present
          ? data.recurrenceRule.value
          : this.recurrenceRule,
      allDay: data.allDay.present ? data.allDay.value : this.allDay,
      recurrenceEnd: data.recurrenceEnd.present
          ? data.recurrenceEnd.value
          : this.recurrenceEnd,
      recurrenceExceptions: data.recurrenceExceptions.present
          ? data.recurrenceExceptions.value
          : this.recurrenceExceptions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('category: $category, ')
          ..write('hasReminder: $hasReminder, ')
          ..write('reminderMinutes: $reminderMinutes, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('allDay: $allDay, ')
          ..write('recurrenceEnd: $recurrenceEnd, ')
          ..write('recurrenceExceptions: $recurrenceExceptions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    startTime,
    endTime,
    category,
    hasReminder,
    reminderMinutes,
    recurrenceRule,
    allDay,
    recurrenceEnd,
    recurrenceExceptions,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.category == this.category &&
          other.hasReminder == this.hasReminder &&
          other.reminderMinutes == this.reminderMinutes &&
          other.recurrenceRule == this.recurrenceRule &&
          other.allDay == this.allDay &&
          other.recurrenceEnd == this.recurrenceEnd &&
          other.recurrenceExceptions == this.recurrenceExceptions);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime> startTime;
  final Value<DateTime?> endTime;
  final Value<String> category;
  final Value<bool> hasReminder;
  final Value<int> reminderMinutes;
  final Value<String?> recurrenceRule;
  final Value<bool> allDay;
  final Value<DateTime?> recurrenceEnd;
  final Value<String> recurrenceExceptions;
  final Value<int> rowid;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.category = const Value.absent(),
    this.hasReminder = const Value.absent(),
    this.reminderMinutes = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.allDay = const Value.absent(),
    this.recurrenceEnd = const Value.absent(),
    this.recurrenceExceptions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventsCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    required DateTime startTime,
    this.endTime = const Value.absent(),
    this.category = const Value.absent(),
    this.hasReminder = const Value.absent(),
    this.reminderMinutes = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.allDay = const Value.absent(),
    this.recurrenceEnd = const Value.absent(),
    this.recurrenceExceptions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       startTime = Value(startTime);
  static Insertable<Event> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<String>? category,
    Expression<bool>? hasReminder,
    Expression<int>? reminderMinutes,
    Expression<String>? recurrenceRule,
    Expression<bool>? allDay,
    Expression<DateTime>? recurrenceEnd,
    Expression<String>? recurrenceExceptions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (category != null) 'category': category,
      if (hasReminder != null) 'has_reminder': hasReminder,
      if (reminderMinutes != null) 'reminder_minutes': reminderMinutes,
      if (recurrenceRule != null) 'recurrence_rule': recurrenceRule,
      if (allDay != null) 'all_day': allDay,
      if (recurrenceEnd != null) 'recurrence_end': recurrenceEnd,
      if (recurrenceExceptions != null)
        'recurrence_exceptions': recurrenceExceptions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime>? startTime,
    Value<DateTime?>? endTime,
    Value<String>? category,
    Value<bool>? hasReminder,
    Value<int>? reminderMinutes,
    Value<String?>? recurrenceRule,
    Value<bool>? allDay,
    Value<DateTime?>? recurrenceEnd,
    Value<String>? recurrenceExceptions,
    Value<int>? rowid,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      category: category ?? this.category,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      allDay: allDay ?? this.allDay,
      recurrenceEnd: recurrenceEnd ?? this.recurrenceEnd,
      recurrenceExceptions: recurrenceExceptions ?? this.recurrenceExceptions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (hasReminder.present) {
      map['has_reminder'] = Variable<bool>(hasReminder.value);
    }
    if (reminderMinutes.present) {
      map['reminder_minutes'] = Variable<int>(reminderMinutes.value);
    }
    if (recurrenceRule.present) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule.value);
    }
    if (allDay.present) {
      map['all_day'] = Variable<bool>(allDay.value);
    }
    if (recurrenceEnd.present) {
      map['recurrence_end'] = Variable<DateTime>(recurrenceEnd.value);
    }
    if (recurrenceExceptions.present) {
      map['recurrence_exceptions'] = Variable<String>(
        recurrenceExceptions.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('category: $category, ')
          ..write('hasReminder: $hasReminder, ')
          ..write('reminderMinutes: $reminderMinutes, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('allDay: $allDay, ')
          ..write('recurrenceEnd: $recurrenceEnd, ')
          ..write('recurrenceExceptions: $recurrenceExceptions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetDateMeta = const VerificationMeta(
    'targetDate',
  );
  @override
  late final GeneratedColumn<DateTime> targetDate = GeneratedColumn<DateTime>(
    'target_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetProgressMeta = const VerificationMeta(
    'targetProgress',
  );
  @override
  late final GeneratedColumn<int> targetProgress = GeneratedColumn<int>(
    'target_progress',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(100),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    createdAt,
    targetDate,
    targetProgress,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<Project> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('target_date')) {
      context.handle(
        _targetDateMeta,
        targetDate.isAcceptableOrUnknown(data['target_date']!, _targetDateMeta),
      );
    }
    if (data.containsKey('target_progress')) {
      context.handle(
        _targetProgressMeta,
        targetProgress.isAcceptableOrUnknown(
          data['target_progress']!,
          _targetProgressMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      targetDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}target_date'],
      ),
      targetProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_progress'],
      )!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime? targetDate;
  final int targetProgress;
  const Project({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    this.targetDate,
    required this.targetProgress,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<DateTime>(targetDate);
    }
    map['target_progress'] = Variable<int>(targetProgress);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      targetProgress: Value(targetProgress),
    );
  }

  factory Project.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      targetDate: serializer.fromJson<DateTime?>(json['targetDate']),
      targetProgress: serializer.fromJson<int>(json['targetProgress']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'targetDate': serializer.toJson<DateTime?>(targetDate),
      'targetProgress': serializer.toJson<int>(targetProgress),
    };
  }

  Project copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> targetDate = const Value.absent(),
    int? targetProgress,
  }) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    targetDate: targetDate.present ? targetDate.value : this.targetDate,
    targetProgress: targetProgress ?? this.targetProgress,
  );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      targetDate: data.targetDate.present
          ? data.targetDate.value
          : this.targetDate,
      targetProgress: data.targetProgress.present
          ? data.targetProgress.value
          : this.targetProgress,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('targetDate: $targetDate, ')
          ..write('targetProgress: $targetProgress')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, description, createdAt, targetDate, targetProgress);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.targetDate == this.targetDate &&
          other.targetProgress == this.targetProgress);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime?> targetDate;
  final Value<int> targetProgress;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.targetProgress = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    required DateTime createdAt,
    this.targetDate = const Value.absent(),
    this.targetProgress = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Project> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? targetDate,
    Expression<int>? targetProgress,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (targetDate != null) 'target_date': targetDate,
      if (targetProgress != null) 'target_progress': targetProgress,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<DateTime?>? targetDate,
    Value<int>? targetProgress,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      targetDate: targetDate ?? this.targetDate,
      targetProgress: targetProgress ?? this.targetProgress,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (targetDate.present) {
      map['target_date'] = Variable<DateTime>(targetDate.value);
    }
    if (targetProgress.present) {
      map['target_progress'] = Variable<int>(targetProgress.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('targetDate: $targetDate, ')
          ..write('targetProgress: $targetProgress, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressLogsTable extends ProgressLogs
    with TableInfo<$ProgressLogsTable, ProgressLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'REFERENCES projects(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, projectId, value, note, timestamp];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgressLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $ProgressLogsTable createAlias(String alias) {
    return $ProgressLogsTable(attachedDatabase, alias);
  }
}

class ProgressLog extends DataClass implements Insertable<ProgressLog> {
  final String id;
  final String projectId;
  final int value;
  final String? note;
  final DateTime timestamp;
  const ProgressLog({
    required this.id,
    required this.projectId,
    required this.value,
    this.note,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['value'] = Variable<int>(value);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  ProgressLogsCompanion toCompanion(bool nullToAbsent) {
    return ProgressLogsCompanion(
      id: Value(id),
      projectId: Value(projectId),
      value: Value(value),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      timestamp: Value(timestamp),
    );
  }

  factory ProgressLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressLog(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      value: serializer.fromJson<int>(json['value']),
      note: serializer.fromJson<String?>(json['note']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'value': serializer.toJson<int>(value),
      'note': serializer.toJson<String?>(note),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  ProgressLog copyWith({
    String? id,
    String? projectId,
    int? value,
    Value<String?> note = const Value.absent(),
    DateTime? timestamp,
  }) => ProgressLog(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    value: value ?? this.value,
    note: note.present ? note.value : this.note,
    timestamp: timestamp ?? this.timestamp,
  );
  ProgressLog copyWithCompanion(ProgressLogsCompanion data) {
    return ProgressLog(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      value: data.value.present ? data.value.value : this.value,
      note: data.note.present ? data.note.value : this.note,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressLog(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('value: $value, ')
          ..write('note: $note, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, projectId, value, note, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressLog &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.value == this.value &&
          other.note == this.note &&
          other.timestamp == this.timestamp);
}

class ProgressLogsCompanion extends UpdateCompanion<ProgressLog> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<int> value;
  final Value<String?> note;
  final Value<DateTime> timestamp;
  final Value<int> rowid;
  const ProgressLogsCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.value = const Value.absent(),
    this.note = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressLogsCompanion.insert({
    required String id,
    required String projectId,
    required int value,
    this.note = const Value.absent(),
    required DateTime timestamp,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       value = Value(value),
       timestamp = Value(timestamp);
  static Insertable<ProgressLog> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<int>? value,
    Expression<String>? note,
    Expression<DateTime>? timestamp,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (value != null) 'value': value,
      if (note != null) 'note': note,
      if (timestamp != null) 'timestamp': timestamp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<int>? value,
    Value<String?>? note,
    Value<DateTime>? timestamp,
    Value<int>? rowid,
  }) {
    return ProgressLogsCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      value: value ?? this.value,
      note: note ?? this.note,
      timestamp: timestamp ?? this.timestamp,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressLogsCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('value: $value, ')
          ..write('note: $note, ')
          ..write('timestamp: $timestamp, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'REFERENCES projects(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusKeyMeta = const VerificationMeta(
    'statusKey',
  );
  @override
  late final GeneratedColumn<String> statusKey = GeneratedColumn<String>(
    'status_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('todo'),
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedMinutesMeta = const VerificationMeta(
    'estimatedMinutes',
  );
  @override
  late final GeneratedColumn<int> estimatedMinutes = GeneratedColumn<int>(
    'estimated_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    title,
    completed,
    statusKey,
    startDate,
    dueDate,
    estimatedMinutes,
    priority,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('status_key')) {
      context.handle(
        _statusKeyMeta,
        statusKey.isAcceptableOrUnknown(data['status_key']!, _statusKeyMeta),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('estimated_minutes')) {
      context.handle(
        _estimatedMinutesMeta,
        estimatedMinutes.isAcceptableOrUnknown(
          data['estimated_minutes']!,
          _estimatedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      statusKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_key'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      estimatedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_minutes'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String projectId;
  final String title;
  final bool completed;

  /// Canonical workflow status. `completed` remains the compatibility flag and
  /// is always derived from this key by the repository.
  final String statusKey;

  /// Optional planned start for the timeline. Date-only intent; the stored
  /// value is normalised to local midnight by the repository.
  final DateTime? startDate;

  /// Optional deadline.
  final DateTime? dueDate;

  /// Effort estimate in minutes. Never a calendar booking.
  final int? estimatedMinutes;

  /// Same stable vocabulary as the to-do priority: 0 none, 1 low, 2 medium,
  /// 3 high.
  final int priority;
  final int sortOrder;
  const Task({
    required this.id,
    required this.projectId,
    required this.title,
    required this.completed,
    required this.statusKey,
    this.startDate,
    this.dueDate,
    this.estimatedMinutes,
    required this.priority,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['title'] = Variable<String>(title);
    map['completed'] = Variable<bool>(completed);
    map['status_key'] = Variable<String>(statusKey);
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || estimatedMinutes != null) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes);
    }
    map['priority'] = Variable<int>(priority);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      projectId: Value(projectId),
      title: Value(title),
      completed: Value(completed),
      statusKey: Value(statusKey),
      startDate: startDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startDate),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      estimatedMinutes: estimatedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedMinutes),
      priority: Value(priority),
      sortOrder: Value(sortOrder),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      title: serializer.fromJson<String>(json['title']),
      completed: serializer.fromJson<bool>(json['completed']),
      statusKey: serializer.fromJson<String>(json['statusKey']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      priority: serializer.fromJson<int>(json['priority']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'title': serializer.toJson<String>(title),
      'completed': serializer.toJson<bool>(completed),
      'statusKey': serializer.toJson<String>(statusKey),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'priority': serializer.toJson<int>(priority),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Task copyWith({
    String? id,
    String? projectId,
    String? title,
    bool? completed,
    String? statusKey,
    Value<DateTime?> startDate = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<int?> estimatedMinutes = const Value.absent(),
    int? priority,
    int? sortOrder,
  }) => Task(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    title: title ?? this.title,
    completed: completed ?? this.completed,
    statusKey: statusKey ?? this.statusKey,
    startDate: startDate.present ? startDate.value : this.startDate,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    priority: priority ?? this.priority,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      title: data.title.present ? data.title.value : this.title,
      completed: data.completed.present ? data.completed.value : this.completed,
      statusKey: data.statusKey.present ? data.statusKey.value : this.statusKey,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      estimatedMinutes: data.estimatedMinutes.present
          ? data.estimatedMinutes.value
          : this.estimatedMinutes,
      priority: data.priority.present ? data.priority.value : this.priority,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('completed: $completed, ')
          ..write('statusKey: $statusKey, ')
          ..write('startDate: $startDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('priority: $priority, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    title,
    completed,
    statusKey,
    startDate,
    dueDate,
    estimatedMinutes,
    priority,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.title == this.title &&
          other.completed == this.completed &&
          other.statusKey == this.statusKey &&
          other.startDate == this.startDate &&
          other.dueDate == this.dueDate &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.priority == this.priority &&
          other.sortOrder == this.sortOrder);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> title;
  final Value<bool> completed;
  final Value<String> statusKey;
  final Value<DateTime?> startDate;
  final Value<DateTime?> dueDate;
  final Value<int?> estimatedMinutes;
  final Value<int> priority;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.title = const Value.absent(),
    this.completed = const Value.absent(),
    this.statusKey = const Value.absent(),
    this.startDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.priority = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String projectId,
    required String title,
    this.completed = const Value.absent(),
    this.statusKey = const Value.absent(),
    this.startDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.priority = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       title = Value(title);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? title,
    Expression<bool>? completed,
    Expression<String>? statusKey,
    Expression<DateTime>? startDate,
    Expression<DateTime>? dueDate,
    Expression<int>? estimatedMinutes,
    Expression<int>? priority,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (title != null) 'title': title,
      if (completed != null) 'completed': completed,
      if (statusKey != null) 'status_key': statusKey,
      if (startDate != null) 'start_date': startDate,
      if (dueDate != null) 'due_date': dueDate,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (priority != null) 'priority': priority,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String>? title,
    Value<bool>? completed,
    Value<String>? statusKey,
    Value<DateTime?>? startDate,
    Value<DateTime?>? dueDate,
    Value<int?>? estimatedMinutes,
    Value<int>? priority,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      statusKey: statusKey ?? this.statusKey,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      priority: priority ?? this.priority,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (statusKey.present) {
      map['status_key'] = Variable<String>(statusKey.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (estimatedMinutes.present) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('completed: $completed, ')
          ..write('statusKey: $statusKey, ')
          ..write('startDate: $startDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('priority: $priority, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiaryEntriesTable extends DiaryEntries
    with TableInfo<$DiaryEntriesTable, DiaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<int> mood = GeneratedColumn<int>(
    'mood',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, date, mood, content];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diary_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    } else if (isInserting) {
      context.missing(_moodMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mood'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
    );
  }

  @override
  $DiaryEntriesTable createAlias(String alias) {
    return $DiaryEntriesTable(attachedDatabase, alias);
  }
}

class DiaryEntry extends DataClass implements Insertable<DiaryEntry> {
  final String id;
  final DateTime date;
  final int mood;
  final String content;
  const DiaryEntry({
    required this.id,
    required this.date,
    required this.mood,
    required this.content,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<DateTime>(date);
    map['mood'] = Variable<int>(mood);
    map['content'] = Variable<String>(content);
    return map;
  }

  DiaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return DiaryEntriesCompanion(
      id: Value(id),
      date: Value(date),
      mood: Value(mood),
      content: Value(content),
    );
  }

  factory DiaryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryEntry(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      mood: serializer.fromJson<int>(json['mood']),
      content: serializer.fromJson<String>(json['content']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<DateTime>(date),
      'mood': serializer.toJson<int>(mood),
      'content': serializer.toJson<String>(content),
    };
  }

  DiaryEntry copyWith({
    String? id,
    DateTime? date,
    int? mood,
    String? content,
  }) => DiaryEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    mood: mood ?? this.mood,
    content: content ?? this.content,
  );
  DiaryEntry copyWithCompanion(DiaryEntriesCompanion data) {
    return DiaryEntry(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      mood: data.mood.present ? data.mood.value : this.mood,
      content: data.content.present ? data.content.value : this.content,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntry(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('mood: $mood, ')
          ..write('content: $content')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, date, mood, content);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryEntry &&
          other.id == this.id &&
          other.date == this.date &&
          other.mood == this.mood &&
          other.content == this.content);
}

class DiaryEntriesCompanion extends UpdateCompanion<DiaryEntry> {
  final Value<String> id;
  final Value<DateTime> date;
  final Value<int> mood;
  final Value<String> content;
  final Value<int> rowid;
  const DiaryEntriesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.mood = const Value.absent(),
    this.content = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiaryEntriesCompanion.insert({
    required String id,
    required DateTime date,
    required int mood,
    required String content,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       mood = Value(mood),
       content = Value(content);
  static Insertable<DiaryEntry> custom({
    Expression<String>? id,
    Expression<DateTime>? date,
    Expression<int>? mood,
    Expression<String>? content,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (mood != null) 'mood': mood,
      if (content != null) 'content': content,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiaryEntriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? date,
    Value<int>? mood,
    Value<String>? content,
    Value<int>? rowid,
  }) {
    return DiaryEntriesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      mood: mood ?? this.mood,
      content: content ?? this.content,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (mood.present) {
      map['mood'] = Variable<int>(mood.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('mood: $mood, ')
          ..write('content: $content, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HabitsTable extends Habits with TableInfo<$HabitsTable, Habit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HabitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('🔥'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetPerWeekMeta = const VerificationMeta(
    'targetPerWeek',
  );
  @override
  late final GeneratedColumn<int> targetPerWeek = GeneratedColumn<int>(
    'target_per_week',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(5),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    icon,
    createdAt,
    targetPerWeek,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'habits';
  @override
  VerificationContext validateIntegrity(
    Insertable<Habit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('target_per_week')) {
      context.handle(
        _targetPerWeekMeta,
        targetPerWeek.isAcceptableOrUnknown(
          data['target_per_week']!,
          _targetPerWeekMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Habit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Habit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      targetPerWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_per_week'],
      )!,
    );
  }

  @override
  $HabitsTable createAlias(String alias) {
    return $HabitsTable(attachedDatabase, alias);
  }
}

class Habit extends DataClass implements Insertable<Habit> {
  final String id;
  final String name;
  final String icon;
  final DateTime createdAt;
  final int targetPerWeek;
  const Habit({
    required this.id,
    required this.name,
    required this.icon,
    required this.createdAt,
    required this.targetPerWeek,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['target_per_week'] = Variable<int>(targetPerWeek);
    return map;
  }

  HabitsCompanion toCompanion(bool nullToAbsent) {
    return HabitsCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      createdAt: Value(createdAt),
      targetPerWeek: Value(targetPerWeek),
    );
  }

  factory Habit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Habit(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      targetPerWeek: serializer.fromJson<int>(json['targetPerWeek']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'targetPerWeek': serializer.toJson<int>(targetPerWeek),
    };
  }

  Habit copyWith({
    String? id,
    String? name,
    String? icon,
    DateTime? createdAt,
    int? targetPerWeek,
  }) => Habit(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    createdAt: createdAt ?? this.createdAt,
    targetPerWeek: targetPerWeek ?? this.targetPerWeek,
  );
  Habit copyWithCompanion(HabitsCompanion data) {
    return Habit(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      targetPerWeek: data.targetPerWeek.present
          ? data.targetPerWeek.value
          : this.targetPerWeek,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Habit(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('createdAt: $createdAt, ')
          ..write('targetPerWeek: $targetPerWeek')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, icon, createdAt, targetPerWeek);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Habit &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.createdAt == this.createdAt &&
          other.targetPerWeek == this.targetPerWeek);
}

class HabitsCompanion extends UpdateCompanion<Habit> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<DateTime> createdAt;
  final Value<int> targetPerWeek;
  final Value<int> rowid;
  const HabitsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.targetPerWeek = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HabitsCompanion.insert({
    required String id,
    required String name,
    this.icon = const Value.absent(),
    required DateTime createdAt,
    this.targetPerWeek = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Habit> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<DateTime>? createdAt,
    Expression<int>? targetPerWeek,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (createdAt != null) 'created_at': createdAt,
      if (targetPerWeek != null) 'target_per_week': targetPerWeek,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HabitsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<DateTime>? createdAt,
    Value<int>? targetPerWeek,
    Value<int>? rowid,
  }) {
    return HabitsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      targetPerWeek: targetPerWeek ?? this.targetPerWeek,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (targetPerWeek.present) {
      map['target_per_week'] = Variable<int>(targetPerWeek.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HabitsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('createdAt: $createdAt, ')
          ..write('targetPerWeek: $targetPerWeek, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HabitLogsTable extends HabitLogs
    with TableInfo<$HabitLogsTable, HabitLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HabitLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _habitIdMeta = const VerificationMeta(
    'habitId',
  );
  @override
  late final GeneratedColumn<String> habitId = GeneratedColumn<String>(
    'habit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'REFERENCES habits(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, habitId, date, completed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'habit_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<HabitLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('habit_id')) {
      context.handle(
        _habitIdMeta,
        habitId.isAcceptableOrUnknown(data['habit_id']!, _habitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_habitIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HabitLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HabitLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      habitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}habit_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
    );
  }

  @override
  $HabitLogsTable createAlias(String alias) {
    return $HabitLogsTable(attachedDatabase, alias);
  }
}

class HabitLog extends DataClass implements Insertable<HabitLog> {
  final String id;
  final String habitId;
  final DateTime date;
  final bool completed;
  const HabitLog({
    required this.id,
    required this.habitId,
    required this.date,
    required this.completed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['habit_id'] = Variable<String>(habitId);
    map['date'] = Variable<DateTime>(date);
    map['completed'] = Variable<bool>(completed);
    return map;
  }

  HabitLogsCompanion toCompanion(bool nullToAbsent) {
    return HabitLogsCompanion(
      id: Value(id),
      habitId: Value(habitId),
      date: Value(date),
      completed: Value(completed),
    );
  }

  factory HabitLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HabitLog(
      id: serializer.fromJson<String>(json['id']),
      habitId: serializer.fromJson<String>(json['habitId']),
      date: serializer.fromJson<DateTime>(json['date']),
      completed: serializer.fromJson<bool>(json['completed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'habitId': serializer.toJson<String>(habitId),
      'date': serializer.toJson<DateTime>(date),
      'completed': serializer.toJson<bool>(completed),
    };
  }

  HabitLog copyWith({
    String? id,
    String? habitId,
    DateTime? date,
    bool? completed,
  }) => HabitLog(
    id: id ?? this.id,
    habitId: habitId ?? this.habitId,
    date: date ?? this.date,
    completed: completed ?? this.completed,
  );
  HabitLog copyWithCompanion(HabitLogsCompanion data) {
    return HabitLog(
      id: data.id.present ? data.id.value : this.id,
      habitId: data.habitId.present ? data.habitId.value : this.habitId,
      date: data.date.present ? data.date.value : this.date,
      completed: data.completed.present ? data.completed.value : this.completed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HabitLog(')
          ..write('id: $id, ')
          ..write('habitId: $habitId, ')
          ..write('date: $date, ')
          ..write('completed: $completed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, habitId, date, completed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HabitLog &&
          other.id == this.id &&
          other.habitId == this.habitId &&
          other.date == this.date &&
          other.completed == this.completed);
}

class HabitLogsCompanion extends UpdateCompanion<HabitLog> {
  final Value<String> id;
  final Value<String> habitId;
  final Value<DateTime> date;
  final Value<bool> completed;
  final Value<int> rowid;
  const HabitLogsCompanion({
    this.id = const Value.absent(),
    this.habitId = const Value.absent(),
    this.date = const Value.absent(),
    this.completed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HabitLogsCompanion.insert({
    required String id,
    required String habitId,
    required DateTime date,
    this.completed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       habitId = Value(habitId),
       date = Value(date);
  static Insertable<HabitLog> custom({
    Expression<String>? id,
    Expression<String>? habitId,
    Expression<DateTime>? date,
    Expression<bool>? completed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (habitId != null) 'habit_id': habitId,
      if (date != null) 'date': date,
      if (completed != null) 'completed': completed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HabitLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? habitId,
    Value<DateTime>? date,
    Value<bool>? completed,
    Value<int>? rowid,
  }) {
    return HabitLogsCompanion(
      id: id ?? this.id,
      habitId: habitId ?? this.habitId,
      date: date ?? this.date,
      completed: completed ?? this.completed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (habitId.present) {
      map['habit_id'] = Variable<String>(habitId.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HabitLogsCompanion(')
          ..write('id: $id, ')
          ..write('habitId: $habitId, ')
          ..write('date: $date, ')
          ..write('completed: $completed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusSessionsTable extends FocusSessions
    with TableInfo<$FocusSessionsTable, FocusSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES projects(id) ON DELETE SET NULL',
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMinutesMeta = const VerificationMeta(
    'durationMinutes',
  );
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
    'duration_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    startTime,
    durationMinutes,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
        _durationMinutesMeta,
        durationMinutes.isAcceptableOrUnknown(
          data['duration_minutes']!,
          _durationMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationMinutesMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FocusSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_time'],
      )!,
      durationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_minutes'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $FocusSessionsTable createAlias(String alias) {
    return $FocusSessionsTable(attachedDatabase, alias);
  }
}

class FocusSession extends DataClass implements Insertable<FocusSession> {
  final String id;
  final String? projectId;
  final DateTime startTime;
  final int durationMinutes;
  final String? note;
  const FocusSession({
    required this.id,
    this.projectId,
    required this.startTime,
    required this.durationMinutes,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    map['start_time'] = Variable<DateTime>(startTime);
    map['duration_minutes'] = Variable<int>(durationMinutes);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  FocusSessionsCompanion toCompanion(bool nullToAbsent) {
    return FocusSessionsCompanion(
      id: Value(id),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      startTime: Value(startTime),
      durationMinutes: Value(durationMinutes),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory FocusSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSession(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      durationMinutes: serializer.fromJson<int>(json['durationMinutes']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String?>(projectId),
      'startTime': serializer.toJson<DateTime>(startTime),
      'durationMinutes': serializer.toJson<int>(durationMinutes),
      'note': serializer.toJson<String?>(note),
    };
  }

  FocusSession copyWith({
    String? id,
    Value<String?> projectId = const Value.absent(),
    DateTime? startTime,
    int? durationMinutes,
    Value<String?> note = const Value.absent(),
  }) => FocusSession(
    id: id ?? this.id,
    projectId: projectId.present ? projectId.value : this.projectId,
    startTime: startTime ?? this.startTime,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    note: note.present ? note.value : this.note,
  );
  FocusSession copyWithCompanion(FocusSessionsCompanion data) {
    return FocusSession(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSession(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('startTime: $startTime, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, projectId, startTime, durationMinutes, note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSession &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.startTime == this.startTime &&
          other.durationMinutes == this.durationMinutes &&
          other.note == this.note);
}

class FocusSessionsCompanion extends UpdateCompanion<FocusSession> {
  final Value<String> id;
  final Value<String?> projectId;
  final Value<DateTime> startTime;
  final Value<int> durationMinutes;
  final Value<String?> note;
  final Value<int> rowid;
  const FocusSessionsCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.startTime = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusSessionsCompanion.insert({
    required String id,
    this.projectId = const Value.absent(),
    required DateTime startTime,
    required int durationMinutes,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startTime = Value(startTime),
       durationMinutes = Value(durationMinutes);
  static Insertable<FocusSession> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<DateTime>? startTime,
    Expression<int>? durationMinutes,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (startTime != null) 'start_time': startTime,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusSessionsCompanion copyWith({
    Value<String>? id,
    Value<String?>? projectId,
    Value<DateTime>? startTime,
    Value<int>? durationMinutes,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return FocusSessionsCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      startTime: startTime ?? this.startTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSessionsCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('startTime: $startTime, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoItemsTable extends TodoItems
    with TableInfo<$TodoItemsTable, TodoItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _recurrenceRuleMeta = const VerificationMeta(
    'recurrenceRule',
  );
  @override
  late final GeneratedColumn<String> recurrenceRule = GeneratedColumn<String>(
    'recurrence_rule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES projects(id) ON DELETE SET NULL',
  );
  static const VerificationMeta _reminderAtMeta = const VerificationMeta(
    'reminderAt',
  );
  @override
  late final GeneratedColumn<DateTime> reminderAt = GeneratedColumn<DateTime>(
    'reminder_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedMinutesMeta = const VerificationMeta(
    'estimatedMinutes',
  );
  @override
  late final GeneratedColumn<int> estimatedMinutes = GeneratedColumn<int>(
    'estimated_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isImportantMeta = const VerificationMeta(
    'isImportant',
  );
  @override
  late final GeneratedColumn<bool> isImportant = GeneratedColumn<bool>(
    'is_important',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_important" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _urgencyOverrideMeta = const VerificationMeta(
    'urgencyOverride',
  );
  @override
  late final GeneratedColumn<bool> urgencyOverride = GeneratedColumn<bool>(
    'urgency_override',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("urgency_override" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    notes,
    completed,
    createdAt,
    startDate,
    dueDate,
    priority,
    tags,
    recurrenceRule,
    parentId,
    projectId,
    reminderAt,
    estimatedMinutes,
    isImportant,
    urgencyOverride,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('recurrence_rule')) {
      context.handle(
        _recurrenceRuleMeta,
        recurrenceRule.isAcceptableOrUnknown(
          data['recurrence_rule']!,
          _recurrenceRuleMeta,
        ),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('reminder_at')) {
      context.handle(
        _reminderAtMeta,
        reminderAt.isAcceptableOrUnknown(data['reminder_at']!, _reminderAtMeta),
      );
    }
    if (data.containsKey('estimated_minutes')) {
      context.handle(
        _estimatedMinutesMeta,
        estimatedMinutes.isAcceptableOrUnknown(
          data['estimated_minutes']!,
          _estimatedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('is_important')) {
      context.handle(
        _isImportantMeta,
        isImportant.isAcceptableOrUnknown(
          data['is_important']!,
          _isImportantMeta,
        ),
      );
    }
    if (data.containsKey('urgency_override')) {
      context.handle(
        _urgencyOverrideMeta,
        urgencyOverride.isAcceptableOrUnknown(
          data['urgency_override']!,
          _urgencyOverrideMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TodoItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      recurrenceRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_rule'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      reminderAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reminder_at'],
      ),
      estimatedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_minutes'],
      ),
      isImportant: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_important'],
      )!,
      urgencyOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}urgency_override'],
      ),
    );
  }

  @override
  $TodoItemsTable createAlias(String alias) {
    return $TodoItemsTable(attachedDatabase, alias);
  }
}

class TodoItem extends DataClass implements Insertable<TodoItem> {
  final String id;
  final String title;

  /// Long-form details that should travel with the task but not crowd its
  /// one-line title.
  final String? notes;
  final bool completed;
  final DateTime createdAt;

  /// When work may start. A task is scheduled as soon as either this or
  /// [dueDate] is set; with neither it is explicitly unscheduled.
  final DateTime? startDate;
  final DateTime? dueDate;

  /// 0 = none, 1 = low, 2 = medium, 3 = high (see `TaskPriority`).
  final int priority;

  /// JSON array of free-form tag names. Stored as text so a tag set needs no
  /// join table and travels with backups and sync payloads.
  final String tags;

  /// Reuses the planner's recurrence vocabulary (`daily`, `weekly`, ...).
  final String? recurrenceRule;

  /// The task this one is a subtask of. Deleting a parent removes its subtasks.
  final String? parentId;

  /// Optional link to a project. Deleting the project unlinks the task rather
  /// than deleting it, because the task also exists independently.
  final String? projectId;

  /// Exact moment to show a reminder. Null means the task has no reminder.
  final DateTime? reminderAt;

  /// Optional effort estimate used by capacity calculations. This is an
  /// estimate, not a booking: actual calendar time lives in
  /// [TaskScheduleBlocks].
  final int? estimatedMinutes;

  /// User-assigned importance, used only by the Eisenhower matrix. It is never
  /// inferred from priority.
  final bool isImportant;

  /// User override for the derived urgency. Null means "use the due-date
  /// window"; true/false pins the task to urgent/not urgent.
  final bool? urgencyOverride;
  const TodoItem({
    required this.id,
    required this.title,
    this.notes,
    required this.completed,
    required this.createdAt,
    this.startDate,
    this.dueDate,
    required this.priority,
    required this.tags,
    this.recurrenceRule,
    this.parentId,
    this.projectId,
    this.reminderAt,
    this.estimatedMinutes,
    required this.isImportant,
    this.urgencyOverride,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['completed'] = Variable<bool>(completed);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    map['priority'] = Variable<int>(priority);
    map['tags'] = Variable<String>(tags);
    if (!nullToAbsent || recurrenceRule != null) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || reminderAt != null) {
      map['reminder_at'] = Variable<DateTime>(reminderAt);
    }
    if (!nullToAbsent || estimatedMinutes != null) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes);
    }
    map['is_important'] = Variable<bool>(isImportant);
    if (!nullToAbsent || urgencyOverride != null) {
      map['urgency_override'] = Variable<bool>(urgencyOverride);
    }
    return map;
  }

  TodoItemsCompanion toCompanion(bool nullToAbsent) {
    return TodoItemsCompanion(
      id: Value(id),
      title: Value(title),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      completed: Value(completed),
      createdAt: Value(createdAt),
      startDate: startDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startDate),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      priority: Value(priority),
      tags: Value(tags),
      recurrenceRule: recurrenceRule == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceRule),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      reminderAt: reminderAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderAt),
      estimatedMinutes: estimatedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedMinutes),
      isImportant: Value(isImportant),
      urgencyOverride: urgencyOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(urgencyOverride),
    );
  }

  factory TodoItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoItem(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String?>(json['notes']),
      completed: serializer.fromJson<bool>(json['completed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      priority: serializer.fromJson<int>(json['priority']),
      tags: serializer.fromJson<String>(json['tags']),
      recurrenceRule: serializer.fromJson<String?>(json['recurrenceRule']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      reminderAt: serializer.fromJson<DateTime?>(json['reminderAt']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      isImportant: serializer.fromJson<bool>(json['isImportant']),
      urgencyOverride: serializer.fromJson<bool?>(json['urgencyOverride']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String?>(notes),
      'completed': serializer.toJson<bool>(completed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'priority': serializer.toJson<int>(priority),
      'tags': serializer.toJson<String>(tags),
      'recurrenceRule': serializer.toJson<String?>(recurrenceRule),
      'parentId': serializer.toJson<String?>(parentId),
      'projectId': serializer.toJson<String?>(projectId),
      'reminderAt': serializer.toJson<DateTime?>(reminderAt),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'isImportant': serializer.toJson<bool>(isImportant),
      'urgencyOverride': serializer.toJson<bool?>(urgencyOverride),
    };
  }

  TodoItem copyWith({
    String? id,
    String? title,
    Value<String?> notes = const Value.absent(),
    bool? completed,
    DateTime? createdAt,
    Value<DateTime?> startDate = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    int? priority,
    String? tags,
    Value<String?> recurrenceRule = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    Value<String?> projectId = const Value.absent(),
    Value<DateTime?> reminderAt = const Value.absent(),
    Value<int?> estimatedMinutes = const Value.absent(),
    bool? isImportant,
    Value<bool?> urgencyOverride = const Value.absent(),
  }) => TodoItem(
    id: id ?? this.id,
    title: title ?? this.title,
    notes: notes.present ? notes.value : this.notes,
    completed: completed ?? this.completed,
    createdAt: createdAt ?? this.createdAt,
    startDate: startDate.present ? startDate.value : this.startDate,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    priority: priority ?? this.priority,
    tags: tags ?? this.tags,
    recurrenceRule: recurrenceRule.present
        ? recurrenceRule.value
        : this.recurrenceRule,
    parentId: parentId.present ? parentId.value : this.parentId,
    projectId: projectId.present ? projectId.value : this.projectId,
    reminderAt: reminderAt.present ? reminderAt.value : this.reminderAt,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    isImportant: isImportant ?? this.isImportant,
    urgencyOverride: urgencyOverride.present
        ? urgencyOverride.value
        : this.urgencyOverride,
  );
  TodoItem copyWithCompanion(TodoItemsCompanion data) {
    return TodoItem(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      completed: data.completed.present ? data.completed.value : this.completed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      priority: data.priority.present ? data.priority.value : this.priority,
      tags: data.tags.present ? data.tags.value : this.tags,
      recurrenceRule: data.recurrenceRule.present
          ? data.recurrenceRule.value
          : this.recurrenceRule,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      reminderAt: data.reminderAt.present
          ? data.reminderAt.value
          : this.reminderAt,
      estimatedMinutes: data.estimatedMinutes.present
          ? data.estimatedMinutes.value
          : this.estimatedMinutes,
      isImportant: data.isImportant.present
          ? data.isImportant.value
          : this.isImportant,
      urgencyOverride: data.urgencyOverride.present
          ? data.urgencyOverride.value
          : this.urgencyOverride,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoItem(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('completed: $completed, ')
          ..write('createdAt: $createdAt, ')
          ..write('startDate: $startDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('priority: $priority, ')
          ..write('tags: $tags, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('parentId: $parentId, ')
          ..write('projectId: $projectId, ')
          ..write('reminderAt: $reminderAt, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('isImportant: $isImportant, ')
          ..write('urgencyOverride: $urgencyOverride')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    completed,
    createdAt,
    startDate,
    dueDate,
    priority,
    tags,
    recurrenceRule,
    parentId,
    projectId,
    reminderAt,
    estimatedMinutes,
    isImportant,
    urgencyOverride,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoItem &&
          other.id == this.id &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.completed == this.completed &&
          other.createdAt == this.createdAt &&
          other.startDate == this.startDate &&
          other.dueDate == this.dueDate &&
          other.priority == this.priority &&
          other.tags == this.tags &&
          other.recurrenceRule == this.recurrenceRule &&
          other.parentId == this.parentId &&
          other.projectId == this.projectId &&
          other.reminderAt == this.reminderAt &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.isImportant == this.isImportant &&
          other.urgencyOverride == this.urgencyOverride);
}

class TodoItemsCompanion extends UpdateCompanion<TodoItem> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> notes;
  final Value<bool> completed;
  final Value<DateTime> createdAt;
  final Value<DateTime?> startDate;
  final Value<DateTime?> dueDate;
  final Value<int> priority;
  final Value<String> tags;
  final Value<String?> recurrenceRule;
  final Value<String?> parentId;
  final Value<String?> projectId;
  final Value<DateTime?> reminderAt;
  final Value<int?> estimatedMinutes;
  final Value<bool> isImportant;
  final Value<bool?> urgencyOverride;
  final Value<int> rowid;
  const TodoItemsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.completed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.startDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.priority = const Value.absent(),
    this.tags = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.parentId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.reminderAt = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.isImportant = const Value.absent(),
    this.urgencyOverride = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoItemsCompanion.insert({
    required String id,
    required String title,
    this.notes = const Value.absent(),
    this.completed = const Value.absent(),
    required DateTime createdAt,
    this.startDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.priority = const Value.absent(),
    this.tags = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.parentId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.reminderAt = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.isImportant = const Value.absent(),
    this.urgencyOverride = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt);
  static Insertable<TodoItem> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<bool>? completed,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? startDate,
    Expression<DateTime>? dueDate,
    Expression<int>? priority,
    Expression<String>? tags,
    Expression<String>? recurrenceRule,
    Expression<String>? parentId,
    Expression<String>? projectId,
    Expression<DateTime>? reminderAt,
    Expression<int>? estimatedMinutes,
    Expression<bool>? isImportant,
    Expression<bool>? urgencyOverride,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (completed != null) 'completed': completed,
      if (createdAt != null) 'created_at': createdAt,
      if (startDate != null) 'start_date': startDate,
      if (dueDate != null) 'due_date': dueDate,
      if (priority != null) 'priority': priority,
      if (tags != null) 'tags': tags,
      if (recurrenceRule != null) 'recurrence_rule': recurrenceRule,
      if (parentId != null) 'parent_id': parentId,
      if (projectId != null) 'project_id': projectId,
      if (reminderAt != null) 'reminder_at': reminderAt,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (isImportant != null) 'is_important': isImportant,
      if (urgencyOverride != null) 'urgency_override': urgencyOverride,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? notes,
    Value<bool>? completed,
    Value<DateTime>? createdAt,
    Value<DateTime?>? startDate,
    Value<DateTime?>? dueDate,
    Value<int>? priority,
    Value<String>? tags,
    Value<String?>? recurrenceRule,
    Value<String?>? parentId,
    Value<String?>? projectId,
    Value<DateTime?>? reminderAt,
    Value<int?>? estimatedMinutes,
    Value<bool>? isImportant,
    Value<bool?>? urgencyOverride,
    Value<int>? rowid,
  }) {
    return TodoItemsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      parentId: parentId ?? this.parentId,
      projectId: projectId ?? this.projectId,
      reminderAt: reminderAt ?? this.reminderAt,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      isImportant: isImportant ?? this.isImportant,
      urgencyOverride: urgencyOverride ?? this.urgencyOverride,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (recurrenceRule.present) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (reminderAt.present) {
      map['reminder_at'] = Variable<DateTime>(reminderAt.value);
    }
    if (estimatedMinutes.present) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes.value);
    }
    if (isImportant.present) {
      map['is_important'] = Variable<bool>(isImportant.value);
    }
    if (urgencyOverride.present) {
      map['urgency_override'] = Variable<bool>(urgencyOverride.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoItemsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('completed: $completed, ')
          ..write('createdAt: $createdAt, ')
          ..write('startDate: $startDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('priority: $priority, ')
          ..write('tags: $tags, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('parentId: $parentId, ')
          ..write('projectId: $projectId, ')
          ..write('reminderAt: $reminderAt, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('isImportant: $isImportant, ')
          ..write('urgencyOverride: $urgencyOverride, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoCompletionsTable extends TodoCompletions
    with TableInfo<$TodoCompletionsTable, TodoCompletion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoCompletionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _todoIdMeta = const VerificationMeta('todoId');
  @override
  late final GeneratedColumn<String> todoId = GeneratedColumn<String>(
    'todo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _occurrenceDueMeta = const VerificationMeta(
    'occurrenceDue',
  );
  @override
  late final GeneratedColumn<DateTime> occurrenceDue =
      GeneratedColumn<DateTime>(
        'occurrence_due',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    todoId,
    occurrenceDue,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_completions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoCompletion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('todo_id')) {
      context.handle(
        _todoIdMeta,
        todoId.isAcceptableOrUnknown(data['todo_id']!, _todoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_todoIdMeta);
    }
    if (data.containsKey('occurrence_due')) {
      context.handle(
        _occurrenceDueMeta,
        occurrenceDue.isAcceptableOrUnknown(
          data['occurrence_due']!,
          _occurrenceDueMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TodoCompletion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoCompletion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      todoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}todo_id'],
      )!,
      occurrenceDue: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurrence_due'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      )!,
    );
  }

  @override
  $TodoCompletionsTable createAlias(String alias) {
    return $TodoCompletionsTable(attachedDatabase, alias);
  }
}

class TodoCompletion extends DataClass implements Insertable<TodoCompletion> {
  final String id;
  final String todoId;

  /// Due date of the occurrence that was completed. Null when the task had no
  /// due date (which cannot advance, so no row is normally written).
  final DateTime? occurrenceDue;
  final DateTime completedAt;
  const TodoCompletion({
    required this.id,
    required this.todoId,
    this.occurrenceDue,
    required this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['todo_id'] = Variable<String>(todoId);
    if (!nullToAbsent || occurrenceDue != null) {
      map['occurrence_due'] = Variable<DateTime>(occurrenceDue);
    }
    map['completed_at'] = Variable<DateTime>(completedAt);
    return map;
  }

  TodoCompletionsCompanion toCompanion(bool nullToAbsent) {
    return TodoCompletionsCompanion(
      id: Value(id),
      todoId: Value(todoId),
      occurrenceDue: occurrenceDue == null && nullToAbsent
          ? const Value.absent()
          : Value(occurrenceDue),
      completedAt: Value(completedAt),
    );
  }

  factory TodoCompletion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoCompletion(
      id: serializer.fromJson<String>(json['id']),
      todoId: serializer.fromJson<String>(json['todoId']),
      occurrenceDue: serializer.fromJson<DateTime?>(json['occurrenceDue']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'todoId': serializer.toJson<String>(todoId),
      'occurrenceDue': serializer.toJson<DateTime?>(occurrenceDue),
      'completedAt': serializer.toJson<DateTime>(completedAt),
    };
  }

  TodoCompletion copyWith({
    String? id,
    String? todoId,
    Value<DateTime?> occurrenceDue = const Value.absent(),
    DateTime? completedAt,
  }) => TodoCompletion(
    id: id ?? this.id,
    todoId: todoId ?? this.todoId,
    occurrenceDue: occurrenceDue.present
        ? occurrenceDue.value
        : this.occurrenceDue,
    completedAt: completedAt ?? this.completedAt,
  );
  TodoCompletion copyWithCompanion(TodoCompletionsCompanion data) {
    return TodoCompletion(
      id: data.id.present ? data.id.value : this.id,
      todoId: data.todoId.present ? data.todoId.value : this.todoId,
      occurrenceDue: data.occurrenceDue.present
          ? data.occurrenceDue.value
          : this.occurrenceDue,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoCompletion(')
          ..write('id: $id, ')
          ..write('todoId: $todoId, ')
          ..write('occurrenceDue: $occurrenceDue, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, todoId, occurrenceDue, completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoCompletion &&
          other.id == this.id &&
          other.todoId == this.todoId &&
          other.occurrenceDue == this.occurrenceDue &&
          other.completedAt == this.completedAt);
}

class TodoCompletionsCompanion extends UpdateCompanion<TodoCompletion> {
  final Value<String> id;
  final Value<String> todoId;
  final Value<DateTime?> occurrenceDue;
  final Value<DateTime> completedAt;
  final Value<int> rowid;
  const TodoCompletionsCompanion({
    this.id = const Value.absent(),
    this.todoId = const Value.absent(),
    this.occurrenceDue = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoCompletionsCompanion.insert({
    required String id,
    required String todoId,
    this.occurrenceDue = const Value.absent(),
    required DateTime completedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       todoId = Value(todoId),
       completedAt = Value(completedAt);
  static Insertable<TodoCompletion> custom({
    Expression<String>? id,
    Expression<String>? todoId,
    Expression<DateTime>? occurrenceDue,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (todoId != null) 'todo_id': todoId,
      if (occurrenceDue != null) 'occurrence_due': occurrenceDue,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoCompletionsCompanion copyWith({
    Value<String>? id,
    Value<String>? todoId,
    Value<DateTime?>? occurrenceDue,
    Value<DateTime>? completedAt,
    Value<int>? rowid,
  }) {
    return TodoCompletionsCompanion(
      id: id ?? this.id,
      todoId: todoId ?? this.todoId,
      occurrenceDue: occurrenceDue ?? this.occurrenceDue,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (todoId.present) {
      map['todo_id'] = Variable<String>(todoId.value);
    }
    if (occurrenceDue.present) {
      map['occurrence_due'] = Variable<DateTime>(occurrenceDue.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoCompletionsCompanion(')
          ..write('id: $id, ')
          ..write('todoId: $todoId, ')
          ..write('occurrenceDue: $occurrenceDue, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyPlansTable extends DailyPlans
    with TableInfo<$DailyPlansTable, DailyPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _intentionMeta = const VerificationMeta(
    'intention',
  );
  @override
  late final GeneratedColumn<String> intention = GeneratedColumn<String>(
    'intention',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dayKey,
    intention,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day_key')) {
      context.handle(
        _dayKeyMeta,
        dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('intention')) {
      context.handle(
        _intentionMeta,
        intention.isAcceptableOrUnknown(data['intention']!, _intentionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyPlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dayKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_key'],
      )!,
      intention: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DailyPlansTable createAlias(String alias) {
    return $DailyPlansTable(attachedDatabase, alias);
  }
}

class DailyPlan extends DataClass implements Insertable<DailyPlan> {
  final String id;
  final String dayKey;
  final String? intention;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DailyPlan({
    required this.id,
    required this.dayKey,
    this.intention,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day_key'] = Variable<String>(dayKey);
    if (!nullToAbsent || intention != null) {
      map['intention'] = Variable<String>(intention);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DailyPlansCompanion toCompanion(bool nullToAbsent) {
    return DailyPlansCompanion(
      id: Value(id),
      dayKey: Value(dayKey),
      intention: intention == null && nullToAbsent
          ? const Value.absent()
          : Value(intention),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DailyPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyPlan(
      id: serializer.fromJson<String>(json['id']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      intention: serializer.fromJson<String?>(json['intention']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dayKey': serializer.toJson<String>(dayKey),
      'intention': serializer.toJson<String?>(intention),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DailyPlan copyWith({
    String? id,
    String? dayKey,
    Value<String?> intention = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DailyPlan(
    id: id ?? this.id,
    dayKey: dayKey ?? this.dayKey,
    intention: intention.present ? intention.value : this.intention,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DailyPlan copyWithCompanion(DailyPlansCompanion data) {
    return DailyPlan(
      id: data.id.present ? data.id.value : this.id,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      intention: data.intention.present ? data.intention.value : this.intention,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyPlan(')
          ..write('id: $id, ')
          ..write('dayKey: $dayKey, ')
          ..write('intention: $intention, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dayKey, intention, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyPlan &&
          other.id == this.id &&
          other.dayKey == this.dayKey &&
          other.intention == this.intention &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DailyPlansCompanion extends UpdateCompanion<DailyPlan> {
  final Value<String> id;
  final Value<String> dayKey;
  final Value<String?> intention;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DailyPlansCompanion({
    this.id = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.intention = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyPlansCompanion.insert({
    required String id,
    required String dayKey,
    this.intention = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dayKey = Value(dayKey),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DailyPlan> custom({
    Expression<String>? id,
    Expression<String>? dayKey,
    Expression<String>? intention,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayKey != null) 'day_key': dayKey,
      if (intention != null) 'intention': intention,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyPlansCompanion copyWith({
    Value<String>? id,
    Value<String>? dayKey,
    Value<String?>? intention,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DailyPlansCompanion(
      id: id ?? this.id,
      dayKey: dayKey ?? this.dayKey,
      intention: intention ?? this.intention,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (intention.present) {
      map['intention'] = Variable<String>(intention.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyPlansCompanion(')
          ..write('id: $id, ')
          ..write('dayKey: $dayKey, ')
          ..write('intention: $intention, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyPlanItemsTable extends DailyPlanItems
    with TableInfo<$DailyPlanItemsTable, DailyPlanItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyPlanItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES daily_plans(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _todoItemIdMeta = const VerificationMeta(
    'todoItemId',
  );
  @override
  late final GeneratedColumn<String> todoItemId = GeneratedColumn<String>(
    'todo_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _projectTaskIdMeta = const VerificationMeta(
    'projectTaskId',
  );
  @override
  late final GeneratedColumn<String> projectTaskId = GeneratedColumn<String>(
    'project_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES tasks(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _plannedMinutesMeta = const VerificationMeta(
    'plannedMinutes',
  );
  @override
  late final GeneratedColumn<int> plannedMinutes = GeneratedColumn<int>(
    'planned_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    planId,
    todoItemId,
    projectTaskId,
    sortOrder,
    plannedMinutes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_plan_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyPlanItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('todo_item_id')) {
      context.handle(
        _todoItemIdMeta,
        todoItemId.isAcceptableOrUnknown(
          data['todo_item_id']!,
          _todoItemIdMeta,
        ),
      );
    }
    if (data.containsKey('project_task_id')) {
      context.handle(
        _projectTaskIdMeta,
        projectTaskId.isAcceptableOrUnknown(
          data['project_task_id']!,
          _projectTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('planned_minutes')) {
      context.handle(
        _plannedMinutesMeta,
        plannedMinutes.isAcceptableOrUnknown(
          data['planned_minutes']!,
          _plannedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyPlanItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyPlanItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      todoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}todo_item_id'],
      ),
      projectTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_task_id'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      plannedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_minutes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DailyPlanItemsTable createAlias(String alias) {
    return $DailyPlanItemsTable(attachedDatabase, alias);
  }
}

class DailyPlanItem extends DataClass implements Insertable<DailyPlanItem> {
  final String id;
  final String planId;
  final String? todoItemId;
  final String? projectTaskId;
  final int sortOrder;
  final int? plannedMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DailyPlanItem({
    required this.id,
    required this.planId,
    this.todoItemId,
    this.projectTaskId,
    required this.sortOrder,
    this.plannedMinutes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['plan_id'] = Variable<String>(planId);
    if (!nullToAbsent || todoItemId != null) {
      map['todo_item_id'] = Variable<String>(todoItemId);
    }
    if (!nullToAbsent || projectTaskId != null) {
      map['project_task_id'] = Variable<String>(projectTaskId);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || plannedMinutes != null) {
      map['planned_minutes'] = Variable<int>(plannedMinutes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DailyPlanItemsCompanion toCompanion(bool nullToAbsent) {
    return DailyPlanItemsCompanion(
      id: Value(id),
      planId: Value(planId),
      todoItemId: todoItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(todoItemId),
      projectTaskId: projectTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectTaskId),
      sortOrder: Value(sortOrder),
      plannedMinutes: plannedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedMinutes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DailyPlanItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyPlanItem(
      id: serializer.fromJson<String>(json['id']),
      planId: serializer.fromJson<String>(json['planId']),
      todoItemId: serializer.fromJson<String?>(json['todoItemId']),
      projectTaskId: serializer.fromJson<String?>(json['projectTaskId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      plannedMinutes: serializer.fromJson<int?>(json['plannedMinutes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'planId': serializer.toJson<String>(planId),
      'todoItemId': serializer.toJson<String?>(todoItemId),
      'projectTaskId': serializer.toJson<String?>(projectTaskId),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'plannedMinutes': serializer.toJson<int?>(plannedMinutes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DailyPlanItem copyWith({
    String? id,
    String? planId,
    Value<String?> todoItemId = const Value.absent(),
    Value<String?> projectTaskId = const Value.absent(),
    int? sortOrder,
    Value<int?> plannedMinutes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DailyPlanItem(
    id: id ?? this.id,
    planId: planId ?? this.planId,
    todoItemId: todoItemId.present ? todoItemId.value : this.todoItemId,
    projectTaskId: projectTaskId.present
        ? projectTaskId.value
        : this.projectTaskId,
    sortOrder: sortOrder ?? this.sortOrder,
    plannedMinutes: plannedMinutes.present
        ? plannedMinutes.value
        : this.plannedMinutes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DailyPlanItem copyWithCompanion(DailyPlanItemsCompanion data) {
    return DailyPlanItem(
      id: data.id.present ? data.id.value : this.id,
      planId: data.planId.present ? data.planId.value : this.planId,
      todoItemId: data.todoItemId.present
          ? data.todoItemId.value
          : this.todoItemId,
      projectTaskId: data.projectTaskId.present
          ? data.projectTaskId.value
          : this.projectTaskId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      plannedMinutes: data.plannedMinutes.present
          ? data.plannedMinutes.value
          : this.plannedMinutes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyPlanItem(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('todoItemId: $todoItemId, ')
          ..write('projectTaskId: $projectTaskId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    planId,
    todoItemId,
    projectTaskId,
    sortOrder,
    plannedMinutes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyPlanItem &&
          other.id == this.id &&
          other.planId == this.planId &&
          other.todoItemId == this.todoItemId &&
          other.projectTaskId == this.projectTaskId &&
          other.sortOrder == this.sortOrder &&
          other.plannedMinutes == this.plannedMinutes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DailyPlanItemsCompanion extends UpdateCompanion<DailyPlanItem> {
  final Value<String> id;
  final Value<String> planId;
  final Value<String?> todoItemId;
  final Value<String?> projectTaskId;
  final Value<int> sortOrder;
  final Value<int?> plannedMinutes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DailyPlanItemsCompanion({
    this.id = const Value.absent(),
    this.planId = const Value.absent(),
    this.todoItemId = const Value.absent(),
    this.projectTaskId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyPlanItemsCompanion.insert({
    required String id,
    required String planId,
    this.todoItemId = const Value.absent(),
    this.projectTaskId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       planId = Value(planId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DailyPlanItem> custom({
    Expression<String>? id,
    Expression<String>? planId,
    Expression<String>? todoItemId,
    Expression<String>? projectTaskId,
    Expression<int>? sortOrder,
    Expression<int>? plannedMinutes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (planId != null) 'plan_id': planId,
      if (todoItemId != null) 'todo_item_id': todoItemId,
      if (projectTaskId != null) 'project_task_id': projectTaskId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (plannedMinutes != null) 'planned_minutes': plannedMinutes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyPlanItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? planId,
    Value<String?>? todoItemId,
    Value<String?>? projectTaskId,
    Value<int>? sortOrder,
    Value<int?>? plannedMinutes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DailyPlanItemsCompanion(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      todoItemId: todoItemId ?? this.todoItemId,
      projectTaskId: projectTaskId ?? this.projectTaskId,
      sortOrder: sortOrder ?? this.sortOrder,
      plannedMinutes: plannedMinutes ?? this.plannedMinutes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (todoItemId.present) {
      map['todo_item_id'] = Variable<String>(todoItemId.value);
    }
    if (projectTaskId.present) {
      map['project_task_id'] = Variable<String>(projectTaskId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (plannedMinutes.present) {
      map['planned_minutes'] = Variable<int>(plannedMinutes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyPlanItemsCompanion(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('todoItemId: $todoItemId, ')
          ..write('projectTaskId: $projectTaskId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskScheduleBlocksTable extends TaskScheduleBlocks
    with TableInfo<$TaskScheduleBlocksTable, TaskScheduleBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskScheduleBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _todoItemIdMeta = const VerificationMeta(
    'todoItemId',
  );
  @override
  late final GeneratedColumn<String> todoItemId = GeneratedColumn<String>(
    'todo_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _projectTaskIdMeta = const VerificationMeta(
    'projectTaskId',
  );
  @override
  late final GeneratedColumn<String> projectTaskId = GeneratedColumn<String>(
    'project_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NULL REFERENCES tasks(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<DateTime> startAt = GeneratedColumn<DateTime>(
    'start_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<DateTime> endAt = GeneratedColumn<DateTime>(
    'end_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneIdMeta = const VerificationMeta(
    'timezoneId',
  );
  @override
  late final GeneratedColumn<String> timezoneId = GeneratedColumn<String>(
    'timezone_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blockKindMeta = const VerificationMeta(
    'blockKind',
  );
  @override
  late final GeneratedColumn<String> blockKind = GeneratedColumn<String>(
    'block_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('work'),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    todoItemId,
    projectTaskId,
    startAt,
    endAt,
    timezoneId,
    blockKind,
    note,
    createdAt,
    updatedAt,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_schedule_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskScheduleBlock> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('todo_item_id')) {
      context.handle(
        _todoItemIdMeta,
        todoItemId.isAcceptableOrUnknown(
          data['todo_item_id']!,
          _todoItemIdMeta,
        ),
      );
    }
    if (data.containsKey('project_task_id')) {
      context.handle(
        _projectTaskIdMeta,
        projectTaskId.isAcceptableOrUnknown(
          data['project_task_id']!,
          _projectTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startAtMeta);
    }
    if (data.containsKey('end_at')) {
      context.handle(
        _endAtMeta,
        endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endAtMeta);
    }
    if (data.containsKey('timezone_id')) {
      context.handle(
        _timezoneIdMeta,
        timezoneId.isAcceptableOrUnknown(data['timezone_id']!, _timezoneIdMeta),
      );
    }
    if (data.containsKey('block_kind')) {
      context.handle(
        _blockKindMeta,
        blockKind.isAcceptableOrUnknown(data['block_kind']!, _blockKindMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskScheduleBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskScheduleBlock(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      todoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}todo_item_id'],
      ),
      projectTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_task_id'],
      ),
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_at'],
      )!,
      endAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_at'],
      )!,
      timezoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone_id'],
      ),
      blockKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_kind'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $TaskScheduleBlocksTable createAlias(String alias) {
    return $TaskScheduleBlocksTable(attachedDatabase, alias);
  }
}

class TaskScheduleBlock extends DataClass
    implements Insertable<TaskScheduleBlock> {
  final String id;
  final String? todoItemId;
  final String? projectTaskId;
  final DateTime startAt;
  final DateTime endAt;

  /// IANA zone for wall-clock intent. Null means the local zone.
  final String? timezoneId;

  /// Controlled vocabulary: work, focus, buffer.
  final String blockKind;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortOrder;
  const TaskScheduleBlock({
    required this.id,
    this.todoItemId,
    this.projectTaskId,
    required this.startAt,
    required this.endAt,
    this.timezoneId,
    required this.blockKind,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || todoItemId != null) {
      map['todo_item_id'] = Variable<String>(todoItemId);
    }
    if (!nullToAbsent || projectTaskId != null) {
      map['project_task_id'] = Variable<String>(projectTaskId);
    }
    map['start_at'] = Variable<DateTime>(startAt);
    map['end_at'] = Variable<DateTime>(endAt);
    if (!nullToAbsent || timezoneId != null) {
      map['timezone_id'] = Variable<String>(timezoneId);
    }
    map['block_kind'] = Variable<String>(blockKind);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TaskScheduleBlocksCompanion toCompanion(bool nullToAbsent) {
    return TaskScheduleBlocksCompanion(
      id: Value(id),
      todoItemId: todoItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(todoItemId),
      projectTaskId: projectTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectTaskId),
      startAt: Value(startAt),
      endAt: Value(endAt),
      timezoneId: timezoneId == null && nullToAbsent
          ? const Value.absent()
          : Value(timezoneId),
      blockKind: Value(blockKind),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      sortOrder: Value(sortOrder),
    );
  }

  factory TaskScheduleBlock.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskScheduleBlock(
      id: serializer.fromJson<String>(json['id']),
      todoItemId: serializer.fromJson<String?>(json['todoItemId']),
      projectTaskId: serializer.fromJson<String?>(json['projectTaskId']),
      startAt: serializer.fromJson<DateTime>(json['startAt']),
      endAt: serializer.fromJson<DateTime>(json['endAt']),
      timezoneId: serializer.fromJson<String?>(json['timezoneId']),
      blockKind: serializer.fromJson<String>(json['blockKind']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'todoItemId': serializer.toJson<String?>(todoItemId),
      'projectTaskId': serializer.toJson<String?>(projectTaskId),
      'startAt': serializer.toJson<DateTime>(startAt),
      'endAt': serializer.toJson<DateTime>(endAt),
      'timezoneId': serializer.toJson<String?>(timezoneId),
      'blockKind': serializer.toJson<String>(blockKind),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  TaskScheduleBlock copyWith({
    String? id,
    Value<String?> todoItemId = const Value.absent(),
    Value<String?> projectTaskId = const Value.absent(),
    DateTime? startAt,
    DateTime? endAt,
    Value<String?> timezoneId = const Value.absent(),
    String? blockKind,
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) => TaskScheduleBlock(
    id: id ?? this.id,
    todoItemId: todoItemId.present ? todoItemId.value : this.todoItemId,
    projectTaskId: projectTaskId.present
        ? projectTaskId.value
        : this.projectTaskId,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    timezoneId: timezoneId.present ? timezoneId.value : this.timezoneId,
    blockKind: blockKind ?? this.blockKind,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  TaskScheduleBlock copyWithCompanion(TaskScheduleBlocksCompanion data) {
    return TaskScheduleBlock(
      id: data.id.present ? data.id.value : this.id,
      todoItemId: data.todoItemId.present
          ? data.todoItemId.value
          : this.todoItemId,
      projectTaskId: data.projectTaskId.present
          ? data.projectTaskId.value
          : this.projectTaskId,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      timezoneId: data.timezoneId.present
          ? data.timezoneId.value
          : this.timezoneId,
      blockKind: data.blockKind.present ? data.blockKind.value : this.blockKind,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskScheduleBlock(')
          ..write('id: $id, ')
          ..write('todoItemId: $todoItemId, ')
          ..write('projectTaskId: $projectTaskId, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('timezoneId: $timezoneId, ')
          ..write('blockKind: $blockKind, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    todoItemId,
    projectTaskId,
    startAt,
    endAt,
    timezoneId,
    blockKind,
    note,
    createdAt,
    updatedAt,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskScheduleBlock &&
          other.id == this.id &&
          other.todoItemId == this.todoItemId &&
          other.projectTaskId == this.projectTaskId &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.timezoneId == this.timezoneId &&
          other.blockKind == this.blockKind &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.sortOrder == this.sortOrder);
}

class TaskScheduleBlocksCompanion extends UpdateCompanion<TaskScheduleBlock> {
  final Value<String> id;
  final Value<String?> todoItemId;
  final Value<String?> projectTaskId;
  final Value<DateTime> startAt;
  final Value<DateTime> endAt;
  final Value<String?> timezoneId;
  final Value<String> blockKind;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const TaskScheduleBlocksCompanion({
    this.id = const Value.absent(),
    this.todoItemId = const Value.absent(),
    this.projectTaskId = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.timezoneId = const Value.absent(),
    this.blockKind = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskScheduleBlocksCompanion.insert({
    required String id,
    this.todoItemId = const Value.absent(),
    this.projectTaskId = const Value.absent(),
    required DateTime startAt,
    required DateTime endAt,
    this.timezoneId = const Value.absent(),
    this.blockKind = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startAt = Value(startAt),
       endAt = Value(endAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskScheduleBlock> custom({
    Expression<String>? id,
    Expression<String>? todoItemId,
    Expression<String>? projectTaskId,
    Expression<DateTime>? startAt,
    Expression<DateTime>? endAt,
    Expression<String>? timezoneId,
    Expression<String>? blockKind,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (todoItemId != null) 'todo_item_id': todoItemId,
      if (projectTaskId != null) 'project_task_id': projectTaskId,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (timezoneId != null) 'timezone_id': timezoneId,
      if (blockKind != null) 'block_kind': blockKind,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskScheduleBlocksCompanion copyWith({
    Value<String>? id,
    Value<String?>? todoItemId,
    Value<String?>? projectTaskId,
    Value<DateTime>? startAt,
    Value<DateTime>? endAt,
    Value<String?>? timezoneId,
    Value<String>? blockKind,
    Value<String?>? note,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return TaskScheduleBlocksCompanion(
      id: id ?? this.id,
      todoItemId: todoItemId ?? this.todoItemId,
      projectTaskId: projectTaskId ?? this.projectTaskId,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      timezoneId: timezoneId ?? this.timezoneId,
      blockKind: blockKind ?? this.blockKind,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (todoItemId.present) {
      map['todo_item_id'] = Variable<String>(todoItemId.value);
    }
    if (projectTaskId.present) {
      map['project_task_id'] = Variable<String>(projectTaskId.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<DateTime>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<DateTime>(endAt.value);
    }
    if (timezoneId.present) {
      map['timezone_id'] = Variable<String>(timezoneId.value);
    }
    if (blockKind.present) {
      map['block_kind'] = Variable<String>(blockKind.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskScheduleBlocksCompanion(')
          ..write('id: $id, ')
          ..write('todoItemId: $todoItemId, ')
          ..write('projectTaskId: $projectTaskId, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('timezoneId: $timezoneId, ')
          ..write('blockKind: $blockKind, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedFiltersTable extends SavedFilters
    with TableInfo<$SavedFiltersTable, SavedFilter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedFiltersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityScopeMeta = const VerificationMeta(
    'entityScope',
  );
  @override
  late final GeneratedColumn<String> entityScope = GeneratedColumn<String>(
    'entity_scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filterJsonMeta = const VerificationMeta(
    'filterJson',
  );
  @override
  late final GeneratedColumn<String> filterJson = GeneratedColumn<String>(
    'filter_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortJsonMeta = const VerificationMeta(
    'sortJson',
  );
  @override
  late final GeneratedColumn<String> sortJson = GeneratedColumn<String>(
    'sort_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _definitionVersionMeta = const VerificationMeta(
    'definitionVersion',
  );
  @override
  late final GeneratedColumn<int> definitionVersion = GeneratedColumn<int>(
    'definition_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    entityScope,
    filterJson,
    sortJson,
    isPinned,
    position,
    createdAt,
    updatedAt,
    definitionVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_filters';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedFilter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('entity_scope')) {
      context.handle(
        _entityScopeMeta,
        entityScope.isAcceptableOrUnknown(
          data['entity_scope']!,
          _entityScopeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityScopeMeta);
    }
    if (data.containsKey('filter_json')) {
      context.handle(
        _filterJsonMeta,
        filterJson.isAcceptableOrUnknown(data['filter_json']!, _filterJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_filterJsonMeta);
    }
    if (data.containsKey('sort_json')) {
      context.handle(
        _sortJsonMeta,
        sortJson.isAcceptableOrUnknown(data['sort_json']!, _sortJsonMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('definition_version')) {
      context.handle(
        _definitionVersionMeta,
        definitionVersion.isAcceptableOrUnknown(
          data['definition_version']!,
          _definitionVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedFilter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedFilter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      entityScope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_scope'],
      )!,
      filterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filter_json'],
      )!,
      sortJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_json'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      definitionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}definition_version'],
      )!,
    );
  }

  @override
  $SavedFiltersTable createAlias(String alias) {
    return $SavedFiltersTable(attachedDatabase, alias);
  }
}

class SavedFilter extends DataClass implements Insertable<SavedFilter> {
  final String id;
  final String name;
  final String entityScope;
  final String filterJson;
  final String sortJson;
  final bool isPinned;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int definitionVersion;
  const SavedFilter({
    required this.id,
    required this.name,
    required this.entityScope,
    required this.filterJson,
    required this.sortJson,
    required this.isPinned,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    required this.definitionVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['entity_scope'] = Variable<String>(entityScope);
    map['filter_json'] = Variable<String>(filterJson);
    map['sort_json'] = Variable<String>(sortJson);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['definition_version'] = Variable<int>(definitionVersion);
    return map;
  }

  SavedFiltersCompanion toCompanion(bool nullToAbsent) {
    return SavedFiltersCompanion(
      id: Value(id),
      name: Value(name),
      entityScope: Value(entityScope),
      filterJson: Value(filterJson),
      sortJson: Value(sortJson),
      isPinned: Value(isPinned),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      definitionVersion: Value(definitionVersion),
    );
  }

  factory SavedFilter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedFilter(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      entityScope: serializer.fromJson<String>(json['entityScope']),
      filterJson: serializer.fromJson<String>(json['filterJson']),
      sortJson: serializer.fromJson<String>(json['sortJson']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      definitionVersion: serializer.fromJson<int>(json['definitionVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'entityScope': serializer.toJson<String>(entityScope),
      'filterJson': serializer.toJson<String>(filterJson),
      'sortJson': serializer.toJson<String>(sortJson),
      'isPinned': serializer.toJson<bool>(isPinned),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'definitionVersion': serializer.toJson<int>(definitionVersion),
    };
  }

  SavedFilter copyWith({
    String? id,
    String? name,
    String? entityScope,
    String? filterJson,
    String? sortJson,
    bool? isPinned,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? definitionVersion,
  }) => SavedFilter(
    id: id ?? this.id,
    name: name ?? this.name,
    entityScope: entityScope ?? this.entityScope,
    filterJson: filterJson ?? this.filterJson,
    sortJson: sortJson ?? this.sortJson,
    isPinned: isPinned ?? this.isPinned,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    definitionVersion: definitionVersion ?? this.definitionVersion,
  );
  SavedFilter copyWithCompanion(SavedFiltersCompanion data) {
    return SavedFilter(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      entityScope: data.entityScope.present
          ? data.entityScope.value
          : this.entityScope,
      filterJson: data.filterJson.present
          ? data.filterJson.value
          : this.filterJson,
      sortJson: data.sortJson.present ? data.sortJson.value : this.sortJson,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      definitionVersion: data.definitionVersion.present
          ? data.definitionVersion.value
          : this.definitionVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedFilter(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('entityScope: $entityScope, ')
          ..write('filterJson: $filterJson, ')
          ..write('sortJson: $sortJson, ')
          ..write('isPinned: $isPinned, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('definitionVersion: $definitionVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    entityScope,
    filterJson,
    sortJson,
    isPinned,
    position,
    createdAt,
    updatedAt,
    definitionVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedFilter &&
          other.id == this.id &&
          other.name == this.name &&
          other.entityScope == this.entityScope &&
          other.filterJson == this.filterJson &&
          other.sortJson == this.sortJson &&
          other.isPinned == this.isPinned &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.definitionVersion == this.definitionVersion);
}

class SavedFiltersCompanion extends UpdateCompanion<SavedFilter> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> entityScope;
  final Value<String> filterJson;
  final Value<String> sortJson;
  final Value<bool> isPinned;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> definitionVersion;
  final Value<int> rowid;
  const SavedFiltersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.entityScope = const Value.absent(),
    this.filterJson = const Value.absent(),
    this.sortJson = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.definitionVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedFiltersCompanion.insert({
    required String id,
    required String name,
    required String entityScope,
    required String filterJson,
    this.sortJson = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.position = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.definitionVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       entityScope = Value(entityScope),
       filterJson = Value(filterJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SavedFilter> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? entityScope,
    Expression<String>? filterJson,
    Expression<String>? sortJson,
    Expression<bool>? isPinned,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? definitionVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (entityScope != null) 'entity_scope': entityScope,
      if (filterJson != null) 'filter_json': filterJson,
      if (sortJson != null) 'sort_json': sortJson,
      if (isPinned != null) 'is_pinned': isPinned,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (definitionVersion != null) 'definition_version': definitionVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedFiltersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? entityScope,
    Value<String>? filterJson,
    Value<String>? sortJson,
    Value<bool>? isPinned,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? definitionVersion,
    Value<int>? rowid,
  }) {
    return SavedFiltersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      entityScope: entityScope ?? this.entityScope,
      filterJson: filterJson ?? this.filterJson,
      sortJson: sortJson ?? this.sortJson,
      isPinned: isPinned ?? this.isPinned,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      definitionVersion: definitionVersion ?? this.definitionVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (entityScope.present) {
      map['entity_scope'] = Variable<String>(entityScope.value);
    }
    if (filterJson.present) {
      map['filter_json'] = Variable<String>(filterJson.value);
    }
    if (sortJson.present) {
      map['sort_json'] = Variable<String>(sortJson.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (definitionVersion.present) {
      map['definition_version'] = Variable<int>(definitionVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedFiltersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('entityScope: $entityScope, ')
          ..write('filterJson: $filterJson, ')
          ..write('sortJson: $sortJson, ')
          ..write('isPinned: $isPinned, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('definitionVersion: $definitionVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanningPreferencesTable extends PlanningPreferences
    with TableInfo<$PlanningPreferencesTable, PlanningPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanningPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneIdMeta = const VerificationMeta(
    'timezoneId',
  );
  @override
  late final GeneratedColumn<String> timezoneId = GeneratedColumn<String>(
    'timezone_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultSlotMinutesMeta =
      const VerificationMeta('defaultSlotMinutes');
  @override
  late final GeneratedColumn<int> defaultSlotMinutes = GeneratedColumn<int>(
    'default_slot_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  static const VerificationMeta _weekStartDayMeta = const VerificationMeta(
    'weekStartDay',
  );
  @override
  late final GeneratedColumn<int> weekStartDay = GeneratedColumn<int>(
    'week_start_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _dayStartMinuteMeta = const VerificationMeta(
    'dayStartMinute',
  );
  @override
  late final GeneratedColumn<int> dayStartMinute = GeneratedColumn<int>(
    'day_start_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(480),
  );
  static const VerificationMeta _dayEndMinuteMeta = const VerificationMeta(
    'dayEndMinute',
  );
  @override
  late final GeneratedColumn<int> dayEndMinute = GeneratedColumn<int>(
    'day_end_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1080),
  );
  static const VerificationMeta _bufferMinutesMeta = const VerificationMeta(
    'bufferMinutes',
  );
  @override
  late final GeneratedColumn<int> bufferMinutes = GeneratedColumn<int>(
    'buffer_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(10),
  );
  static const VerificationMeta _urgencyWindowDaysMeta = const VerificationMeta(
    'urgencyWindowDays',
  );
  @override
  late final GeneratedColumn<int> urgencyWindowDays = GeneratedColumn<int>(
    'urgency_window_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(3),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    timezoneId,
    defaultSlotMinutes,
    weekStartDay,
    dayStartMinute,
    dayEndMinute,
    bufferMinutes,
    urgencyWindowDays,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'planning_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanningPreference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('timezone_id')) {
      context.handle(
        _timezoneIdMeta,
        timezoneId.isAcceptableOrUnknown(data['timezone_id']!, _timezoneIdMeta),
      );
    }
    if (data.containsKey('default_slot_minutes')) {
      context.handle(
        _defaultSlotMinutesMeta,
        defaultSlotMinutes.isAcceptableOrUnknown(
          data['default_slot_minutes']!,
          _defaultSlotMinutesMeta,
        ),
      );
    }
    if (data.containsKey('week_start_day')) {
      context.handle(
        _weekStartDayMeta,
        weekStartDay.isAcceptableOrUnknown(
          data['week_start_day']!,
          _weekStartDayMeta,
        ),
      );
    }
    if (data.containsKey('day_start_minute')) {
      context.handle(
        _dayStartMinuteMeta,
        dayStartMinute.isAcceptableOrUnknown(
          data['day_start_minute']!,
          _dayStartMinuteMeta,
        ),
      );
    }
    if (data.containsKey('day_end_minute')) {
      context.handle(
        _dayEndMinuteMeta,
        dayEndMinute.isAcceptableOrUnknown(
          data['day_end_minute']!,
          _dayEndMinuteMeta,
        ),
      );
    }
    if (data.containsKey('buffer_minutes')) {
      context.handle(
        _bufferMinutesMeta,
        bufferMinutes.isAcceptableOrUnknown(
          data['buffer_minutes']!,
          _bufferMinutesMeta,
        ),
      );
    }
    if (data.containsKey('urgency_window_days')) {
      context.handle(
        _urgencyWindowDaysMeta,
        urgencyWindowDays.isAcceptableOrUnknown(
          data['urgency_window_days']!,
          _urgencyWindowDaysMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanningPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanningPreference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      timezoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone_id'],
      ),
      defaultSlotMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_slot_minutes'],
      )!,
      weekStartDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}week_start_day'],
      )!,
      dayStartMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_start_minute'],
      )!,
      dayEndMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_end_minute'],
      )!,
      bufferMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}buffer_minutes'],
      )!,
      urgencyWindowDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}urgency_window_days'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanningPreferencesTable createAlias(String alias) {
    return $PlanningPreferencesTable(attachedDatabase, alias);
  }
}

class PlanningPreference extends DataClass
    implements Insertable<PlanningPreference> {
  final String id;
  final String? timezoneId;
  final int defaultSlotMinutes;
  final int weekStartDay;
  final int dayStartMinute;
  final int dayEndMinute;
  final int bufferMinutes;

  /// Due-date proximity in days used to derive urgency in the Eisenhower
  /// matrix.
  final int urgencyWindowDays;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PlanningPreference({
    required this.id,
    this.timezoneId,
    required this.defaultSlotMinutes,
    required this.weekStartDay,
    required this.dayStartMinute,
    required this.dayEndMinute,
    required this.bufferMinutes,
    required this.urgencyWindowDays,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || timezoneId != null) {
      map['timezone_id'] = Variable<String>(timezoneId);
    }
    map['default_slot_minutes'] = Variable<int>(defaultSlotMinutes);
    map['week_start_day'] = Variable<int>(weekStartDay);
    map['day_start_minute'] = Variable<int>(dayStartMinute);
    map['day_end_minute'] = Variable<int>(dayEndMinute);
    map['buffer_minutes'] = Variable<int>(bufferMinutes);
    map['urgency_window_days'] = Variable<int>(urgencyWindowDays);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlanningPreferencesCompanion toCompanion(bool nullToAbsent) {
    return PlanningPreferencesCompanion(
      id: Value(id),
      timezoneId: timezoneId == null && nullToAbsent
          ? const Value.absent()
          : Value(timezoneId),
      defaultSlotMinutes: Value(defaultSlotMinutes),
      weekStartDay: Value(weekStartDay),
      dayStartMinute: Value(dayStartMinute),
      dayEndMinute: Value(dayEndMinute),
      bufferMinutes: Value(bufferMinutes),
      urgencyWindowDays: Value(urgencyWindowDays),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanningPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanningPreference(
      id: serializer.fromJson<String>(json['id']),
      timezoneId: serializer.fromJson<String?>(json['timezoneId']),
      defaultSlotMinutes: serializer.fromJson<int>(json['defaultSlotMinutes']),
      weekStartDay: serializer.fromJson<int>(json['weekStartDay']),
      dayStartMinute: serializer.fromJson<int>(json['dayStartMinute']),
      dayEndMinute: serializer.fromJson<int>(json['dayEndMinute']),
      bufferMinutes: serializer.fromJson<int>(json['bufferMinutes']),
      urgencyWindowDays: serializer.fromJson<int>(json['urgencyWindowDays']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'timezoneId': serializer.toJson<String?>(timezoneId),
      'defaultSlotMinutes': serializer.toJson<int>(defaultSlotMinutes),
      'weekStartDay': serializer.toJson<int>(weekStartDay),
      'dayStartMinute': serializer.toJson<int>(dayStartMinute),
      'dayEndMinute': serializer.toJson<int>(dayEndMinute),
      'bufferMinutes': serializer.toJson<int>(bufferMinutes),
      'urgencyWindowDays': serializer.toJson<int>(urgencyWindowDays),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlanningPreference copyWith({
    String? id,
    Value<String?> timezoneId = const Value.absent(),
    int? defaultSlotMinutes,
    int? weekStartDay,
    int? dayStartMinute,
    int? dayEndMinute,
    int? bufferMinutes,
    int? urgencyWindowDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PlanningPreference(
    id: id ?? this.id,
    timezoneId: timezoneId.present ? timezoneId.value : this.timezoneId,
    defaultSlotMinutes: defaultSlotMinutes ?? this.defaultSlotMinutes,
    weekStartDay: weekStartDay ?? this.weekStartDay,
    dayStartMinute: dayStartMinute ?? this.dayStartMinute,
    dayEndMinute: dayEndMinute ?? this.dayEndMinute,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    urgencyWindowDays: urgencyWindowDays ?? this.urgencyWindowDays,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanningPreference copyWithCompanion(PlanningPreferencesCompanion data) {
    return PlanningPreference(
      id: data.id.present ? data.id.value : this.id,
      timezoneId: data.timezoneId.present
          ? data.timezoneId.value
          : this.timezoneId,
      defaultSlotMinutes: data.defaultSlotMinutes.present
          ? data.defaultSlotMinutes.value
          : this.defaultSlotMinutes,
      weekStartDay: data.weekStartDay.present
          ? data.weekStartDay.value
          : this.weekStartDay,
      dayStartMinute: data.dayStartMinute.present
          ? data.dayStartMinute.value
          : this.dayStartMinute,
      dayEndMinute: data.dayEndMinute.present
          ? data.dayEndMinute.value
          : this.dayEndMinute,
      bufferMinutes: data.bufferMinutes.present
          ? data.bufferMinutes.value
          : this.bufferMinutes,
      urgencyWindowDays: data.urgencyWindowDays.present
          ? data.urgencyWindowDays.value
          : this.urgencyWindowDays,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanningPreference(')
          ..write('id: $id, ')
          ..write('timezoneId: $timezoneId, ')
          ..write('defaultSlotMinutes: $defaultSlotMinutes, ')
          ..write('weekStartDay: $weekStartDay, ')
          ..write('dayStartMinute: $dayStartMinute, ')
          ..write('dayEndMinute: $dayEndMinute, ')
          ..write('bufferMinutes: $bufferMinutes, ')
          ..write('urgencyWindowDays: $urgencyWindowDays, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    timezoneId,
    defaultSlotMinutes,
    weekStartDay,
    dayStartMinute,
    dayEndMinute,
    bufferMinutes,
    urgencyWindowDays,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanningPreference &&
          other.id == this.id &&
          other.timezoneId == this.timezoneId &&
          other.defaultSlotMinutes == this.defaultSlotMinutes &&
          other.weekStartDay == this.weekStartDay &&
          other.dayStartMinute == this.dayStartMinute &&
          other.dayEndMinute == this.dayEndMinute &&
          other.bufferMinutes == this.bufferMinutes &&
          other.urgencyWindowDays == this.urgencyWindowDays &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlanningPreferencesCompanion extends UpdateCompanion<PlanningPreference> {
  final Value<String> id;
  final Value<String?> timezoneId;
  final Value<int> defaultSlotMinutes;
  final Value<int> weekStartDay;
  final Value<int> dayStartMinute;
  final Value<int> dayEndMinute;
  final Value<int> bufferMinutes;
  final Value<int> urgencyWindowDays;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlanningPreferencesCompanion({
    this.id = const Value.absent(),
    this.timezoneId = const Value.absent(),
    this.defaultSlotMinutes = const Value.absent(),
    this.weekStartDay = const Value.absent(),
    this.dayStartMinute = const Value.absent(),
    this.dayEndMinute = const Value.absent(),
    this.bufferMinutes = const Value.absent(),
    this.urgencyWindowDays = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanningPreferencesCompanion.insert({
    required String id,
    this.timezoneId = const Value.absent(),
    this.defaultSlotMinutes = const Value.absent(),
    this.weekStartDay = const Value.absent(),
    this.dayStartMinute = const Value.absent(),
    this.dayEndMinute = const Value.absent(),
    this.bufferMinutes = const Value.absent(),
    this.urgencyWindowDays = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanningPreference> custom({
    Expression<String>? id,
    Expression<String>? timezoneId,
    Expression<int>? defaultSlotMinutes,
    Expression<int>? weekStartDay,
    Expression<int>? dayStartMinute,
    Expression<int>? dayEndMinute,
    Expression<int>? bufferMinutes,
    Expression<int>? urgencyWindowDays,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timezoneId != null) 'timezone_id': timezoneId,
      if (defaultSlotMinutes != null)
        'default_slot_minutes': defaultSlotMinutes,
      if (weekStartDay != null) 'week_start_day': weekStartDay,
      if (dayStartMinute != null) 'day_start_minute': dayStartMinute,
      if (dayEndMinute != null) 'day_end_minute': dayEndMinute,
      if (bufferMinutes != null) 'buffer_minutes': bufferMinutes,
      if (urgencyWindowDays != null) 'urgency_window_days': urgencyWindowDays,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanningPreferencesCompanion copyWith({
    Value<String>? id,
    Value<String?>? timezoneId,
    Value<int>? defaultSlotMinutes,
    Value<int>? weekStartDay,
    Value<int>? dayStartMinute,
    Value<int>? dayEndMinute,
    Value<int>? bufferMinutes,
    Value<int>? urgencyWindowDays,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanningPreferencesCompanion(
      id: id ?? this.id,
      timezoneId: timezoneId ?? this.timezoneId,
      defaultSlotMinutes: defaultSlotMinutes ?? this.defaultSlotMinutes,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      dayStartMinute: dayStartMinute ?? this.dayStartMinute,
      dayEndMinute: dayEndMinute ?? this.dayEndMinute,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      urgencyWindowDays: urgencyWindowDays ?? this.urgencyWindowDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (timezoneId.present) {
      map['timezone_id'] = Variable<String>(timezoneId.value);
    }
    if (defaultSlotMinutes.present) {
      map['default_slot_minutes'] = Variable<int>(defaultSlotMinutes.value);
    }
    if (weekStartDay.present) {
      map['week_start_day'] = Variable<int>(weekStartDay.value);
    }
    if (dayStartMinute.present) {
      map['day_start_minute'] = Variable<int>(dayStartMinute.value);
    }
    if (dayEndMinute.present) {
      map['day_end_minute'] = Variable<int>(dayEndMinute.value);
    }
    if (bufferMinutes.present) {
      map['buffer_minutes'] = Variable<int>(bufferMinutes.value);
    }
    if (urgencyWindowDays.present) {
      map['urgency_window_days'] = Variable<int>(urgencyWindowDays.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanningPreferencesCompanion(')
          ..write('id: $id, ')
          ..write('timezoneId: $timezoneId, ')
          ..write('defaultSlotMinutes: $defaultSlotMinutes, ')
          ..write('weekStartDay: $weekStartDay, ')
          ..write('dayStartMinute: $dayStartMinute, ')
          ..write('dayEndMinute: $dayEndMinute, ')
          ..write('bufferMinutes: $bufferMinutes, ')
          ..write('urgencyWindowDays: $urgencyWindowDays, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkingHoursTable extends WorkingHours
    with TableInfo<$WorkingHoursTable, WorkingHour> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkingHoursTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMinuteMeta = const VerificationMeta(
    'endMinute',
  );
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
    'end_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    weekday,
    enabled,
    startMinute,
    endMinute,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'working_hours';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkingHour> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startMinuteMeta);
    }
    if (data.containsKey('end_minute')) {
      context.handle(
        _endMinuteMeta,
        endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta),
      );
    } else if (isInserting) {
      context.missing(_endMinuteMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkingHour map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkingHour(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      )!,
      endMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_minute'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WorkingHoursTable createAlias(String alias) {
    return $WorkingHoursTable(attachedDatabase, alias);
  }
}

class WorkingHour extends DataClass implements Insertable<WorkingHour> {
  final String id;
  final int weekday;
  final bool enabled;
  final int startMinute;
  final int endMinute;
  final DateTime createdAt;
  final DateTime updatedAt;
  const WorkingHour({
    required this.id,
    required this.weekday,
    required this.enabled,
    required this.startMinute,
    required this.endMinute,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['weekday'] = Variable<int>(weekday);
    map['enabled'] = Variable<bool>(enabled);
    map['start_minute'] = Variable<int>(startMinute);
    map['end_minute'] = Variable<int>(endMinute);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WorkingHoursCompanion toCompanion(bool nullToAbsent) {
    return WorkingHoursCompanion(
      id: Value(id),
      weekday: Value(weekday),
      enabled: Value(enabled),
      startMinute: Value(startMinute),
      endMinute: Value(endMinute),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WorkingHour.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkingHour(
      id: serializer.fromJson<String>(json['id']),
      weekday: serializer.fromJson<int>(json['weekday']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      startMinute: serializer.fromJson<int>(json['startMinute']),
      endMinute: serializer.fromJson<int>(json['endMinute']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'weekday': serializer.toJson<int>(weekday),
      'enabled': serializer.toJson<bool>(enabled),
      'startMinute': serializer.toJson<int>(startMinute),
      'endMinute': serializer.toJson<int>(endMinute),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WorkingHour copyWith({
    String? id,
    int? weekday,
    bool? enabled,
    int? startMinute,
    int? endMinute,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WorkingHour(
    id: id ?? this.id,
    weekday: weekday ?? this.weekday,
    enabled: enabled ?? this.enabled,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WorkingHour copyWithCompanion(WorkingHoursCompanion data) {
    return WorkingHour(
      id: data.id.present ? data.id.value : this.id,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkingHour(')
          ..write('id: $id, ')
          ..write('weekday: $weekday, ')
          ..write('enabled: $enabled, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    weekday,
    enabled,
    startMinute,
    endMinute,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkingHour &&
          other.id == this.id &&
          other.weekday == this.weekday &&
          other.enabled == this.enabled &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WorkingHoursCompanion extends UpdateCompanion<WorkingHour> {
  final Value<String> id;
  final Value<int> weekday;
  final Value<bool> enabled;
  final Value<int> startMinute;
  final Value<int> endMinute;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WorkingHoursCompanion({
    this.id = const Value.absent(),
    this.weekday = const Value.absent(),
    this.enabled = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkingHoursCompanion.insert({
    required String id,
    required int weekday,
    this.enabled = const Value.absent(),
    required int startMinute,
    required int endMinute,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       weekday = Value(weekday),
       startMinute = Value(startMinute),
       endMinute = Value(endMinute),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<WorkingHour> custom({
    Expression<String>? id,
    Expression<int>? weekday,
    Expression<bool>? enabled,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (weekday != null) 'weekday': weekday,
      if (enabled != null) 'enabled': enabled,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkingHoursCompanion copyWith({
    Value<String>? id,
    Value<int>? weekday,
    Value<bool>? enabled,
    Value<int>? startMinute,
    Value<int>? endMinute,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WorkingHoursCompanion(
      id: id ?? this.id,
      weekday: weekday ?? this.weekday,
      enabled: enabled ?? this.enabled,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkingHoursCompanion(')
          ..write('id: $id, ')
          ..write('weekday: $weekday, ')
          ..write('enabled: $enabled, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkingBreaksTable extends WorkingBreaks
    with TableInfo<$WorkingBreaksTable, WorkingBreak> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkingBreaksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMinuteMeta = const VerificationMeta(
    'endMinute',
  );
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
    'end_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    weekday,
    startMinute,
    endMinute,
    label,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'working_breaks';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkingBreak> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startMinuteMeta);
    }
    if (data.containsKey('end_minute')) {
      context.handle(
        _endMinuteMeta,
        endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta),
      );
    } else if (isInserting) {
      context.missing(_endMinuteMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkingBreak map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkingBreak(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      )!,
      endMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_minute'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WorkingBreaksTable createAlias(String alias) {
    return $WorkingBreaksTable(attachedDatabase, alias);
  }
}

class WorkingBreak extends DataClass implements Insertable<WorkingBreak> {
  final String id;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String? label;
  final DateTime createdAt;
  final DateTime updatedAt;
  const WorkingBreak({
    required this.id,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.label,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['weekday'] = Variable<int>(weekday);
    map['start_minute'] = Variable<int>(startMinute);
    map['end_minute'] = Variable<int>(endMinute);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WorkingBreaksCompanion toCompanion(bool nullToAbsent) {
    return WorkingBreaksCompanion(
      id: Value(id),
      weekday: Value(weekday),
      startMinute: Value(startMinute),
      endMinute: Value(endMinute),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WorkingBreak.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkingBreak(
      id: serializer.fromJson<String>(json['id']),
      weekday: serializer.fromJson<int>(json['weekday']),
      startMinute: serializer.fromJson<int>(json['startMinute']),
      endMinute: serializer.fromJson<int>(json['endMinute']),
      label: serializer.fromJson<String?>(json['label']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'weekday': serializer.toJson<int>(weekday),
      'startMinute': serializer.toJson<int>(startMinute),
      'endMinute': serializer.toJson<int>(endMinute),
      'label': serializer.toJson<String?>(label),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WorkingBreak copyWith({
    String? id,
    int? weekday,
    int? startMinute,
    int? endMinute,
    Value<String?> label = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WorkingBreak(
    id: id ?? this.id,
    weekday: weekday ?? this.weekday,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    label: label.present ? label.value : this.label,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WorkingBreak copyWithCompanion(WorkingBreaksCompanion data) {
    return WorkingBreak(
      id: data.id.present ? data.id.value : this.id,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
      label: data.label.present ? data.label.value : this.label,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkingBreak(')
          ..write('id: $id, ')
          ..write('weekday: $weekday, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('label: $label, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    weekday,
    startMinute,
    endMinute,
    label,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkingBreak &&
          other.id == this.id &&
          other.weekday == this.weekday &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute &&
          other.label == this.label &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WorkingBreaksCompanion extends UpdateCompanion<WorkingBreak> {
  final Value<String> id;
  final Value<int> weekday;
  final Value<int> startMinute;
  final Value<int> endMinute;
  final Value<String?> label;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WorkingBreaksCompanion({
    this.id = const Value.absent(),
    this.weekday = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.label = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkingBreaksCompanion.insert({
    required String id,
    required int weekday,
    required int startMinute,
    required int endMinute,
    this.label = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       weekday = Value(weekday),
       startMinute = Value(startMinute),
       endMinute = Value(endMinute),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<WorkingBreak> custom({
    Expression<String>? id,
    Expression<int>? weekday,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
    Expression<String>? label,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (weekday != null) 'weekday': weekday,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
      if (label != null) 'label': label,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkingBreaksCompanion copyWith({
    Value<String>? id,
    Value<int>? weekday,
    Value<int>? startMinute,
    Value<int>? endMinute,
    Value<String?>? label,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WorkingBreaksCompanion(
      id: id ?? this.id,
      weekday: weekday ?? this.weekday,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkingBreaksCompanion(')
          ..write('id: $id, ')
          ..write('weekday: $weekday, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('label: $label, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectStatusesTable extends ProjectStatuses
    with TableInfo<$ProjectStatusesTable, ProjectStatus> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectStatusesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'REFERENCES projects(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _statusKeyMeta = const VerificationMeta(
    'statusKey',
  );
  @override
  late final GeneratedColumn<String> statusKey = GeneratedColumn<String>(
    'status_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorTokenMeta = const VerificationMeta(
    'colorToken',
  );
  @override
  late final GeneratedColumn<String> colorToken = GeneratedColumn<String>(
    'color_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('blue'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isDoneMeta = const VerificationMeta('isDone');
  @override
  late final GeneratedColumn<bool> isDone = GeneratedColumn<bool>(
    'is_done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    statusKey,
    name,
    colorToken,
    position,
    isDone,
    isDefault,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_statuses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectStatus> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('status_key')) {
      context.handle(
        _statusKeyMeta,
        statusKey.isAcceptableOrUnknown(data['status_key']!, _statusKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_statusKeyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_token')) {
      context.handle(
        _colorTokenMeta,
        colorToken.isAcceptableOrUnknown(data['color_token']!, _colorTokenMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('is_done')) {
      context.handle(
        _isDoneMeta,
        isDone.isAcceptableOrUnknown(data['is_done']!, _isDoneMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {projectId, statusKey},
  ];
  @override
  ProjectStatus map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectStatus(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      statusKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_token'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      isDone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_done'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectStatusesTable createAlias(String alias) {
    return $ProjectStatusesTable(attachedDatabase, alias);
  }
}

class ProjectStatus extends DataClass implements Insertable<ProjectStatus> {
  final String id;
  final String projectId;
  final String statusKey;
  final String name;
  final String colorToken;
  final int position;
  final bool isDone;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProjectStatus({
    required this.id,
    required this.projectId,
    required this.statusKey,
    required this.name,
    required this.colorToken,
    required this.position,
    required this.isDone,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['status_key'] = Variable<String>(statusKey);
    map['name'] = Variable<String>(name);
    map['color_token'] = Variable<String>(colorToken);
    map['position'] = Variable<int>(position);
    map['is_done'] = Variable<bool>(isDone);
    map['is_default'] = Variable<bool>(isDefault);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectStatusesCompanion toCompanion(bool nullToAbsent) {
    return ProjectStatusesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      statusKey: Value(statusKey),
      name: Value(name),
      colorToken: Value(colorToken),
      position: Value(position),
      isDone: Value(isDone),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProjectStatus.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectStatus(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      statusKey: serializer.fromJson<String>(json['statusKey']),
      name: serializer.fromJson<String>(json['name']),
      colorToken: serializer.fromJson<String>(json['colorToken']),
      position: serializer.fromJson<int>(json['position']),
      isDone: serializer.fromJson<bool>(json['isDone']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'statusKey': serializer.toJson<String>(statusKey),
      'name': serializer.toJson<String>(name),
      'colorToken': serializer.toJson<String>(colorToken),
      'position': serializer.toJson<int>(position),
      'isDone': serializer.toJson<bool>(isDone),
      'isDefault': serializer.toJson<bool>(isDefault),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProjectStatus copyWith({
    String? id,
    String? projectId,
    String? statusKey,
    String? name,
    String? colorToken,
    int? position,
    bool? isDone,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProjectStatus(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    statusKey: statusKey ?? this.statusKey,
    name: name ?? this.name,
    colorToken: colorToken ?? this.colorToken,
    position: position ?? this.position,
    isDone: isDone ?? this.isDone,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProjectStatus copyWithCompanion(ProjectStatusesCompanion data) {
    return ProjectStatus(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      statusKey: data.statusKey.present ? data.statusKey.value : this.statusKey,
      name: data.name.present ? data.name.value : this.name,
      colorToken: data.colorToken.present
          ? data.colorToken.value
          : this.colorToken,
      position: data.position.present ? data.position.value : this.position,
      isDone: data.isDone.present ? data.isDone.value : this.isDone,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectStatus(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('statusKey: $statusKey, ')
          ..write('name: $name, ')
          ..write('colorToken: $colorToken, ')
          ..write('position: $position, ')
          ..write('isDone: $isDone, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    statusKey,
    name,
    colorToken,
    position,
    isDone,
    isDefault,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectStatus &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.statusKey == this.statusKey &&
          other.name == this.name &&
          other.colorToken == this.colorToken &&
          other.position == this.position &&
          other.isDone == this.isDone &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectStatusesCompanion extends UpdateCompanion<ProjectStatus> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> statusKey;
  final Value<String> name;
  final Value<String> colorToken;
  final Value<int> position;
  final Value<bool> isDone;
  final Value<bool> isDefault;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProjectStatusesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.statusKey = const Value.absent(),
    this.name = const Value.absent(),
    this.colorToken = const Value.absent(),
    this.position = const Value.absent(),
    this.isDone = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectStatusesCompanion.insert({
    required String id,
    required String projectId,
    required String statusKey,
    required String name,
    this.colorToken = const Value.absent(),
    this.position = const Value.absent(),
    this.isDone = const Value.absent(),
    this.isDefault = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       statusKey = Value(statusKey),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProjectStatus> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? statusKey,
    Expression<String>? name,
    Expression<String>? colorToken,
    Expression<int>? position,
    Expression<bool>? isDone,
    Expression<bool>? isDefault,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (statusKey != null) 'status_key': statusKey,
      if (name != null) 'name': name,
      if (colorToken != null) 'color_token': colorToken,
      if (position != null) 'position': position,
      if (isDone != null) 'is_done': isDone,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectStatusesCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String>? statusKey,
    Value<String>? name,
    Value<String>? colorToken,
    Value<int>? position,
    Value<bool>? isDone,
    Value<bool>? isDefault,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectStatusesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      statusKey: statusKey ?? this.statusKey,
      name: name ?? this.name,
      colorToken: colorToken ?? this.colorToken,
      position: position ?? this.position,
      isDone: isDone ?? this.isDone,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (statusKey.present) {
      map['status_key'] = Variable<String>(statusKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorToken.present) {
      map['color_token'] = Variable<String>(colorToken.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (isDone.present) {
      map['is_done'] = Variable<bool>(isDone.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectStatusesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('statusKey: $statusKey, ')
          ..write('name: $name, ')
          ..write('colorToken: $colorToken, ')
          ..write('position: $position, ')
          ..write('isDone: $isDone, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectMilestonesTable extends ProjectMilestones
    with TableInfo<$ProjectMilestonesTable, ProjectMilestone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectMilestonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'REFERENCES projects(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetDateMeta = const VerificationMeta(
    'targetDate',
  );
  @override
  late final GeneratedColumn<DateTime> targetDate = GeneratedColumn<DateTime>(
    'target_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    title,
    description,
    targetDate,
    completedAt,
    position,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_milestones';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectMilestone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('target_date')) {
      context.handle(
        _targetDateMeta,
        targetDate.isAcceptableOrUnknown(data['target_date']!, _targetDateMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectMilestone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectMilestone(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      targetDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}target_date'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectMilestonesTable createAlias(String alias) {
    return $ProjectMilestonesTable(attachedDatabase, alias);
  }
}

class ProjectMilestone extends DataClass
    implements Insertable<ProjectMilestone> {
  final String id;
  final String projectId;
  final String title;
  final String? description;
  final DateTime? targetDate;
  final DateTime? completedAt;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProjectMilestone({
    required this.id,
    required this.projectId,
    required this.title,
    this.description,
    this.targetDate,
    this.completedAt,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<DateTime>(targetDate);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectMilestonesCompanion toCompanion(bool nullToAbsent) {
    return ProjectMilestonesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProjectMilestone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectMilestone(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      targetDate: serializer.fromJson<DateTime?>(json['targetDate']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'targetDate': serializer.toJson<DateTime?>(targetDate),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProjectMilestone copyWith({
    String? id,
    String? projectId,
    String? title,
    Value<String?> description = const Value.absent(),
    Value<DateTime?> targetDate = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProjectMilestone(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    targetDate: targetDate.present ? targetDate.value : this.targetDate,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProjectMilestone copyWithCompanion(ProjectMilestonesCompanion data) {
    return ProjectMilestone(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      targetDate: data.targetDate.present
          ? data.targetDate.value
          : this.targetDate,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectMilestone(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('targetDate: $targetDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    title,
    description,
    targetDate,
    completedAt,
    position,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectMilestone &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.title == this.title &&
          other.description == this.description &&
          other.targetDate == this.targetDate &&
          other.completedAt == this.completedAt &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectMilestonesCompanion extends UpdateCompanion<ProjectMilestone> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime?> targetDate;
  final Value<DateTime?> completedAt;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProjectMilestonesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectMilestonesCompanion.insert({
    required String id,
    required String projectId,
    required String title,
    this.description = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.position = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProjectMilestone> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? targetDate,
    Expression<DateTime>? completedAt,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (targetDate != null) 'target_date': targetDate,
      if (completedAt != null) 'completed_at': completedAt,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectMilestonesCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime?>? targetDate,
    Value<DateTime?>? completedAt,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectMilestonesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      targetDate: targetDate ?? this.targetDate,
      completedAt: completedAt ?? this.completedAt,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (targetDate.present) {
      map['target_date'] = Variable<DateTime>(targetDate.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectMilestonesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('targetDate: $targetDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskDependenciesTable extends TaskDependencies
    with TableInfo<$TaskDependenciesTable, TaskDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskDependenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _predecessorTaskIdMeta = const VerificationMeta(
    'predecessorTaskId',
  );
  @override
  late final GeneratedColumn<String> predecessorTaskId =
      GeneratedColumn<String>(
        'predecessor_task_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'REFERENCES tasks(id) ON DELETE CASCADE',
      );
  static const VerificationMeta _successorTaskIdMeta = const VerificationMeta(
    'successorTaskId',
  );
  @override
  late final GeneratedColumn<String> successorTaskId = GeneratedColumn<String>(
    'successor_task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'REFERENCES tasks(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _dependencyTypeMeta = const VerificationMeta(
    'dependencyType',
  );
  @override
  late final GeneratedColumn<String> dependencyType = GeneratedColumn<String>(
    'dependency_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('finish_to_start'),
  );
  static const VerificationMeta _lagMinutesMeta = const VerificationMeta(
    'lagMinutes',
  );
  @override
  late final GeneratedColumn<int> lagMinutes = GeneratedColumn<int>(
    'lag_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    predecessorTaskId,
    successorTaskId,
    dependencyType,
    lagMinutes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_dependencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskDependency> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('predecessor_task_id')) {
      context.handle(
        _predecessorTaskIdMeta,
        predecessorTaskId.isAcceptableOrUnknown(
          data['predecessor_task_id']!,
          _predecessorTaskIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_predecessorTaskIdMeta);
    }
    if (data.containsKey('successor_task_id')) {
      context.handle(
        _successorTaskIdMeta,
        successorTaskId.isAcceptableOrUnknown(
          data['successor_task_id']!,
          _successorTaskIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_successorTaskIdMeta);
    }
    if (data.containsKey('dependency_type')) {
      context.handle(
        _dependencyTypeMeta,
        dependencyType.isAcceptableOrUnknown(
          data['dependency_type']!,
          _dependencyTypeMeta,
        ),
      );
    }
    if (data.containsKey('lag_minutes')) {
      context.handle(
        _lagMinutesMeta,
        lagMinutes.isAcceptableOrUnknown(data['lag_minutes']!, _lagMinutesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {predecessorTaskId, successorTaskId},
  ];
  @override
  TaskDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskDependency(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      predecessorTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}predecessor_task_id'],
      )!,
      successorTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}successor_task_id'],
      )!,
      dependencyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dependency_type'],
      )!,
      lagMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lag_minutes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TaskDependenciesTable createAlias(String alias) {
    return $TaskDependenciesTable(attachedDatabase, alias);
  }
}

class TaskDependency extends DataClass implements Insertable<TaskDependency> {
  final String id;
  final String predecessorTaskId;
  final String successorTaskId;
  final String dependencyType;
  final int lagMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TaskDependency({
    required this.id,
    required this.predecessorTaskId,
    required this.successorTaskId,
    required this.dependencyType,
    required this.lagMinutes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['predecessor_task_id'] = Variable<String>(predecessorTaskId);
    map['successor_task_id'] = Variable<String>(successorTaskId);
    map['dependency_type'] = Variable<String>(dependencyType);
    map['lag_minutes'] = Variable<int>(lagMinutes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TaskDependenciesCompanion toCompanion(bool nullToAbsent) {
    return TaskDependenciesCompanion(
      id: Value(id),
      predecessorTaskId: Value(predecessorTaskId),
      successorTaskId: Value(successorTaskId),
      dependencyType: Value(dependencyType),
      lagMinutes: Value(lagMinutes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TaskDependency.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskDependency(
      id: serializer.fromJson<String>(json['id']),
      predecessorTaskId: serializer.fromJson<String>(json['predecessorTaskId']),
      successorTaskId: serializer.fromJson<String>(json['successorTaskId']),
      dependencyType: serializer.fromJson<String>(json['dependencyType']),
      lagMinutes: serializer.fromJson<int>(json['lagMinutes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'predecessorTaskId': serializer.toJson<String>(predecessorTaskId),
      'successorTaskId': serializer.toJson<String>(successorTaskId),
      'dependencyType': serializer.toJson<String>(dependencyType),
      'lagMinutes': serializer.toJson<int>(lagMinutes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TaskDependency copyWith({
    String? id,
    String? predecessorTaskId,
    String? successorTaskId,
    String? dependencyType,
    int? lagMinutes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TaskDependency(
    id: id ?? this.id,
    predecessorTaskId: predecessorTaskId ?? this.predecessorTaskId,
    successorTaskId: successorTaskId ?? this.successorTaskId,
    dependencyType: dependencyType ?? this.dependencyType,
    lagMinutes: lagMinutes ?? this.lagMinutes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TaskDependency copyWithCompanion(TaskDependenciesCompanion data) {
    return TaskDependency(
      id: data.id.present ? data.id.value : this.id,
      predecessorTaskId: data.predecessorTaskId.present
          ? data.predecessorTaskId.value
          : this.predecessorTaskId,
      successorTaskId: data.successorTaskId.present
          ? data.successorTaskId.value
          : this.successorTaskId,
      dependencyType: data.dependencyType.present
          ? data.dependencyType.value
          : this.dependencyType,
      lagMinutes: data.lagMinutes.present
          ? data.lagMinutes.value
          : this.lagMinutes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependency(')
          ..write('id: $id, ')
          ..write('predecessorTaskId: $predecessorTaskId, ')
          ..write('successorTaskId: $successorTaskId, ')
          ..write('dependencyType: $dependencyType, ')
          ..write('lagMinutes: $lagMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    predecessorTaskId,
    successorTaskId,
    dependencyType,
    lagMinutes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskDependency &&
          other.id == this.id &&
          other.predecessorTaskId == this.predecessorTaskId &&
          other.successorTaskId == this.successorTaskId &&
          other.dependencyType == this.dependencyType &&
          other.lagMinutes == this.lagMinutes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TaskDependenciesCompanion extends UpdateCompanion<TaskDependency> {
  final Value<String> id;
  final Value<String> predecessorTaskId;
  final Value<String> successorTaskId;
  final Value<String> dependencyType;
  final Value<int> lagMinutes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TaskDependenciesCompanion({
    this.id = const Value.absent(),
    this.predecessorTaskId = const Value.absent(),
    this.successorTaskId = const Value.absent(),
    this.dependencyType = const Value.absent(),
    this.lagMinutes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskDependenciesCompanion.insert({
    required String id,
    required String predecessorTaskId,
    required String successorTaskId,
    this.dependencyType = const Value.absent(),
    this.lagMinutes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       predecessorTaskId = Value(predecessorTaskId),
       successorTaskId = Value(successorTaskId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskDependency> custom({
    Expression<String>? id,
    Expression<String>? predecessorTaskId,
    Expression<String>? successorTaskId,
    Expression<String>? dependencyType,
    Expression<int>? lagMinutes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (predecessorTaskId != null) 'predecessor_task_id': predecessorTaskId,
      if (successorTaskId != null) 'successor_task_id': successorTaskId,
      if (dependencyType != null) 'dependency_type': dependencyType,
      if (lagMinutes != null) 'lag_minutes': lagMinutes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskDependenciesCompanion copyWith({
    Value<String>? id,
    Value<String>? predecessorTaskId,
    Value<String>? successorTaskId,
    Value<String>? dependencyType,
    Value<int>? lagMinutes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TaskDependenciesCompanion(
      id: id ?? this.id,
      predecessorTaskId: predecessorTaskId ?? this.predecessorTaskId,
      successorTaskId: successorTaskId ?? this.successorTaskId,
      dependencyType: dependencyType ?? this.dependencyType,
      lagMinutes: lagMinutes ?? this.lagMinutes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (predecessorTaskId.present) {
      map['predecessor_task_id'] = Variable<String>(predecessorTaskId.value);
    }
    if (successorTaskId.present) {
      map['successor_task_id'] = Variable<String>(successorTaskId.value);
    }
    if (dependencyType.present) {
      map['dependency_type'] = Variable<String>(dependencyType.value);
    }
    if (lagMinutes.present) {
      map['lag_minutes'] = Variable<int>(lagMinutes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependenciesCompanion(')
          ..write('id: $id, ')
          ..write('predecessorTaskId: $predecessorTaskId, ')
          ..write('successorTaskId: $successorTaskId, ')
          ..write('dependencyType: $dependencyType, ')
          ..write('lagMinutes: $lagMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    operation,
    payload,
    deviceId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  final int id;
  final String entityType;
  final String entityId;
  final String operation;
  final String payload;
  final String? deviceId;
  final DateTime createdAt;
  const SyncOutboxData({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    this.deviceId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: Value(payload),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      createdAt: Value(createdAt),
    );
  }

  factory SyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxData(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'deviceId': serializer.toJson<String?>(deviceId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncOutboxData copyWith({
    int? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? payload,
    Value<String?> deviceId = const Value.absent(),
    DateTime? createdAt,
  }) => SyncOutboxData(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncOutboxData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxData(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxData(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('deviceId: $deviceId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    operation,
    payload,
    deviceId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxData &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.deviceId == this.deviceId &&
          other.createdAt == this.createdAt);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String?> deviceId;
  final Value<DateTime> createdAt;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
    this.deviceId = const Value.absent(),
    required DateTime createdAt,
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<SyncOutboxData> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? deviceId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (deviceId != null) 'device_id': deviceId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payload,
    Value<String?>? deviceId,
    Value<DateTime>? createdAt,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('deviceId: $deviceId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EventsTable events = $EventsTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $ProgressLogsTable progressLogs = $ProgressLogsTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $DiaryEntriesTable diaryEntries = $DiaryEntriesTable(this);
  late final $HabitsTable habits = $HabitsTable(this);
  late final $HabitLogsTable habitLogs = $HabitLogsTable(this);
  late final $FocusSessionsTable focusSessions = $FocusSessionsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $TodoItemsTable todoItems = $TodoItemsTable(this);
  late final $TodoCompletionsTable todoCompletions = $TodoCompletionsTable(
    this,
  );
  late final $DailyPlansTable dailyPlans = $DailyPlansTable(this);
  late final $DailyPlanItemsTable dailyPlanItems = $DailyPlanItemsTable(this);
  late final $TaskScheduleBlocksTable taskScheduleBlocks =
      $TaskScheduleBlocksTable(this);
  late final $SavedFiltersTable savedFilters = $SavedFiltersTable(this);
  late final $PlanningPreferencesTable planningPreferences =
      $PlanningPreferencesTable(this);
  late final $WorkingHoursTable workingHours = $WorkingHoursTable(this);
  late final $WorkingBreaksTable workingBreaks = $WorkingBreaksTable(this);
  late final $ProjectStatusesTable projectStatuses = $ProjectStatusesTable(
    this,
  );
  late final $ProjectMilestonesTable projectMilestones =
      $ProjectMilestonesTable(this);
  late final $TaskDependenciesTable taskDependencies = $TaskDependenciesTable(
    this,
  );
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    events,
    projects,
    progressLogs,
    tasks,
    diaryEntries,
    habits,
    habitLogs,
    focusSessions,
    appSettings,
    todoItems,
    todoCompletions,
    dailyPlans,
    dailyPlanItems,
    taskScheduleBlocks,
    savedFilters,
    planningPreferences,
    workingHours,
    workingBreaks,
    projectStatuses,
    projectMilestones,
    taskDependencies,
    syncOutbox,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('progress_logs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'habits',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('habit_logs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('focus_sessions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('todo_items', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'todo_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('todo_completions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'daily_plans',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_plan_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'todo_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_plan_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_plan_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'todo_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_schedule_blocks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_schedule_blocks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('project_statuses', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('project_milestones', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_dependencies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_dependencies', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      required String id,
      required String title,
      Value<String?> description,
      required DateTime startTime,
      Value<DateTime?> endTime,
      Value<String> category,
      Value<bool> hasReminder,
      Value<int> reminderMinutes,
      Value<String?> recurrenceRule,
      Value<bool> allDay,
      Value<DateTime?> recurrenceEnd,
      Value<String> recurrenceExceptions,
      Value<int> rowid,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> description,
      Value<DateTime> startTime,
      Value<DateTime?> endTime,
      Value<String> category,
      Value<bool> hasReminder,
      Value<int> reminderMinutes,
      Value<String?> recurrenceRule,
      Value<bool> allDay,
      Value<DateTime?> recurrenceEnd,
      Value<String> recurrenceExceptions,
      Value<int> rowid,
    });

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasReminder => $composableBuilder(
    column: $table.hasReminder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderMinutes => $composableBuilder(
    column: $table.reminderMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recurrenceEnd => $composableBuilder(
    column: $table.recurrenceEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceExceptions => $composableBuilder(
    column: $table.recurrenceExceptions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasReminder => $composableBuilder(
    column: $table.hasReminder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderMinutes => $composableBuilder(
    column: $table.reminderMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recurrenceEnd => $composableBuilder(
    column: $table.recurrenceEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceExceptions => $composableBuilder(
    column: $table.recurrenceExceptions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<bool> get hasReminder => $composableBuilder(
    column: $table.hasReminder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderMinutes => $composableBuilder(
    column: $table.reminderMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allDay =>
      $composableBuilder(column: $table.allDay, builder: (column) => column);

  GeneratedColumn<DateTime> get recurrenceEnd => $composableBuilder(
    column: $table.recurrenceEnd,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recurrenceExceptions => $composableBuilder(
    column: $table.recurrenceExceptions,
    builder: (column) => column,
  );
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> startTime = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<bool> hasReminder = const Value.absent(),
                Value<int> reminderMinutes = const Value.absent(),
                Value<String?> recurrenceRule = const Value.absent(),
                Value<bool> allDay = const Value.absent(),
                Value<DateTime?> recurrenceEnd = const Value.absent(),
                Value<String> recurrenceExceptions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                title: title,
                description: description,
                startTime: startTime,
                endTime: endTime,
                category: category,
                hasReminder: hasReminder,
                reminderMinutes: reminderMinutes,
                recurrenceRule: recurrenceRule,
                allDay: allDay,
                recurrenceEnd: recurrenceEnd,
                recurrenceExceptions: recurrenceExceptions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> description = const Value.absent(),
                required DateTime startTime,
                Value<DateTime?> endTime = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<bool> hasReminder = const Value.absent(),
                Value<int> reminderMinutes = const Value.absent(),
                Value<String?> recurrenceRule = const Value.absent(),
                Value<bool> allDay = const Value.absent(),
                Value<DateTime?> recurrenceEnd = const Value.absent(),
                Value<String> recurrenceExceptions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                title: title,
                description: description,
                startTime: startTime,
                endTime: endTime,
                category: category,
                hasReminder: hasReminder,
                reminderMinutes: reminderMinutes,
                recurrenceRule: recurrenceRule,
                allDay: allDay,
                recurrenceEnd: recurrenceEnd,
                recurrenceExceptions: recurrenceExceptions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$ProjectsTableCreateCompanionBuilder =
    ProjectsCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      required DateTime createdAt,
      Value<DateTime?> targetDate,
      Value<int> targetProgress,
      Value<int> rowid,
    });
typedef $$ProjectsTableUpdateCompanionBuilder =
    ProjectsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime?> targetDate,
      Value<int> targetProgress,
      Value<int> rowid,
    });

final class $$ProjectsTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectsTable, Project> {
  $$ProjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProgressLogsTable, List<ProgressLog>>
  _progressLogsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.progressLogs,
    aliasName: $_aliasNameGenerator(db.projects.id, db.progressLogs.projectId),
  );

  $$ProgressLogsTableProcessedTableManager get progressLogsRefs {
    final manager = $$ProgressLogsTableTableManager(
      $_db,
      $_db.progressLogs,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_progressLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<Task>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: $_aliasNameGenerator(db.projects.id, db.tasks.projectId),
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FocusSessionsTable, List<FocusSession>>
  _focusSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.focusSessions,
    aliasName: $_aliasNameGenerator(db.projects.id, db.focusSessions.projectId),
  );

  $$FocusSessionsTableProcessedTableManager get focusSessionsRefs {
    final manager = $$FocusSessionsTableTableManager(
      $_db,
      $_db.focusSessions,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_focusSessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TodoItemsTable, List<TodoItem>>
  _todoItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.todoItems,
    aliasName: $_aliasNameGenerator(db.projects.id, db.todoItems.projectId),
  );

  $$TodoItemsTableProcessedTableManager get todoItemsRefs {
    final manager = $$TodoItemsTableTableManager(
      $_db,
      $_db.todoItems,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_todoItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProjectStatusesTable, List<ProjectStatus>>
  _projectStatusesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.projectStatuses,
    aliasName: $_aliasNameGenerator(
      db.projects.id,
      db.projectStatuses.projectId,
    ),
  );

  $$ProjectStatusesTableProcessedTableManager get projectStatusesRefs {
    final manager = $$ProjectStatusesTableTableManager(
      $_db,
      $_db.projectStatuses,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _projectStatusesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProjectMilestonesTable, List<ProjectMilestone>>
  _projectMilestonesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.projectMilestones,
        aliasName: $_aliasNameGenerator(
          db.projects.id,
          db.projectMilestones.projectId,
        ),
      );

  $$ProjectMilestonesTableProcessedTableManager get projectMilestonesRefs {
    final manager = $$ProjectMilestonesTableTableManager(
      $_db,
      $_db.projectMilestones,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _projectMilestonesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetProgress => $composableBuilder(
    column: $table.targetProgress,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> progressLogsRefs(
    Expression<bool> Function($$ProgressLogsTableFilterComposer f) f,
  ) {
    final $$ProgressLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.progressLogs,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgressLogsTableFilterComposer(
            $db: $db,
            $table: $db.progressLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> focusSessionsRefs(
    Expression<bool> Function($$FocusSessionsTableFilterComposer f) f,
  ) {
    final $$FocusSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.focusSessions,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FocusSessionsTableFilterComposer(
            $db: $db,
            $table: $db.focusSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> todoItemsRefs(
    Expression<bool> Function($$TodoItemsTableFilterComposer f) f,
  ) {
    final $$TodoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableFilterComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> projectStatusesRefs(
    Expression<bool> Function($$ProjectStatusesTableFilterComposer f) f,
  ) {
    final $$ProjectStatusesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectStatuses,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectStatusesTableFilterComposer(
            $db: $db,
            $table: $db.projectStatuses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> projectMilestonesRefs(
    Expression<bool> Function($$ProjectMilestonesTableFilterComposer f) f,
  ) {
    final $$ProjectMilestonesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectMilestones,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectMilestonesTableFilterComposer(
            $db: $db,
            $table: $db.projectMilestones,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetProgress => $composableBuilder(
    column: $table.targetProgress,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetProgress => $composableBuilder(
    column: $table.targetProgress,
    builder: (column) => column,
  );

  Expression<T> progressLogsRefs<T extends Object>(
    Expression<T> Function($$ProgressLogsTableAnnotationComposer a) f,
  ) {
    final $$ProgressLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.progressLogs,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgressLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.progressLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> focusSessionsRefs<T extends Object>(
    Expression<T> Function($$FocusSessionsTableAnnotationComposer a) f,
  ) {
    final $$FocusSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.focusSessions,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FocusSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.focusSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> todoItemsRefs<T extends Object>(
    Expression<T> Function($$TodoItemsTableAnnotationComposer a) f,
  ) {
    final $$TodoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> projectStatusesRefs<T extends Object>(
    Expression<T> Function($$ProjectStatusesTableAnnotationComposer a) f,
  ) {
    final $$ProjectStatusesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectStatuses,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectStatusesTableAnnotationComposer(
            $db: $db,
            $table: $db.projectStatuses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> projectMilestonesRefs<T extends Object>(
    Expression<T> Function($$ProjectMilestonesTableAnnotationComposer a) f,
  ) {
    final $$ProjectMilestonesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.projectMilestones,
          getReferencedColumn: (t) => t.projectId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProjectMilestonesTableAnnotationComposer(
                $db: $db,
                $table: $db.projectMilestones,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectsTable,
          Project,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (Project, $$ProjectsTableReferences),
          Project,
          PrefetchHooks Function({
            bool progressLogsRefs,
            bool tasksRefs,
            bool focusSessionsRefs,
            bool todoItemsRefs,
            bool projectStatusesRefs,
            bool projectMilestonesRefs,
          })
        > {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> targetDate = const Value.absent(),
                Value<int> targetProgress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                targetDate: targetDate,
                targetProgress: targetProgress,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> targetDate = const Value.absent(),
                Value<int> targetProgress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                targetDate: targetDate,
                targetProgress: targetProgress,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                progressLogsRefs = false,
                tasksRefs = false,
                focusSessionsRefs = false,
                todoItemsRefs = false,
                projectStatusesRefs = false,
                projectMilestonesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (progressLogsRefs) db.progressLogs,
                    if (tasksRefs) db.tasks,
                    if (focusSessionsRefs) db.focusSessions,
                    if (todoItemsRefs) db.todoItems,
                    if (projectStatusesRefs) db.projectStatuses,
                    if (projectMilestonesRefs) db.projectMilestones,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (progressLogsRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          ProgressLog
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._progressLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).progressLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tasksRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          Task
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._tasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).tasksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (focusSessionsRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          FocusSession
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._focusSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).focusSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (todoItemsRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          TodoItem
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._todoItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).todoItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (projectStatusesRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          ProjectStatus
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._projectStatusesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).projectStatusesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (projectMilestonesRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          ProjectMilestone
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._projectMilestonesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).projectMilestonesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectsTable,
      Project,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (Project, $$ProjectsTableReferences),
      Project,
      PrefetchHooks Function({
        bool progressLogsRefs,
        bool tasksRefs,
        bool focusSessionsRefs,
        bool todoItemsRefs,
        bool projectStatusesRefs,
        bool projectMilestonesRefs,
      })
    >;
typedef $$ProgressLogsTableCreateCompanionBuilder =
    ProgressLogsCompanion Function({
      required String id,
      required String projectId,
      required int value,
      Value<String?> note,
      required DateTime timestamp,
      Value<int> rowid,
    });
typedef $$ProgressLogsTableUpdateCompanionBuilder =
    ProgressLogsCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<int> value,
      Value<String?> note,
      Value<DateTime> timestamp,
      Value<int> rowid,
    });

final class $$ProgressLogsTableReferences
    extends BaseReferences<_$AppDatabase, $ProgressLogsTable, ProgressLog> {
  $$ProgressLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.progressLogs.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProgressLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ProgressLogsTable> {
  $$ProgressLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgressLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProgressLogsTable> {
  $$ProgressLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgressLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProgressLogsTable> {
  $$ProgressLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgressLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProgressLogsTable,
          ProgressLog,
          $$ProgressLogsTableFilterComposer,
          $$ProgressLogsTableOrderingComposer,
          $$ProgressLogsTableAnnotationComposer,
          $$ProgressLogsTableCreateCompanionBuilder,
          $$ProgressLogsTableUpdateCompanionBuilder,
          (ProgressLog, $$ProgressLogsTableReferences),
          ProgressLog,
          PrefetchHooks Function({bool projectId})
        > {
  $$ProgressLogsTableTableManager(_$AppDatabase db, $ProgressLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgressLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<int> value = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressLogsCompanion(
                id: id,
                projectId: projectId,
                value: value,
                note: note,
                timestamp: timestamp,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required int value,
                Value<String?> note = const Value.absent(),
                required DateTime timestamp,
                Value<int> rowid = const Value.absent(),
              }) => ProgressLogsCompanion.insert(
                id: id,
                projectId: projectId,
                value: value,
                note: note,
                timestamp: timestamp,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProgressLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable: $$ProgressLogsTableReferences
                                    ._projectIdTable(db),
                                referencedColumn: $$ProgressLogsTableReferences
                                    ._projectIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProgressLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProgressLogsTable,
      ProgressLog,
      $$ProgressLogsTableFilterComposer,
      $$ProgressLogsTableOrderingComposer,
      $$ProgressLogsTableAnnotationComposer,
      $$ProgressLogsTableCreateCompanionBuilder,
      $$ProgressLogsTableUpdateCompanionBuilder,
      (ProgressLog, $$ProgressLogsTableReferences),
      ProgressLog,
      PrefetchHooks Function({bool projectId})
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      required String id,
      required String projectId,
      required String title,
      Value<bool> completed,
      Value<String> statusKey,
      Value<DateTime?> startDate,
      Value<DateTime?> dueDate,
      Value<int?> estimatedMinutes,
      Value<int> priority,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String> title,
      Value<bool> completed,
      Value<String> statusKey,
      Value<DateTime?> startDate,
      Value<DateTime?> dueDate,
      Value<int?> estimatedMinutes,
      Value<int> priority,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProjectsTable _projectIdTable(_$AppDatabase db) => db.projects
      .createAlias($_aliasNameGenerator(db.tasks.projectId, db.projects.id));

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DailyPlanItemsTable, List<DailyPlanItem>>
  _dailyPlanItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.dailyPlanItems,
    aliasName: $_aliasNameGenerator(
      db.tasks.id,
      db.dailyPlanItems.projectTaskId,
    ),
  );

  $$DailyPlanItemsTableProcessedTableManager get dailyPlanItemsRefs {
    final manager = $$DailyPlanItemsTableTableManager(
      $_db,
      $_db.dailyPlanItems,
    ).filter((f) => f.projectTaskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_dailyPlanItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TaskScheduleBlocksTable, List<TaskScheduleBlock>>
  _taskScheduleBlocksRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.taskScheduleBlocks,
        aliasName: $_aliasNameGenerator(
          db.tasks.id,
          db.taskScheduleBlocks.projectTaskId,
        ),
      );

  $$TaskScheduleBlocksTableProcessedTableManager get taskScheduleBlocksRefs {
    final manager = $$TaskScheduleBlocksTableTableManager(
      $_db,
      $_db.taskScheduleBlocks,
    ).filter((f) => f.projectTaskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _taskScheduleBlocksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusKey => $composableBuilder(
    column: $table.statusKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> dailyPlanItemsRefs(
    Expression<bool> Function($$DailyPlanItemsTableFilterComposer f) f,
  ) {
    final $$DailyPlanItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyPlanItems,
      getReferencedColumn: (t) => t.projectTaskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlanItemsTableFilterComposer(
            $db: $db,
            $table: $db.dailyPlanItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskScheduleBlocksRefs(
    Expression<bool> Function($$TaskScheduleBlocksTableFilterComposer f) f,
  ) {
    final $$TaskScheduleBlocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskScheduleBlocks,
      getReferencedColumn: (t) => t.projectTaskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskScheduleBlocksTableFilterComposer(
            $db: $db,
            $table: $db.taskScheduleBlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusKey => $composableBuilder(
    column: $table.statusKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<String> get statusKey =>
      $composableBuilder(column: $table.statusKey, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> dailyPlanItemsRefs<T extends Object>(
    Expression<T> Function($$DailyPlanItemsTableAnnotationComposer a) f,
  ) {
    final $$DailyPlanItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyPlanItems,
      getReferencedColumn: (t) => t.projectTaskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlanItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.dailyPlanItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> taskScheduleBlocksRefs<T extends Object>(
    Expression<T> Function($$TaskScheduleBlocksTableAnnotationComposer a) f,
  ) {
    final $$TaskScheduleBlocksTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.taskScheduleBlocks,
          getReferencedColumn: (t) => t.projectTaskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TaskScheduleBlocksTableAnnotationComposer(
                $db: $db,
                $table: $db.taskScheduleBlocks,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, $$TasksTableReferences),
          Task,
          PrefetchHooks Function({
            bool projectId,
            bool dailyPlanItemsRefs,
            bool taskScheduleBlocksRefs,
          })
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<String> statusKey = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                projectId: projectId,
                title: title,
                completed: completed,
                statusKey: statusKey,
                startDate: startDate,
                dueDate: dueDate,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required String title,
                Value<bool> completed = const Value.absent(),
                Value<String> statusKey = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                projectId: projectId,
                title: title,
                completed: completed,
                statusKey: statusKey,
                startDate: startDate,
                dueDate: dueDate,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TasksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                projectId = false,
                dailyPlanItemsRefs = false,
                taskScheduleBlocksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dailyPlanItemsRefs) db.dailyPlanItems,
                    if (taskScheduleBlocksRefs) db.taskScheduleBlocks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (projectId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.projectId,
                                    referencedTable: $$TasksTableReferences
                                        ._projectIdTable(db),
                                    referencedColumn: $$TasksTableReferences
                                        ._projectIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dailyPlanItemsRefs)
                        await $_getPrefetchedData<
                          Task,
                          $TasksTable,
                          DailyPlanItem
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._dailyPlanItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).dailyPlanItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectTaskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskScheduleBlocksRefs)
                        await $_getPrefetchedData<
                          Task,
                          $TasksTable,
                          TaskScheduleBlock
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._taskScheduleBlocksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskScheduleBlocksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectTaskId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, $$TasksTableReferences),
      Task,
      PrefetchHooks Function({
        bool projectId,
        bool dailyPlanItemsRefs,
        bool taskScheduleBlocksRefs,
      })
    >;
typedef $$DiaryEntriesTableCreateCompanionBuilder =
    DiaryEntriesCompanion Function({
      required String id,
      required DateTime date,
      required int mood,
      required String content,
      Value<int> rowid,
    });
typedef $$DiaryEntriesTableUpdateCompanionBuilder =
    DiaryEntriesCompanion Function({
      Value<String> id,
      Value<DateTime> date,
      Value<int> mood,
      Value<String> content,
      Value<int> rowid,
    });

class $$DiaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);
}

class $$DiaryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiaryEntriesTable,
          DiaryEntry,
          $$DiaryEntriesTableFilterComposer,
          $$DiaryEntriesTableOrderingComposer,
          $$DiaryEntriesTableAnnotationComposer,
          $$DiaryEntriesTableCreateCompanionBuilder,
          $$DiaryEntriesTableUpdateCompanionBuilder,
          (
            DiaryEntry,
            BaseReferences<_$AppDatabase, $DiaryEntriesTable, DiaryEntry>,
          ),
          DiaryEntry,
          PrefetchHooks Function()
        > {
  $$DiaryEntriesTableTableManager(_$AppDatabase db, $DiaryEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiaryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int> mood = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntriesCompanion(
                id: id,
                date: date,
                mood: mood,
                content: content,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime date,
                required int mood,
                required String content,
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntriesCompanion.insert(
                id: id,
                date: date,
                mood: mood,
                content: content,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiaryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiaryEntriesTable,
      DiaryEntry,
      $$DiaryEntriesTableFilterComposer,
      $$DiaryEntriesTableOrderingComposer,
      $$DiaryEntriesTableAnnotationComposer,
      $$DiaryEntriesTableCreateCompanionBuilder,
      $$DiaryEntriesTableUpdateCompanionBuilder,
      (
        DiaryEntry,
        BaseReferences<_$AppDatabase, $DiaryEntriesTable, DiaryEntry>,
      ),
      DiaryEntry,
      PrefetchHooks Function()
    >;
typedef $$HabitsTableCreateCompanionBuilder =
    HabitsCompanion Function({
      required String id,
      required String name,
      Value<String> icon,
      required DateTime createdAt,
      Value<int> targetPerWeek,
      Value<int> rowid,
    });
typedef $$HabitsTableUpdateCompanionBuilder =
    HabitsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> icon,
      Value<DateTime> createdAt,
      Value<int> targetPerWeek,
      Value<int> rowid,
    });

final class $$HabitsTableReferences
    extends BaseReferences<_$AppDatabase, $HabitsTable, Habit> {
  $$HabitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$HabitLogsTable, List<HabitLog>>
  _habitLogsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.habitLogs,
    aliasName: $_aliasNameGenerator(db.habits.id, db.habitLogs.habitId),
  );

  $$HabitLogsTableProcessedTableManager get habitLogsRefs {
    final manager = $$HabitLogsTableTableManager(
      $_db,
      $_db.habitLogs,
    ).filter((f) => f.habitId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_habitLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HabitsTableFilterComposer
    extends Composer<_$AppDatabase, $HabitsTable> {
  $$HabitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetPerWeek => $composableBuilder(
    column: $table.targetPerWeek,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> habitLogsRefs(
    Expression<bool> Function($$HabitLogsTableFilterComposer f) f,
  ) {
    final $$HabitLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.habitLogs,
      getReferencedColumn: (t) => t.habitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitLogsTableFilterComposer(
            $db: $db,
            $table: $db.habitLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HabitsTableOrderingComposer
    extends Composer<_$AppDatabase, $HabitsTable> {
  $$HabitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetPerWeek => $composableBuilder(
    column: $table.targetPerWeek,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HabitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HabitsTable> {
  $$HabitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get targetPerWeek => $composableBuilder(
    column: $table.targetPerWeek,
    builder: (column) => column,
  );

  Expression<T> habitLogsRefs<T extends Object>(
    Expression<T> Function($$HabitLogsTableAnnotationComposer a) f,
  ) {
    final $$HabitLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.habitLogs,
      getReferencedColumn: (t) => t.habitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.habitLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HabitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HabitsTable,
          Habit,
          $$HabitsTableFilterComposer,
          $$HabitsTableOrderingComposer,
          $$HabitsTableAnnotationComposer,
          $$HabitsTableCreateCompanionBuilder,
          $$HabitsTableUpdateCompanionBuilder,
          (Habit, $$HabitsTableReferences),
          Habit,
          PrefetchHooks Function({bool habitLogsRefs})
        > {
  $$HabitsTableTableManager(_$AppDatabase db, $HabitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HabitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HabitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HabitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> targetPerWeek = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitsCompanion(
                id: id,
                name: name,
                icon: icon,
                createdAt: createdAt,
                targetPerWeek: targetPerWeek,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> icon = const Value.absent(),
                required DateTime createdAt,
                Value<int> targetPerWeek = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitsCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                createdAt: createdAt,
                targetPerWeek: targetPerWeek,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$HabitsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({habitLogsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (habitLogsRefs) db.habitLogs],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (habitLogsRefs)
                    await $_getPrefetchedData<Habit, $HabitsTable, HabitLog>(
                      currentTable: table,
                      referencedTable: $$HabitsTableReferences
                          ._habitLogsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$HabitsTableReferences(db, table, p0).habitLogsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.habitId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$HabitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HabitsTable,
      Habit,
      $$HabitsTableFilterComposer,
      $$HabitsTableOrderingComposer,
      $$HabitsTableAnnotationComposer,
      $$HabitsTableCreateCompanionBuilder,
      $$HabitsTableUpdateCompanionBuilder,
      (Habit, $$HabitsTableReferences),
      Habit,
      PrefetchHooks Function({bool habitLogsRefs})
    >;
typedef $$HabitLogsTableCreateCompanionBuilder =
    HabitLogsCompanion Function({
      required String id,
      required String habitId,
      required DateTime date,
      Value<bool> completed,
      Value<int> rowid,
    });
typedef $$HabitLogsTableUpdateCompanionBuilder =
    HabitLogsCompanion Function({
      Value<String> id,
      Value<String> habitId,
      Value<DateTime> date,
      Value<bool> completed,
      Value<int> rowid,
    });

final class $$HabitLogsTableReferences
    extends BaseReferences<_$AppDatabase, $HabitLogsTable, HabitLog> {
  $$HabitLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HabitsTable _habitIdTable(_$AppDatabase db) => db.habits.createAlias(
    $_aliasNameGenerator(db.habitLogs.habitId, db.habits.id),
  );

  $$HabitsTableProcessedTableManager get habitId {
    final $_column = $_itemColumn<String>('habit_id')!;

    final manager = $$HabitsTableTableManager(
      $_db,
      $_db.habits,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_habitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HabitLogsTableFilterComposer
    extends Composer<_$AppDatabase, $HabitLogsTable> {
  $$HabitLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  $$HabitsTableFilterComposer get habitId {
    final $$HabitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.habitId,
      referencedTable: $db.habits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitsTableFilterComposer(
            $db: $db,
            $table: $db.habits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HabitLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $HabitLogsTable> {
  $$HabitLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  $$HabitsTableOrderingComposer get habitId {
    final $$HabitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.habitId,
      referencedTable: $db.habits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitsTableOrderingComposer(
            $db: $db,
            $table: $db.habits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HabitLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HabitLogsTable> {
  $$HabitLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  $$HabitsTableAnnotationComposer get habitId {
    final $$HabitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.habitId,
      referencedTable: $db.habits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HabitsTableAnnotationComposer(
            $db: $db,
            $table: $db.habits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HabitLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HabitLogsTable,
          HabitLog,
          $$HabitLogsTableFilterComposer,
          $$HabitLogsTableOrderingComposer,
          $$HabitLogsTableAnnotationComposer,
          $$HabitLogsTableCreateCompanionBuilder,
          $$HabitLogsTableUpdateCompanionBuilder,
          (HabitLog, $$HabitLogsTableReferences),
          HabitLog,
          PrefetchHooks Function({bool habitId})
        > {
  $$HabitLogsTableTableManager(_$AppDatabase db, $HabitLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HabitLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HabitLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HabitLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> habitId = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitLogsCompanion(
                id: id,
                habitId: habitId,
                date: date,
                completed: completed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String habitId,
                required DateTime date,
                Value<bool> completed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HabitLogsCompanion.insert(
                id: id,
                habitId: habitId,
                date: date,
                completed: completed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HabitLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({habitId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (habitId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.habitId,
                                referencedTable: $$HabitLogsTableReferences
                                    ._habitIdTable(db),
                                referencedColumn: $$HabitLogsTableReferences
                                    ._habitIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HabitLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HabitLogsTable,
      HabitLog,
      $$HabitLogsTableFilterComposer,
      $$HabitLogsTableOrderingComposer,
      $$HabitLogsTableAnnotationComposer,
      $$HabitLogsTableCreateCompanionBuilder,
      $$HabitLogsTableUpdateCompanionBuilder,
      (HabitLog, $$HabitLogsTableReferences),
      HabitLog,
      PrefetchHooks Function({bool habitId})
    >;
typedef $$FocusSessionsTableCreateCompanionBuilder =
    FocusSessionsCompanion Function({
      required String id,
      Value<String?> projectId,
      required DateTime startTime,
      required int durationMinutes,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$FocusSessionsTableUpdateCompanionBuilder =
    FocusSessionsCompanion Function({
      Value<String> id,
      Value<String?> projectId,
      Value<DateTime> startTime,
      Value<int> durationMinutes,
      Value<String?> note,
      Value<int> rowid,
    });

final class $$FocusSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $FocusSessionsTable, FocusSession> {
  $$FocusSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.focusSessions.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager? get projectId {
    final $_column = $_itemColumn<String>('project_id');
    if ($_column == null) return null;
    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FocusSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FocusSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FocusSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FocusSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FocusSessionsTable,
          FocusSession,
          $$FocusSessionsTableFilterComposer,
          $$FocusSessionsTableOrderingComposer,
          $$FocusSessionsTableAnnotationComposer,
          $$FocusSessionsTableCreateCompanionBuilder,
          $$FocusSessionsTableUpdateCompanionBuilder,
          (FocusSession, $$FocusSessionsTableReferences),
          FocusSession,
          PrefetchHooks Function({bool projectId})
        > {
  $$FocusSessionsTableTableManager(_$AppDatabase db, $FocusSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<DateTime> startTime = const Value.absent(),
                Value<int> durationMinutes = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusSessionsCompanion(
                id: id,
                projectId: projectId,
                startTime: startTime,
                durationMinutes: durationMinutes,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> projectId = const Value.absent(),
                required DateTime startTime,
                required int durationMinutes,
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusSessionsCompanion.insert(
                id: id,
                projectId: projectId,
                startTime: startTime,
                durationMinutes: durationMinutes,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FocusSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable: $$FocusSessionsTableReferences
                                    ._projectIdTable(db),
                                referencedColumn: $$FocusSessionsTableReferences
                                    ._projectIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FocusSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FocusSessionsTable,
      FocusSession,
      $$FocusSessionsTableFilterComposer,
      $$FocusSessionsTableOrderingComposer,
      $$FocusSessionsTableAnnotationComposer,
      $$FocusSessionsTableCreateCompanionBuilder,
      $$FocusSessionsTableUpdateCompanionBuilder,
      (FocusSession, $$FocusSessionsTableReferences),
      FocusSession,
      PrefetchHooks Function({bool projectId})
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$TodoItemsTableCreateCompanionBuilder =
    TodoItemsCompanion Function({
      required String id,
      required String title,
      Value<String?> notes,
      Value<bool> completed,
      required DateTime createdAt,
      Value<DateTime?> startDate,
      Value<DateTime?> dueDate,
      Value<int> priority,
      Value<String> tags,
      Value<String?> recurrenceRule,
      Value<String?> parentId,
      Value<String?> projectId,
      Value<DateTime?> reminderAt,
      Value<int?> estimatedMinutes,
      Value<bool> isImportant,
      Value<bool?> urgencyOverride,
      Value<int> rowid,
    });
typedef $$TodoItemsTableUpdateCompanionBuilder =
    TodoItemsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> notes,
      Value<bool> completed,
      Value<DateTime> createdAt,
      Value<DateTime?> startDate,
      Value<DateTime?> dueDate,
      Value<int> priority,
      Value<String> tags,
      Value<String?> recurrenceRule,
      Value<String?> parentId,
      Value<String?> projectId,
      Value<DateTime?> reminderAt,
      Value<int?> estimatedMinutes,
      Value<bool> isImportant,
      Value<bool?> urgencyOverride,
      Value<int> rowid,
    });

final class $$TodoItemsTableReferences
    extends BaseReferences<_$AppDatabase, $TodoItemsTable, TodoItem> {
  $$TodoItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.todoItems.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager? get projectId {
    final $_column = $_itemColumn<String>('project_id');
    if ($_column == null) return null;
    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TodoCompletionsTable, List<TodoCompletion>>
  _todoCompletionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.todoCompletions,
    aliasName: $_aliasNameGenerator(db.todoItems.id, db.todoCompletions.todoId),
  );

  $$TodoCompletionsTableProcessedTableManager get todoCompletionsRefs {
    final manager = $$TodoCompletionsTableTableManager(
      $_db,
      $_db.todoCompletions,
    ).filter((f) => f.todoId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _todoCompletionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DailyPlanItemsTable, List<DailyPlanItem>>
  _dailyPlanItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.dailyPlanItems,
    aliasName: $_aliasNameGenerator(
      db.todoItems.id,
      db.dailyPlanItems.todoItemId,
    ),
  );

  $$DailyPlanItemsTableProcessedTableManager get dailyPlanItemsRefs {
    final manager = $$DailyPlanItemsTableTableManager(
      $_db,
      $_db.dailyPlanItems,
    ).filter((f) => f.todoItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_dailyPlanItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TaskScheduleBlocksTable, List<TaskScheduleBlock>>
  _taskScheduleBlocksRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.taskScheduleBlocks,
        aliasName: $_aliasNameGenerator(
          db.todoItems.id,
          db.taskScheduleBlocks.todoItemId,
        ),
      );

  $$TaskScheduleBlocksTableProcessedTableManager get taskScheduleBlocksRefs {
    final manager = $$TaskScheduleBlocksTableTableManager(
      $_db,
      $_db.taskScheduleBlocks,
    ).filter((f) => f.todoItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _taskScheduleBlocksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TodoItemsTableFilterComposer
    extends Composer<_$AppDatabase, $TodoItemsTable> {
  $$TodoItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reminderAt => $composableBuilder(
    column: $table.reminderAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isImportant => $composableBuilder(
    column: $table.isImportant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get urgencyOverride => $composableBuilder(
    column: $table.urgencyOverride,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> todoCompletionsRefs(
    Expression<bool> Function($$TodoCompletionsTableFilterComposer f) f,
  ) {
    final $$TodoCompletionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.todoCompletions,
      getReferencedColumn: (t) => t.todoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoCompletionsTableFilterComposer(
            $db: $db,
            $table: $db.todoCompletions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dailyPlanItemsRefs(
    Expression<bool> Function($$DailyPlanItemsTableFilterComposer f) f,
  ) {
    final $$DailyPlanItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyPlanItems,
      getReferencedColumn: (t) => t.todoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlanItemsTableFilterComposer(
            $db: $db,
            $table: $db.dailyPlanItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskScheduleBlocksRefs(
    Expression<bool> Function($$TaskScheduleBlocksTableFilterComposer f) f,
  ) {
    final $$TaskScheduleBlocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskScheduleBlocks,
      getReferencedColumn: (t) => t.todoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskScheduleBlocksTableFilterComposer(
            $db: $db,
            $table: $db.taskScheduleBlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TodoItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $TodoItemsTable> {
  $$TodoItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reminderAt => $composableBuilder(
    column: $table.reminderAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isImportant => $composableBuilder(
    column: $table.isImportant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get urgencyOverride => $composableBuilder(
    column: $table.urgencyOverride,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TodoItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TodoItemsTable> {
  $$TodoItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<DateTime> get reminderAt => $composableBuilder(
    column: $table.reminderAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isImportant => $composableBuilder(
    column: $table.isImportant,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get urgencyOverride => $composableBuilder(
    column: $table.urgencyOverride,
    builder: (column) => column,
  );

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> todoCompletionsRefs<T extends Object>(
    Expression<T> Function($$TodoCompletionsTableAnnotationComposer a) f,
  ) {
    final $$TodoCompletionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.todoCompletions,
      getReferencedColumn: (t) => t.todoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoCompletionsTableAnnotationComposer(
            $db: $db,
            $table: $db.todoCompletions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> dailyPlanItemsRefs<T extends Object>(
    Expression<T> Function($$DailyPlanItemsTableAnnotationComposer a) f,
  ) {
    final $$DailyPlanItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyPlanItems,
      getReferencedColumn: (t) => t.todoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlanItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.dailyPlanItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> taskScheduleBlocksRefs<T extends Object>(
    Expression<T> Function($$TaskScheduleBlocksTableAnnotationComposer a) f,
  ) {
    final $$TaskScheduleBlocksTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.taskScheduleBlocks,
          getReferencedColumn: (t) => t.todoItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TaskScheduleBlocksTableAnnotationComposer(
                $db: $db,
                $table: $db.taskScheduleBlocks,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TodoItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TodoItemsTable,
          TodoItem,
          $$TodoItemsTableFilterComposer,
          $$TodoItemsTableOrderingComposer,
          $$TodoItemsTableAnnotationComposer,
          $$TodoItemsTableCreateCompanionBuilder,
          $$TodoItemsTableUpdateCompanionBuilder,
          (TodoItem, $$TodoItemsTableReferences),
          TodoItem,
          PrefetchHooks Function({
            bool projectId,
            bool todoCompletionsRefs,
            bool dailyPlanItemsRefs,
            bool taskScheduleBlocksRefs,
          })
        > {
  $$TodoItemsTableTableManager(_$AppDatabase db, $TodoItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> recurrenceRule = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<DateTime?> reminderAt = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<bool> isImportant = const Value.absent(),
                Value<bool?> urgencyOverride = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoItemsCompanion(
                id: id,
                title: title,
                notes: notes,
                completed: completed,
                createdAt: createdAt,
                startDate: startDate,
                dueDate: dueDate,
                priority: priority,
                tags: tags,
                recurrenceRule: recurrenceRule,
                parentId: parentId,
                projectId: projectId,
                reminderAt: reminderAt,
                estimatedMinutes: estimatedMinutes,
                isImportant: isImportant,
                urgencyOverride: urgencyOverride,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> notes = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> recurrenceRule = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<DateTime?> reminderAt = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<bool> isImportant = const Value.absent(),
                Value<bool?> urgencyOverride = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoItemsCompanion.insert(
                id: id,
                title: title,
                notes: notes,
                completed: completed,
                createdAt: createdAt,
                startDate: startDate,
                dueDate: dueDate,
                priority: priority,
                tags: tags,
                recurrenceRule: recurrenceRule,
                parentId: parentId,
                projectId: projectId,
                reminderAt: reminderAt,
                estimatedMinutes: estimatedMinutes,
                isImportant: isImportant,
                urgencyOverride: urgencyOverride,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TodoItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                projectId = false,
                todoCompletionsRefs = false,
                dailyPlanItemsRefs = false,
                taskScheduleBlocksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (todoCompletionsRefs) db.todoCompletions,
                    if (dailyPlanItemsRefs) db.dailyPlanItems,
                    if (taskScheduleBlocksRefs) db.taskScheduleBlocks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (projectId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.projectId,
                                    referencedTable: $$TodoItemsTableReferences
                                        ._projectIdTable(db),
                                    referencedColumn: $$TodoItemsTableReferences
                                        ._projectIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (todoCompletionsRefs)
                        await $_getPrefetchedData<
                          TodoItem,
                          $TodoItemsTable,
                          TodoCompletion
                        >(
                          currentTable: table,
                          referencedTable: $$TodoItemsTableReferences
                              ._todoCompletionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TodoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).todoCompletionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.todoId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (dailyPlanItemsRefs)
                        await $_getPrefetchedData<
                          TodoItem,
                          $TodoItemsTable,
                          DailyPlanItem
                        >(
                          currentTable: table,
                          referencedTable: $$TodoItemsTableReferences
                              ._dailyPlanItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TodoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).dailyPlanItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.todoItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskScheduleBlocksRefs)
                        await $_getPrefetchedData<
                          TodoItem,
                          $TodoItemsTable,
                          TaskScheduleBlock
                        >(
                          currentTable: table,
                          referencedTable: $$TodoItemsTableReferences
                              ._taskScheduleBlocksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TodoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).taskScheduleBlocksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.todoItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TodoItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TodoItemsTable,
      TodoItem,
      $$TodoItemsTableFilterComposer,
      $$TodoItemsTableOrderingComposer,
      $$TodoItemsTableAnnotationComposer,
      $$TodoItemsTableCreateCompanionBuilder,
      $$TodoItemsTableUpdateCompanionBuilder,
      (TodoItem, $$TodoItemsTableReferences),
      TodoItem,
      PrefetchHooks Function({
        bool projectId,
        bool todoCompletionsRefs,
        bool dailyPlanItemsRefs,
        bool taskScheduleBlocksRefs,
      })
    >;
typedef $$TodoCompletionsTableCreateCompanionBuilder =
    TodoCompletionsCompanion Function({
      required String id,
      required String todoId,
      Value<DateTime?> occurrenceDue,
      required DateTime completedAt,
      Value<int> rowid,
    });
typedef $$TodoCompletionsTableUpdateCompanionBuilder =
    TodoCompletionsCompanion Function({
      Value<String> id,
      Value<String> todoId,
      Value<DateTime?> occurrenceDue,
      Value<DateTime> completedAt,
      Value<int> rowid,
    });

final class $$TodoCompletionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $TodoCompletionsTable, TodoCompletion> {
  $$TodoCompletionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TodoItemsTable _todoIdTable(_$AppDatabase db) =>
      db.todoItems.createAlias(
        $_aliasNameGenerator(db.todoCompletions.todoId, db.todoItems.id),
      );

  $$TodoItemsTableProcessedTableManager get todoId {
    final $_column = $_itemColumn<String>('todo_id')!;

    final manager = $$TodoItemsTableTableManager(
      $_db,
      $_db.todoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_todoIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TodoCompletionsTableFilterComposer
    extends Composer<_$AppDatabase, $TodoCompletionsTable> {
  $$TodoCompletionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurrenceDue => $composableBuilder(
    column: $table.occurrenceDue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TodoItemsTableFilterComposer get todoId {
    final $$TodoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableFilterComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TodoCompletionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TodoCompletionsTable> {
  $$TodoCompletionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurrenceDue => $composableBuilder(
    column: $table.occurrenceDue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TodoItemsTableOrderingComposer get todoId {
    final $$TodoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TodoCompletionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TodoCompletionsTable> {
  $$TodoCompletionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get occurrenceDue => $composableBuilder(
    column: $table.occurrenceDue,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  $$TodoItemsTableAnnotationComposer get todoId {
    final $$TodoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TodoCompletionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TodoCompletionsTable,
          TodoCompletion,
          $$TodoCompletionsTableFilterComposer,
          $$TodoCompletionsTableOrderingComposer,
          $$TodoCompletionsTableAnnotationComposer,
          $$TodoCompletionsTableCreateCompanionBuilder,
          $$TodoCompletionsTableUpdateCompanionBuilder,
          (TodoCompletion, $$TodoCompletionsTableReferences),
          TodoCompletion,
          PrefetchHooks Function({bool todoId})
        > {
  $$TodoCompletionsTableTableManager(
    _$AppDatabase db,
    $TodoCompletionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoCompletionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoCompletionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoCompletionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> todoId = const Value.absent(),
                Value<DateTime?> occurrenceDue = const Value.absent(),
                Value<DateTime> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoCompletionsCompanion(
                id: id,
                todoId: todoId,
                occurrenceDue: occurrenceDue,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String todoId,
                Value<DateTime?> occurrenceDue = const Value.absent(),
                required DateTime completedAt,
                Value<int> rowid = const Value.absent(),
              }) => TodoCompletionsCompanion.insert(
                id: id,
                todoId: todoId,
                occurrenceDue: occurrenceDue,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TodoCompletionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({todoId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (todoId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.todoId,
                                referencedTable:
                                    $$TodoCompletionsTableReferences
                                        ._todoIdTable(db),
                                referencedColumn:
                                    $$TodoCompletionsTableReferences
                                        ._todoIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TodoCompletionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TodoCompletionsTable,
      TodoCompletion,
      $$TodoCompletionsTableFilterComposer,
      $$TodoCompletionsTableOrderingComposer,
      $$TodoCompletionsTableAnnotationComposer,
      $$TodoCompletionsTableCreateCompanionBuilder,
      $$TodoCompletionsTableUpdateCompanionBuilder,
      (TodoCompletion, $$TodoCompletionsTableReferences),
      TodoCompletion,
      PrefetchHooks Function({bool todoId})
    >;
typedef $$DailyPlansTableCreateCompanionBuilder =
    DailyPlansCompanion Function({
      required String id,
      required String dayKey,
      Value<String?> intention,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$DailyPlansTableUpdateCompanionBuilder =
    DailyPlansCompanion Function({
      Value<String> id,
      Value<String> dayKey,
      Value<String?> intention,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$DailyPlansTableReferences
    extends BaseReferences<_$AppDatabase, $DailyPlansTable, DailyPlan> {
  $$DailyPlansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DailyPlanItemsTable, List<DailyPlanItem>>
  _dailyPlanItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.dailyPlanItems,
    aliasName: $_aliasNameGenerator(db.dailyPlans.id, db.dailyPlanItems.planId),
  );

  $$DailyPlanItemsTableProcessedTableManager get dailyPlanItemsRefs {
    final manager = $$DailyPlanItemsTableTableManager(
      $_db,
      $_db.dailyPlanItems,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_dailyPlanItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DailyPlansTableFilterComposer
    extends Composer<_$AppDatabase, $DailyPlansTable> {
  $$DailyPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayKey => $composableBuilder(
    column: $table.dayKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intention => $composableBuilder(
    column: $table.intention,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dailyPlanItemsRefs(
    Expression<bool> Function($$DailyPlanItemsTableFilterComposer f) f,
  ) {
    final $$DailyPlanItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyPlanItems,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlanItemsTableFilterComposer(
            $db: $db,
            $table: $db.dailyPlanItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DailyPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyPlansTable> {
  $$DailyPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayKey => $composableBuilder(
    column: $table.dayKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intention => $composableBuilder(
    column: $table.intention,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyPlansTable> {
  $$DailyPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<String> get intention =>
      $composableBuilder(column: $table.intention, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> dailyPlanItemsRefs<T extends Object>(
    Expression<T> Function($$DailyPlanItemsTableAnnotationComposer a) f,
  ) {
    final $$DailyPlanItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyPlanItems,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlanItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.dailyPlanItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DailyPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyPlansTable,
          DailyPlan,
          $$DailyPlansTableFilterComposer,
          $$DailyPlansTableOrderingComposer,
          $$DailyPlansTableAnnotationComposer,
          $$DailyPlansTableCreateCompanionBuilder,
          $$DailyPlansTableUpdateCompanionBuilder,
          (DailyPlan, $$DailyPlansTableReferences),
          DailyPlan,
          PrefetchHooks Function({bool dailyPlanItemsRefs})
        > {
  $$DailyPlansTableTableManager(_$AppDatabase db, $DailyPlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dayKey = const Value.absent(),
                Value<String?> intention = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyPlansCompanion(
                id: id,
                dayKey: dayKey,
                intention: intention,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dayKey,
                Value<String?> intention = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DailyPlansCompanion.insert(
                id: id,
                dayKey: dayKey,
                intention: intention,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DailyPlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({dailyPlanItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (dailyPlanItemsRefs) db.dailyPlanItems,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (dailyPlanItemsRefs)
                    await $_getPrefetchedData<
                      DailyPlan,
                      $DailyPlansTable,
                      DailyPlanItem
                    >(
                      currentTable: table,
                      referencedTable: $$DailyPlansTableReferences
                          ._dailyPlanItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$DailyPlansTableReferences(
                            db,
                            table,
                            p0,
                          ).dailyPlanItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.planId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DailyPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyPlansTable,
      DailyPlan,
      $$DailyPlansTableFilterComposer,
      $$DailyPlansTableOrderingComposer,
      $$DailyPlansTableAnnotationComposer,
      $$DailyPlansTableCreateCompanionBuilder,
      $$DailyPlansTableUpdateCompanionBuilder,
      (DailyPlan, $$DailyPlansTableReferences),
      DailyPlan,
      PrefetchHooks Function({bool dailyPlanItemsRefs})
    >;
typedef $$DailyPlanItemsTableCreateCompanionBuilder =
    DailyPlanItemsCompanion Function({
      required String id,
      required String planId,
      Value<String?> todoItemId,
      Value<String?> projectTaskId,
      Value<int> sortOrder,
      Value<int?> plannedMinutes,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$DailyPlanItemsTableUpdateCompanionBuilder =
    DailyPlanItemsCompanion Function({
      Value<String> id,
      Value<String> planId,
      Value<String?> todoItemId,
      Value<String?> projectTaskId,
      Value<int> sortOrder,
      Value<int?> plannedMinutes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$DailyPlanItemsTableReferences
    extends BaseReferences<_$AppDatabase, $DailyPlanItemsTable, DailyPlanItem> {
  $$DailyPlanItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DailyPlansTable _planIdTable(_$AppDatabase db) =>
      db.dailyPlans.createAlias(
        $_aliasNameGenerator(db.dailyPlanItems.planId, db.dailyPlans.id),
      );

  $$DailyPlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<String>('plan_id')!;

    final manager = $$DailyPlansTableTableManager(
      $_db,
      $_db.dailyPlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TodoItemsTable _todoItemIdTable(_$AppDatabase db) =>
      db.todoItems.createAlias(
        $_aliasNameGenerator(db.dailyPlanItems.todoItemId, db.todoItems.id),
      );

  $$TodoItemsTableProcessedTableManager? get todoItemId {
    final $_column = $_itemColumn<String>('todo_item_id');
    if ($_column == null) return null;
    final manager = $$TodoItemsTableTableManager(
      $_db,
      $_db.todoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_todoItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _projectTaskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias(
        $_aliasNameGenerator(db.dailyPlanItems.projectTaskId, db.tasks.id),
      );

  $$TasksTableProcessedTableManager? get projectTaskId {
    final $_column = $_itemColumn<String>('project_task_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DailyPlanItemsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyPlanItemsTable> {
  $$DailyPlanItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$DailyPlansTableFilterComposer get planId {
    final $$DailyPlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.dailyPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlansTableFilterComposer(
            $db: $db,
            $table: $db.dailyPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TodoItemsTableFilterComposer get todoItemId {
    final $$TodoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoItemId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableFilterComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get projectTaskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyPlanItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyPlanItemsTable> {
  $$DailyPlanItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$DailyPlansTableOrderingComposer get planId {
    final $$DailyPlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.dailyPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlansTableOrderingComposer(
            $db: $db,
            $table: $db.dailyPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TodoItemsTableOrderingComposer get todoItemId {
    final $$TodoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoItemId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get projectTaskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyPlanItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyPlanItemsTable> {
  $$DailyPlanItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$DailyPlansTableAnnotationComposer get planId {
    final $$DailyPlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.dailyPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyPlansTableAnnotationComposer(
            $db: $db,
            $table: $db.dailyPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TodoItemsTableAnnotationComposer get todoItemId {
    final $$TodoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoItemId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get projectTaskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyPlanItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyPlanItemsTable,
          DailyPlanItem,
          $$DailyPlanItemsTableFilterComposer,
          $$DailyPlanItemsTableOrderingComposer,
          $$DailyPlanItemsTableAnnotationComposer,
          $$DailyPlanItemsTableCreateCompanionBuilder,
          $$DailyPlanItemsTableUpdateCompanionBuilder,
          (DailyPlanItem, $$DailyPlanItemsTableReferences),
          DailyPlanItem,
          PrefetchHooks Function({
            bool planId,
            bool todoItemId,
            bool projectTaskId,
          })
        > {
  $$DailyPlanItemsTableTableManager(
    _$AppDatabase db,
    $DailyPlanItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyPlanItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyPlanItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyPlanItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<String?> todoItemId = const Value.absent(),
                Value<String?> projectTaskId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int?> plannedMinutes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyPlanItemsCompanion(
                id: id,
                planId: planId,
                todoItemId: todoItemId,
                projectTaskId: projectTaskId,
                sortOrder: sortOrder,
                plannedMinutes: plannedMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String planId,
                Value<String?> todoItemId = const Value.absent(),
                Value<String?> projectTaskId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int?> plannedMinutes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DailyPlanItemsCompanion.insert(
                id: id,
                planId: planId,
                todoItemId: todoItemId,
                projectTaskId: projectTaskId,
                sortOrder: sortOrder,
                plannedMinutes: plannedMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DailyPlanItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({planId = false, todoItemId = false, projectTaskId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (planId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.planId,
                                    referencedTable:
                                        $$DailyPlanItemsTableReferences
                                            ._planIdTable(db),
                                    referencedColumn:
                                        $$DailyPlanItemsTableReferences
                                            ._planIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (todoItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.todoItemId,
                                    referencedTable:
                                        $$DailyPlanItemsTableReferences
                                            ._todoItemIdTable(db),
                                    referencedColumn:
                                        $$DailyPlanItemsTableReferences
                                            ._todoItemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (projectTaskId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.projectTaskId,
                                    referencedTable:
                                        $$DailyPlanItemsTableReferences
                                            ._projectTaskIdTable(db),
                                    referencedColumn:
                                        $$DailyPlanItemsTableReferences
                                            ._projectTaskIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$DailyPlanItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyPlanItemsTable,
      DailyPlanItem,
      $$DailyPlanItemsTableFilterComposer,
      $$DailyPlanItemsTableOrderingComposer,
      $$DailyPlanItemsTableAnnotationComposer,
      $$DailyPlanItemsTableCreateCompanionBuilder,
      $$DailyPlanItemsTableUpdateCompanionBuilder,
      (DailyPlanItem, $$DailyPlanItemsTableReferences),
      DailyPlanItem,
      PrefetchHooks Function({bool planId, bool todoItemId, bool projectTaskId})
    >;
typedef $$TaskScheduleBlocksTableCreateCompanionBuilder =
    TaskScheduleBlocksCompanion Function({
      required String id,
      Value<String?> todoItemId,
      Value<String?> projectTaskId,
      required DateTime startAt,
      required DateTime endAt,
      Value<String?> timezoneId,
      Value<String> blockKind,
      Value<String?> note,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$TaskScheduleBlocksTableUpdateCompanionBuilder =
    TaskScheduleBlocksCompanion Function({
      Value<String> id,
      Value<String?> todoItemId,
      Value<String?> projectTaskId,
      Value<DateTime> startAt,
      Value<DateTime> endAt,
      Value<String?> timezoneId,
      Value<String> blockKind,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$TaskScheduleBlocksTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TaskScheduleBlocksTable,
          TaskScheduleBlock
        > {
  $$TaskScheduleBlocksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TodoItemsTable _todoItemIdTable(_$AppDatabase db) =>
      db.todoItems.createAlias(
        $_aliasNameGenerator(db.taskScheduleBlocks.todoItemId, db.todoItems.id),
      );

  $$TodoItemsTableProcessedTableManager? get todoItemId {
    final $_column = $_itemColumn<String>('todo_item_id');
    if ($_column == null) return null;
    final manager = $$TodoItemsTableTableManager(
      $_db,
      $_db.todoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_todoItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _projectTaskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias(
        $_aliasNameGenerator(db.taskScheduleBlocks.projectTaskId, db.tasks.id),
      );

  $$TasksTableProcessedTableManager? get projectTaskId {
    final $_column = $_itemColumn<String>('project_task_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskScheduleBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $TaskScheduleBlocksTable> {
  $$TaskScheduleBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezoneId => $composableBuilder(
    column: $table.timezoneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockKind => $composableBuilder(
    column: $table.blockKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$TodoItemsTableFilterComposer get todoItemId {
    final $$TodoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoItemId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableFilterComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get projectTaskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskScheduleBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskScheduleBlocksTable> {
  $$TaskScheduleBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezoneId => $composableBuilder(
    column: $table.timezoneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockKind => $composableBuilder(
    column: $table.blockKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$TodoItemsTableOrderingComposer get todoItemId {
    final $$TodoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoItemId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get projectTaskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskScheduleBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskScheduleBlocksTable> {
  $$TaskScheduleBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<String> get timezoneId => $composableBuilder(
    column: $table.timezoneId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blockKind =>
      $composableBuilder(column: $table.blockKind, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$TodoItemsTableAnnotationComposer get todoItemId {
    final $$TodoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.todoItemId,
      referencedTable: $db.todoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TodoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.todoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get projectTaskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskScheduleBlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskScheduleBlocksTable,
          TaskScheduleBlock,
          $$TaskScheduleBlocksTableFilterComposer,
          $$TaskScheduleBlocksTableOrderingComposer,
          $$TaskScheduleBlocksTableAnnotationComposer,
          $$TaskScheduleBlocksTableCreateCompanionBuilder,
          $$TaskScheduleBlocksTableUpdateCompanionBuilder,
          (TaskScheduleBlock, $$TaskScheduleBlocksTableReferences),
          TaskScheduleBlock,
          PrefetchHooks Function({bool todoItemId, bool projectTaskId})
        > {
  $$TaskScheduleBlocksTableTableManager(
    _$AppDatabase db,
    $TaskScheduleBlocksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskScheduleBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskScheduleBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskScheduleBlocksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> todoItemId = const Value.absent(),
                Value<String?> projectTaskId = const Value.absent(),
                Value<DateTime> startAt = const Value.absent(),
                Value<DateTime> endAt = const Value.absent(),
                Value<String?> timezoneId = const Value.absent(),
                Value<String> blockKind = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskScheduleBlocksCompanion(
                id: id,
                todoItemId: todoItemId,
                projectTaskId: projectTaskId,
                startAt: startAt,
                endAt: endAt,
                timezoneId: timezoneId,
                blockKind: blockKind,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> todoItemId = const Value.absent(),
                Value<String?> projectTaskId = const Value.absent(),
                required DateTime startAt,
                required DateTime endAt,
                Value<String?> timezoneId = const Value.absent(),
                Value<String> blockKind = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskScheduleBlocksCompanion.insert(
                id: id,
                todoItemId: todoItemId,
                projectTaskId: projectTaskId,
                startAt: startAt,
                endAt: endAt,
                timezoneId: timezoneId,
                blockKind: blockKind,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskScheduleBlocksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({todoItemId = false, projectTaskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (todoItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.todoItemId,
                                referencedTable:
                                    $$TaskScheduleBlocksTableReferences
                                        ._todoItemIdTable(db),
                                referencedColumn:
                                    $$TaskScheduleBlocksTableReferences
                                        ._todoItemIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (projectTaskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectTaskId,
                                referencedTable:
                                    $$TaskScheduleBlocksTableReferences
                                        ._projectTaskIdTable(db),
                                referencedColumn:
                                    $$TaskScheduleBlocksTableReferences
                                        ._projectTaskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskScheduleBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskScheduleBlocksTable,
      TaskScheduleBlock,
      $$TaskScheduleBlocksTableFilterComposer,
      $$TaskScheduleBlocksTableOrderingComposer,
      $$TaskScheduleBlocksTableAnnotationComposer,
      $$TaskScheduleBlocksTableCreateCompanionBuilder,
      $$TaskScheduleBlocksTableUpdateCompanionBuilder,
      (TaskScheduleBlock, $$TaskScheduleBlocksTableReferences),
      TaskScheduleBlock,
      PrefetchHooks Function({bool todoItemId, bool projectTaskId})
    >;
typedef $$SavedFiltersTableCreateCompanionBuilder =
    SavedFiltersCompanion Function({
      required String id,
      required String name,
      required String entityScope,
      required String filterJson,
      Value<String> sortJson,
      Value<bool> isPinned,
      Value<int> position,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> definitionVersion,
      Value<int> rowid,
    });
typedef $$SavedFiltersTableUpdateCompanionBuilder =
    SavedFiltersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> entityScope,
      Value<String> filterJson,
      Value<String> sortJson,
      Value<bool> isPinned,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> definitionVersion,
      Value<int> rowid,
    });

class $$SavedFiltersTableFilterComposer
    extends Composer<_$AppDatabase, $SavedFiltersTable> {
  $$SavedFiltersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityScope => $composableBuilder(
    column: $table.entityScope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filterJson => $composableBuilder(
    column: $table.filterJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortJson => $composableBuilder(
    column: $table.sortJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedFiltersTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedFiltersTable> {
  $$SavedFiltersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityScope => $composableBuilder(
    column: $table.entityScope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filterJson => $composableBuilder(
    column: $table.filterJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortJson => $composableBuilder(
    column: $table.sortJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedFiltersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedFiltersTable> {
  $$SavedFiltersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get entityScope => $composableBuilder(
    column: $table.entityScope,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filterJson => $composableBuilder(
    column: $table.filterJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sortJson =>
      $composableBuilder(column: $table.sortJson, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => column,
  );
}

class $$SavedFiltersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedFiltersTable,
          SavedFilter,
          $$SavedFiltersTableFilterComposer,
          $$SavedFiltersTableOrderingComposer,
          $$SavedFiltersTableAnnotationComposer,
          $$SavedFiltersTableCreateCompanionBuilder,
          $$SavedFiltersTableUpdateCompanionBuilder,
          (
            SavedFilter,
            BaseReferences<_$AppDatabase, $SavedFiltersTable, SavedFilter>,
          ),
          SavedFilter,
          PrefetchHooks Function()
        > {
  $$SavedFiltersTableTableManager(_$AppDatabase db, $SavedFiltersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedFiltersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedFiltersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedFiltersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> entityScope = const Value.absent(),
                Value<String> filterJson = const Value.absent(),
                Value<String> sortJson = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> definitionVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedFiltersCompanion(
                id: id,
                name: name,
                entityScope: entityScope,
                filterJson: filterJson,
                sortJson: sortJson,
                isPinned: isPinned,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                definitionVersion: definitionVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String entityScope,
                required String filterJson,
                Value<String> sortJson = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> position = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> definitionVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedFiltersCompanion.insert(
                id: id,
                name: name,
                entityScope: entityScope,
                filterJson: filterJson,
                sortJson: sortJson,
                isPinned: isPinned,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                definitionVersion: definitionVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedFiltersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedFiltersTable,
      SavedFilter,
      $$SavedFiltersTableFilterComposer,
      $$SavedFiltersTableOrderingComposer,
      $$SavedFiltersTableAnnotationComposer,
      $$SavedFiltersTableCreateCompanionBuilder,
      $$SavedFiltersTableUpdateCompanionBuilder,
      (
        SavedFilter,
        BaseReferences<_$AppDatabase, $SavedFiltersTable, SavedFilter>,
      ),
      SavedFilter,
      PrefetchHooks Function()
    >;
typedef $$PlanningPreferencesTableCreateCompanionBuilder =
    PlanningPreferencesCompanion Function({
      required String id,
      Value<String?> timezoneId,
      Value<int> defaultSlotMinutes,
      Value<int> weekStartDay,
      Value<int> dayStartMinute,
      Value<int> dayEndMinute,
      Value<int> bufferMinutes,
      Value<int> urgencyWindowDays,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlanningPreferencesTableUpdateCompanionBuilder =
    PlanningPreferencesCompanion Function({
      Value<String> id,
      Value<String?> timezoneId,
      Value<int> defaultSlotMinutes,
      Value<int> weekStartDay,
      Value<int> dayStartMinute,
      Value<int> dayEndMinute,
      Value<int> bufferMinutes,
      Value<int> urgencyWindowDays,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PlanningPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $PlanningPreferencesTable> {
  $$PlanningPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezoneId => $composableBuilder(
    column: $table.timezoneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultSlotMinutes => $composableBuilder(
    column: $table.defaultSlotMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekStartDay => $composableBuilder(
    column: $table.weekStartDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayStartMinute => $composableBuilder(
    column: $table.dayStartMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayEndMinute => $composableBuilder(
    column: $table.dayEndMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bufferMinutes => $composableBuilder(
    column: $table.bufferMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get urgencyWindowDays => $composableBuilder(
    column: $table.urgencyWindowDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlanningPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanningPreferencesTable> {
  $$PlanningPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezoneId => $composableBuilder(
    column: $table.timezoneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultSlotMinutes => $composableBuilder(
    column: $table.defaultSlotMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekStartDay => $composableBuilder(
    column: $table.weekStartDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayStartMinute => $composableBuilder(
    column: $table.dayStartMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayEndMinute => $composableBuilder(
    column: $table.dayEndMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bufferMinutes => $composableBuilder(
    column: $table.bufferMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get urgencyWindowDays => $composableBuilder(
    column: $table.urgencyWindowDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanningPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanningPreferencesTable> {
  $$PlanningPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get timezoneId => $composableBuilder(
    column: $table.timezoneId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get defaultSlotMinutes => $composableBuilder(
    column: $table.defaultSlotMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weekStartDay => $composableBuilder(
    column: $table.weekStartDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dayStartMinute => $composableBuilder(
    column: $table.dayStartMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dayEndMinute => $composableBuilder(
    column: $table.dayEndMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bufferMinutes => $composableBuilder(
    column: $table.bufferMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get urgencyWindowDays => $composableBuilder(
    column: $table.urgencyWindowDays,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlanningPreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanningPreferencesTable,
          PlanningPreference,
          $$PlanningPreferencesTableFilterComposer,
          $$PlanningPreferencesTableOrderingComposer,
          $$PlanningPreferencesTableAnnotationComposer,
          $$PlanningPreferencesTableCreateCompanionBuilder,
          $$PlanningPreferencesTableUpdateCompanionBuilder,
          (
            PlanningPreference,
            BaseReferences<
              _$AppDatabase,
              $PlanningPreferencesTable,
              PlanningPreference
            >,
          ),
          PlanningPreference,
          PrefetchHooks Function()
        > {
  $$PlanningPreferencesTableTableManager(
    _$AppDatabase db,
    $PlanningPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanningPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanningPreferencesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlanningPreferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> timezoneId = const Value.absent(),
                Value<int> defaultSlotMinutes = const Value.absent(),
                Value<int> weekStartDay = const Value.absent(),
                Value<int> dayStartMinute = const Value.absent(),
                Value<int> dayEndMinute = const Value.absent(),
                Value<int> bufferMinutes = const Value.absent(),
                Value<int> urgencyWindowDays = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanningPreferencesCompanion(
                id: id,
                timezoneId: timezoneId,
                defaultSlotMinutes: defaultSlotMinutes,
                weekStartDay: weekStartDay,
                dayStartMinute: dayStartMinute,
                dayEndMinute: dayEndMinute,
                bufferMinutes: bufferMinutes,
                urgencyWindowDays: urgencyWindowDays,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> timezoneId = const Value.absent(),
                Value<int> defaultSlotMinutes = const Value.absent(),
                Value<int> weekStartDay = const Value.absent(),
                Value<int> dayStartMinute = const Value.absent(),
                Value<int> dayEndMinute = const Value.absent(),
                Value<int> bufferMinutes = const Value.absent(),
                Value<int> urgencyWindowDays = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanningPreferencesCompanion.insert(
                id: id,
                timezoneId: timezoneId,
                defaultSlotMinutes: defaultSlotMinutes,
                weekStartDay: weekStartDay,
                dayStartMinute: dayStartMinute,
                dayEndMinute: dayEndMinute,
                bufferMinutes: bufferMinutes,
                urgencyWindowDays: urgencyWindowDays,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlanningPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanningPreferencesTable,
      PlanningPreference,
      $$PlanningPreferencesTableFilterComposer,
      $$PlanningPreferencesTableOrderingComposer,
      $$PlanningPreferencesTableAnnotationComposer,
      $$PlanningPreferencesTableCreateCompanionBuilder,
      $$PlanningPreferencesTableUpdateCompanionBuilder,
      (
        PlanningPreference,
        BaseReferences<
          _$AppDatabase,
          $PlanningPreferencesTable,
          PlanningPreference
        >,
      ),
      PlanningPreference,
      PrefetchHooks Function()
    >;
typedef $$WorkingHoursTableCreateCompanionBuilder =
    WorkingHoursCompanion Function({
      required String id,
      required int weekday,
      Value<bool> enabled,
      required int startMinute,
      required int endMinute,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$WorkingHoursTableUpdateCompanionBuilder =
    WorkingHoursCompanion Function({
      Value<String> id,
      Value<int> weekday,
      Value<bool> enabled,
      Value<int> startMinute,
      Value<int> endMinute,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$WorkingHoursTableFilterComposer
    extends Composer<_$AppDatabase, $WorkingHoursTable> {
  $$WorkingHoursTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkingHoursTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkingHoursTable> {
  $$WorkingHoursTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkingHoursTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkingHoursTable> {
  $$WorkingHoursTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WorkingHoursTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkingHoursTable,
          WorkingHour,
          $$WorkingHoursTableFilterComposer,
          $$WorkingHoursTableOrderingComposer,
          $$WorkingHoursTableAnnotationComposer,
          $$WorkingHoursTableCreateCompanionBuilder,
          $$WorkingHoursTableUpdateCompanionBuilder,
          (
            WorkingHour,
            BaseReferences<_$AppDatabase, $WorkingHoursTable, WorkingHour>,
          ),
          WorkingHour,
          PrefetchHooks Function()
        > {
  $$WorkingHoursTableTableManager(_$AppDatabase db, $WorkingHoursTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkingHoursTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkingHoursTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkingHoursTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> startMinute = const Value.absent(),
                Value<int> endMinute = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkingHoursCompanion(
                id: id,
                weekday: weekday,
                enabled: enabled,
                startMinute: startMinute,
                endMinute: endMinute,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int weekday,
                Value<bool> enabled = const Value.absent(),
                required int startMinute,
                required int endMinute,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WorkingHoursCompanion.insert(
                id: id,
                weekday: weekday,
                enabled: enabled,
                startMinute: startMinute,
                endMinute: endMinute,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkingHoursTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkingHoursTable,
      WorkingHour,
      $$WorkingHoursTableFilterComposer,
      $$WorkingHoursTableOrderingComposer,
      $$WorkingHoursTableAnnotationComposer,
      $$WorkingHoursTableCreateCompanionBuilder,
      $$WorkingHoursTableUpdateCompanionBuilder,
      (
        WorkingHour,
        BaseReferences<_$AppDatabase, $WorkingHoursTable, WorkingHour>,
      ),
      WorkingHour,
      PrefetchHooks Function()
    >;
typedef $$WorkingBreaksTableCreateCompanionBuilder =
    WorkingBreaksCompanion Function({
      required String id,
      required int weekday,
      required int startMinute,
      required int endMinute,
      Value<String?> label,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$WorkingBreaksTableUpdateCompanionBuilder =
    WorkingBreaksCompanion Function({
      Value<String> id,
      Value<int> weekday,
      Value<int> startMinute,
      Value<int> endMinute,
      Value<String?> label,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$WorkingBreaksTableFilterComposer
    extends Composer<_$AppDatabase, $WorkingBreaksTable> {
  $$WorkingBreaksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkingBreaksTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkingBreaksTable> {
  $$WorkingBreaksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkingBreaksTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkingBreaksTable> {
  $$WorkingBreaksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WorkingBreaksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkingBreaksTable,
          WorkingBreak,
          $$WorkingBreaksTableFilterComposer,
          $$WorkingBreaksTableOrderingComposer,
          $$WorkingBreaksTableAnnotationComposer,
          $$WorkingBreaksTableCreateCompanionBuilder,
          $$WorkingBreaksTableUpdateCompanionBuilder,
          (
            WorkingBreak,
            BaseReferences<_$AppDatabase, $WorkingBreaksTable, WorkingBreak>,
          ),
          WorkingBreak,
          PrefetchHooks Function()
        > {
  $$WorkingBreaksTableTableManager(_$AppDatabase db, $WorkingBreaksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkingBreaksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkingBreaksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkingBreaksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<int> startMinute = const Value.absent(),
                Value<int> endMinute = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkingBreaksCompanion(
                id: id,
                weekday: weekday,
                startMinute: startMinute,
                endMinute: endMinute,
                label: label,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int weekday,
                required int startMinute,
                required int endMinute,
                Value<String?> label = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WorkingBreaksCompanion.insert(
                id: id,
                weekday: weekday,
                startMinute: startMinute,
                endMinute: endMinute,
                label: label,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkingBreaksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkingBreaksTable,
      WorkingBreak,
      $$WorkingBreaksTableFilterComposer,
      $$WorkingBreaksTableOrderingComposer,
      $$WorkingBreaksTableAnnotationComposer,
      $$WorkingBreaksTableCreateCompanionBuilder,
      $$WorkingBreaksTableUpdateCompanionBuilder,
      (
        WorkingBreak,
        BaseReferences<_$AppDatabase, $WorkingBreaksTable, WorkingBreak>,
      ),
      WorkingBreak,
      PrefetchHooks Function()
    >;
typedef $$ProjectStatusesTableCreateCompanionBuilder =
    ProjectStatusesCompanion Function({
      required String id,
      required String projectId,
      required String statusKey,
      required String name,
      Value<String> colorToken,
      Value<int> position,
      Value<bool> isDone,
      Value<bool> isDefault,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectStatusesTableUpdateCompanionBuilder =
    ProjectStatusesCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String> statusKey,
      Value<String> name,
      Value<String> colorToken,
      Value<int> position,
      Value<bool> isDone,
      Value<bool> isDefault,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ProjectStatusesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ProjectStatusesTable, ProjectStatus> {
  $$ProjectStatusesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.projectStatuses.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProjectStatusesTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectStatusesTable> {
  $$ProjectStatusesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusKey => $composableBuilder(
    column: $table.statusKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorToken => $composableBuilder(
    column: $table.colorToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDone => $composableBuilder(
    column: $table.isDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectStatusesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectStatusesTable> {
  $$ProjectStatusesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusKey => $composableBuilder(
    column: $table.statusKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorToken => $composableBuilder(
    column: $table.colorToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDone => $composableBuilder(
    column: $table.isDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectStatusesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectStatusesTable> {
  $$ProjectStatusesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get statusKey =>
      $composableBuilder(column: $table.statusKey, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorToken => $composableBuilder(
    column: $table.colorToken,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get isDone =>
      $composableBuilder(column: $table.isDone, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectStatusesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectStatusesTable,
          ProjectStatus,
          $$ProjectStatusesTableFilterComposer,
          $$ProjectStatusesTableOrderingComposer,
          $$ProjectStatusesTableAnnotationComposer,
          $$ProjectStatusesTableCreateCompanionBuilder,
          $$ProjectStatusesTableUpdateCompanionBuilder,
          (ProjectStatus, $$ProjectStatusesTableReferences),
          ProjectStatus,
          PrefetchHooks Function({bool projectId})
        > {
  $$ProjectStatusesTableTableManager(
    _$AppDatabase db,
    $ProjectStatusesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectStatusesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectStatusesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectStatusesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> statusKey = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> colorToken = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> isDone = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectStatusesCompanion(
                id: id,
                projectId: projectId,
                statusKey: statusKey,
                name: name,
                colorToken: colorToken,
                position: position,
                isDone: isDone,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required String statusKey,
                required String name,
                Value<String> colorToken = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> isDone = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectStatusesCompanion.insert(
                id: id,
                projectId: projectId,
                statusKey: statusKey,
                name: name,
                colorToken: colorToken,
                position: position,
                isDone: isDone,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectStatusesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable:
                                    $$ProjectStatusesTableReferences
                                        ._projectIdTable(db),
                                referencedColumn:
                                    $$ProjectStatusesTableReferences
                                        ._projectIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProjectStatusesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectStatusesTable,
      ProjectStatus,
      $$ProjectStatusesTableFilterComposer,
      $$ProjectStatusesTableOrderingComposer,
      $$ProjectStatusesTableAnnotationComposer,
      $$ProjectStatusesTableCreateCompanionBuilder,
      $$ProjectStatusesTableUpdateCompanionBuilder,
      (ProjectStatus, $$ProjectStatusesTableReferences),
      ProjectStatus,
      PrefetchHooks Function({bool projectId})
    >;
typedef $$ProjectMilestonesTableCreateCompanionBuilder =
    ProjectMilestonesCompanion Function({
      required String id,
      required String projectId,
      required String title,
      Value<String?> description,
      Value<DateTime?> targetDate,
      Value<DateTime?> completedAt,
      Value<int> position,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectMilestonesTableUpdateCompanionBuilder =
    ProjectMilestonesCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String> title,
      Value<String?> description,
      Value<DateTime?> targetDate,
      Value<DateTime?> completedAt,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ProjectMilestonesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ProjectMilestonesTable,
          ProjectMilestone
        > {
  $$ProjectMilestonesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.projectMilestones.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProjectMilestonesTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectMilestonesTable> {
  $$ProjectMilestonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectMilestonesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectMilestonesTable> {
  $$ProjectMilestonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectMilestonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectMilestonesTable> {
  $$ProjectMilestonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectMilestonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectMilestonesTable,
          ProjectMilestone,
          $$ProjectMilestonesTableFilterComposer,
          $$ProjectMilestonesTableOrderingComposer,
          $$ProjectMilestonesTableAnnotationComposer,
          $$ProjectMilestonesTableCreateCompanionBuilder,
          $$ProjectMilestonesTableUpdateCompanionBuilder,
          (ProjectMilestone, $$ProjectMilestonesTableReferences),
          ProjectMilestone,
          PrefetchHooks Function({bool projectId})
        > {
  $$ProjectMilestonesTableTableManager(
    _$AppDatabase db,
    $ProjectMilestonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectMilestonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectMilestonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectMilestonesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime?> targetDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectMilestonesCompanion(
                id: id,
                projectId: projectId,
                title: title,
                description: description,
                targetDate: targetDate,
                completedAt: completedAt,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<DateTime?> targetDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> position = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectMilestonesCompanion.insert(
                id: id,
                projectId: projectId,
                title: title,
                description: description,
                targetDate: targetDate,
                completedAt: completedAt,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectMilestonesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable:
                                    $$ProjectMilestonesTableReferences
                                        ._projectIdTable(db),
                                referencedColumn:
                                    $$ProjectMilestonesTableReferences
                                        ._projectIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProjectMilestonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectMilestonesTable,
      ProjectMilestone,
      $$ProjectMilestonesTableFilterComposer,
      $$ProjectMilestonesTableOrderingComposer,
      $$ProjectMilestonesTableAnnotationComposer,
      $$ProjectMilestonesTableCreateCompanionBuilder,
      $$ProjectMilestonesTableUpdateCompanionBuilder,
      (ProjectMilestone, $$ProjectMilestonesTableReferences),
      ProjectMilestone,
      PrefetchHooks Function({bool projectId})
    >;
typedef $$TaskDependenciesTableCreateCompanionBuilder =
    TaskDependenciesCompanion Function({
      required String id,
      required String predecessorTaskId,
      required String successorTaskId,
      Value<String> dependencyType,
      Value<int> lagMinutes,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TaskDependenciesTableUpdateCompanionBuilder =
    TaskDependenciesCompanion Function({
      Value<String> id,
      Value<String> predecessorTaskId,
      Value<String> successorTaskId,
      Value<String> dependencyType,
      Value<int> lagMinutes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TaskDependenciesTableReferences
    extends
        BaseReferences<_$AppDatabase, $TaskDependenciesTable, TaskDependency> {
  $$TaskDependenciesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TasksTable _predecessorTaskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias(
        $_aliasNameGenerator(
          db.taskDependencies.predecessorTaskId,
          db.tasks.id,
        ),
      );

  $$TasksTableProcessedTableManager get predecessorTaskId {
    final $_column = $_itemColumn<String>('predecessor_task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_predecessorTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _successorTaskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias(
        $_aliasNameGenerator(db.taskDependencies.successorTaskId, db.tasks.id),
      );

  $$TasksTableProcessedTableManager get successorTaskId {
    final $_column = $_itemColumn<String>('successor_task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_successorTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskDependenciesTableFilterComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dependencyType => $composableBuilder(
    column: $table.dependencyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lagMinutes => $composableBuilder(
    column: $table.lagMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get predecessorTaskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get successorTaskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.successorTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskDependenciesTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependencyType => $composableBuilder(
    column: $table.dependencyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lagMinutes => $composableBuilder(
    column: $table.lagMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get predecessorTaskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get successorTaskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.successorTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskDependenciesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dependencyType => $composableBuilder(
    column: $table.dependencyType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lagMinutes => $composableBuilder(
    column: $table.lagMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$TasksTableAnnotationComposer get predecessorTaskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get successorTaskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.successorTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskDependenciesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskDependenciesTable,
          TaskDependency,
          $$TaskDependenciesTableFilterComposer,
          $$TaskDependenciesTableOrderingComposer,
          $$TaskDependenciesTableAnnotationComposer,
          $$TaskDependenciesTableCreateCompanionBuilder,
          $$TaskDependenciesTableUpdateCompanionBuilder,
          (TaskDependency, $$TaskDependenciesTableReferences),
          TaskDependency,
          PrefetchHooks Function({bool predecessorTaskId, bool successorTaskId})
        > {
  $$TaskDependenciesTableTableManager(
    _$AppDatabase db,
    $TaskDependenciesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskDependenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskDependenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskDependenciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> predecessorTaskId = const Value.absent(),
                Value<String> successorTaskId = const Value.absent(),
                Value<String> dependencyType = const Value.absent(),
                Value<int> lagMinutes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskDependenciesCompanion(
                id: id,
                predecessorTaskId: predecessorTaskId,
                successorTaskId: successorTaskId,
                dependencyType: dependencyType,
                lagMinutes: lagMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String predecessorTaskId,
                required String successorTaskId,
                Value<String> dependencyType = const Value.absent(),
                Value<int> lagMinutes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TaskDependenciesCompanion.insert(
                id: id,
                predecessorTaskId: predecessorTaskId,
                successorTaskId: successorTaskId,
                dependencyType: dependencyType,
                lagMinutes: lagMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskDependenciesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({predecessorTaskId = false, successorTaskId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (predecessorTaskId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.predecessorTaskId,
                                    referencedTable:
                                        $$TaskDependenciesTableReferences
                                            ._predecessorTaskIdTable(db),
                                    referencedColumn:
                                        $$TaskDependenciesTableReferences
                                            ._predecessorTaskIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (successorTaskId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.successorTaskId,
                                    referencedTable:
                                        $$TaskDependenciesTableReferences
                                            ._successorTaskIdTable(db),
                                    referencedColumn:
                                        $$TaskDependenciesTableReferences
                                            ._successorTaskIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$TaskDependenciesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskDependenciesTable,
      TaskDependency,
      $$TaskDependenciesTableFilterComposer,
      $$TaskDependenciesTableOrderingComposer,
      $$TaskDependenciesTableAnnotationComposer,
      $$TaskDependenciesTableCreateCompanionBuilder,
      $$TaskDependenciesTableUpdateCompanionBuilder,
      (TaskDependency, $$TaskDependenciesTableReferences),
      TaskDependency,
      PrefetchHooks Function({bool predecessorTaskId, bool successorTaskId})
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      required String entityType,
      required String entityId,
      required String operation,
      required String payload,
      Value<String?> deviceId,
      required DateTime createdAt,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payload,
      Value<String?> deviceId,
      Value<DateTime> createdAt,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxData,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
          ),
          SyncOutboxData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                deviceId: deviceId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entityType,
                required String entityId,
                required String operation,
                required String payload,
                Value<String?> deviceId = const Value.absent(),
                required DateTime createdAt,
              }) => SyncOutboxCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                deviceId: deviceId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxData,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
      ),
      SyncOutboxData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$ProgressLogsTableTableManager get progressLogs =>
      $$ProgressLogsTableTableManager(_db, _db.progressLogs);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$DiaryEntriesTableTableManager get diaryEntries =>
      $$DiaryEntriesTableTableManager(_db, _db.diaryEntries);
  $$HabitsTableTableManager get habits =>
      $$HabitsTableTableManager(_db, _db.habits);
  $$HabitLogsTableTableManager get habitLogs =>
      $$HabitLogsTableTableManager(_db, _db.habitLogs);
  $$FocusSessionsTableTableManager get focusSessions =>
      $$FocusSessionsTableTableManager(_db, _db.focusSessions);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$TodoItemsTableTableManager get todoItems =>
      $$TodoItemsTableTableManager(_db, _db.todoItems);
  $$TodoCompletionsTableTableManager get todoCompletions =>
      $$TodoCompletionsTableTableManager(_db, _db.todoCompletions);
  $$DailyPlansTableTableManager get dailyPlans =>
      $$DailyPlansTableTableManager(_db, _db.dailyPlans);
  $$DailyPlanItemsTableTableManager get dailyPlanItems =>
      $$DailyPlanItemsTableTableManager(_db, _db.dailyPlanItems);
  $$TaskScheduleBlocksTableTableManager get taskScheduleBlocks =>
      $$TaskScheduleBlocksTableTableManager(_db, _db.taskScheduleBlocks);
  $$SavedFiltersTableTableManager get savedFilters =>
      $$SavedFiltersTableTableManager(_db, _db.savedFilters);
  $$PlanningPreferencesTableTableManager get planningPreferences =>
      $$PlanningPreferencesTableTableManager(_db, _db.planningPreferences);
  $$WorkingHoursTableTableManager get workingHours =>
      $$WorkingHoursTableTableManager(_db, _db.workingHours);
  $$WorkingBreaksTableTableManager get workingBreaks =>
      $$WorkingBreaksTableTableManager(_db, _db.workingBreaks);
  $$ProjectStatusesTableTableManager get projectStatuses =>
      $$ProjectStatusesTableTableManager(_db, _db.projectStatuses);
  $$ProjectMilestonesTableTableManager get projectMilestones =>
      $$ProjectMilestonesTableTableManager(_db, _db.projectMilestones);
  $$TaskDependenciesTableTableManager get taskDependencies =>
      $$TaskDependenciesTableTableManager(_db, _db.taskDependencies);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
}
