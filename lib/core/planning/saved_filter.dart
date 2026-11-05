import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../utils/app_clock.dart';
import '../utils/day_math.dart';

/// A saved view definition that has been parsed and checked against the
/// allowlisted filter language.
///
/// Nothing in a saved view is ever executed as SQL text. The parser only
/// accepts known field names and operators, and [compile] turns the resulting
/// tree into a fixed WHERE template with every user value bound as a
/// parameter. Unknown fields, malformed values and unknown definition versions
/// raise [SavedFilterException] so the UI can keep the stored definition and
/// show an actionable error instead of dropping it.
class SavedFilterDefinition {
  const SavedFilterDefinition({
    required this.scope,
    required this.root,
    this.sort = const [],
    this.version = supportedVersion,
  });

  static const supportedVersion = 1;
  static const maxDepth = 4;
  static const maxConditions = 50;
  static const maxStringLength = 1000;
  static const maxListLength = 100;

  static const scopes = {'tasks', 'projects', 'events', 'habits'};

  /// Fields and their allowed operators for the editor. Keys are stable JSON
  /// names; values are the operator tokens the parser accepts.
  static Map<String, Set<String>> fieldOperators(String scope) => {
    for (final entry in _fieldSpecs(scope).entries)
      entry.key: entry.value.operators,
  };

  static FilterValueType valueType(String scope, String field) =>
      _fieldSpecs(scope)[field]!.type;

  final int version;
  final String scope;
  final FilterNode root;
  final List<SortDescriptor> sort;

  /// Parses the stored JSON for [scope].
  ///
  /// [definitionVersion] is the row's own compatibility marker; a row written
  /// by a newer parser is rejected without touching the stored text.
  factory SavedFilterDefinition.parse({
    required String scope,
    required String filterJson,
    String sortJson = '[]',
    int definitionVersion = supportedVersion,
  }) {
    if (!scopes.contains(scope)) {
      throw SavedFilterException('Unknown saved-view scope "$scope".');
    }
    if (definitionVersion > supportedVersion || definitionVersion < 1) {
      throw SavedFilterException(
        'Saved view uses definition version $definitionVersion; this build '
        'supports 1.',
      );
    }

    final decoded = _decodeObject(filterJson, 'filter');
    final version = decoded['version'];
    if (version is! int || version < 1) {
      throw const SavedFilterException(
        'Saved view filter is missing a valid version.',
      );
    }
    if (version > supportedVersion) {
      throw SavedFilterException(
        'Saved view needs filter version $version; this build supports '
        '$supportedVersion.',
      );
    }
    final encodedScope = decoded['scope'];
    if (encodedScope != null && encodedScope != scope) {
      throw SavedFilterException(
        'Saved view scope "$encodedScope" does not match "$scope".',
      );
    }

    final counter = _Countdown(maxConditions);
    final root = _parseNode(decoded, scope, depth: 1, counter: counter);

    final sortDecoded = sortJson.trim().isEmpty
        ? const []
        : jsonDecode(sortJson);
    if (sortDecoded is! List) {
      throw const SavedFilterException('Saved view sort must be a JSON list.');
    }
    if (sortDecoded.length > 10) {
      throw const SavedFilterException('Saved view has too many sort fields.');
    }
    final sort = <SortDescriptor>[];
    for (final entry in sortDecoded) {
      if (entry is! Map) {
        throw const SavedFilterException(
          'Each saved-view sort entry must be an object.',
        );
      }
      final map = Map<String, dynamic>.from(entry);
      final field = map['field'];
      if (field is! String || !_fieldSpecs(scope).containsKey(field)) {
        throw SavedFilterException('Unknown sort field "$field".');
      }
      final descending = map['descending'];
      if (descending != null && descending is! bool) {
        throw const SavedFilterException('Sort "descending" must be a bool.');
      }
      sort.add(SortDescriptor(field: field, descending: descending == true));
    }

    return SavedFilterDefinition(
      scope: scope,
      root: root,
      sort: sort,
      version: version,
    );
  }

  /// Returns the canonical JSON for this definition. Re-saving an already
  /// parsed view is therefore stable and never grows the stored document.
  String toFilterJson() =>
      jsonEncode({'version': version, 'scope': scope, ...root.toJson()});

  String toSortJson() => jsonEncode([
    for (final term in sort)
      {'field': term.field, 'descending': term.descending},
  ]);

  /// Compiles the definition to a parameterised WHERE template.
  ///
  /// The returned SQL only contains `?` placeholders and allowlisted column
  /// names from [_fieldSpecs]. [now] is injectable so relative tokens such as
  /// `thisWeek` can be tested deterministically.
  CompiledFilter compile({DateTime? now}) {
    final compiler = _Compiler(
      scope: scope,
      now: DayMath.dateOnly(now ?? AppClock.now()),
    );
    final where = compiler.compile(root);
    final orderBy = sort.isEmpty
        ? ''
        : ' ORDER BY ${sort.map((s) {
            final column = _fieldSpecs(scope)[s.field]!.column;
            return s.descending ? '$column DESC' : '$column ASC';
          }).join(', ')}';
    return CompiledFilter(
      whereSql: where,
      variables: compiler.variables,
      orderBySql: orderBy,
    );
  }

  static Map<String, dynamic> _decodeObject(String source, String label) {
    if (source.length > 100 * 1024) {
      throw SavedFilterException('Saved view $label is too large.');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw SavedFilterException('Saved view $label must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static FilterNode _parseNode(
    Map<String, dynamic> node,
    String scope, {
    required int depth,
    required _Countdown counter,
  }) {
    if (depth > maxDepth) {
      throw const SavedFilterException('Saved view is nested too deeply.');
    }
    final hasAll = node.containsKey('all');
    final hasAny = node.containsKey('any');
    if (hasAll && hasAny) {
      throw const SavedFilterException(
        'A saved-view group cannot contain both "all" and "any".',
      );
    }

    if (hasAll || hasAny) {
      final key = hasAll ? 'all' : 'any';
      final raw = node[key];
      if (raw is! List || raw.isEmpty) {
        throw SavedFilterException(
          'Saved-view "$key" must be a non-empty list.',
        );
      }
      final children = <FilterNode>[];
      for (final child in raw) {
        counter.take();
        if (child is! Map) {
          throw const SavedFilterException(
            'Saved-view clauses must be objects.',
          );
        }
        children.add(
          _parseNode(
            Map<String, dynamic>.from(child),
            scope,
            depth: depth + 1,
            counter: counter,
          ),
        );
      }
      return FilterGroup(any: hasAny, children: children);
    }

    final field = node['field'];
    final op = node['op'];
    if (field is! String || op is! String) {
      throw const SavedFilterException(
        'Saved-view clause needs a field and an operator.',
      );
    }
    final spec = _fieldSpecs(scope)[field];
    if (spec == null) {
      throw SavedFilterException('Unknown filter field "$field".');
    }
    if (!spec.operators.contains(op)) {
      throw SavedFilterException(
        'Operator "$op" is not allowed for field "$field".',
      );
    }

    if (op == 'isNull' || op == 'isNotNull') {
      return FilterCondition(field: field, operator: op);
    }

    if (!node.containsKey('value')) {
      throw SavedFilterException('Filter "$field $op" needs a value.');
    }
    final value = _validateValue(field, spec, op, node['value']);
    return FilterCondition(field: field, operator: op, value: value);
  }

  static Object? _validateValue(
    String field,
    _FieldSpec spec,
    String op,
    Object? value,
  ) {
    switch (op) {
      case 'in':
        if (value is! List || value.isEmpty) {
          throw SavedFilterException(
            'Filter "$field in" needs a non-empty list.',
          );
        }
        if (value.length > maxListLength) {
          throw SavedFilterException('Filter "$field in" has too many values.');
        }
        final validated = <Object>[];
        for (final item in value) {
          if (spec.type == FilterValueType.date &&
              item is String &&
              RelativeDateRanges.tokens.contains(item)) {
            throw SavedFilterException(
              'Filter "$field in" needs concrete dates, not "$item".',
            );
          }
          validated.add(_validateScalar(field, spec, item));
        }
        return validated;
      case 'within':
        if (spec.type != FilterValueType.date || value is! String) {
          throw SavedFilterException(
            'Filter "$field within" needs a relative date token.',
          );
        }
        if (!RelativeDateRanges.tokens.contains(value)) {
          throw SavedFilterException('Unknown relative date "$value".');
        }
        return value;
      default:
        return _validateScalar(field, spec, value);
    }
  }

  static Object _validateScalar(String field, _FieldSpec spec, Object? value) {
    switch (spec.type) {
      case FilterValueType.boolean:
        if (value is! bool) {
          throw SavedFilterException('Filter "$field" needs a boolean.');
        }
        return value;
      case FilterValueType.integer:
        if (value is! num || value is double && value != value.truncate()) {
          throw SavedFilterException('Filter "$field" needs an integer.');
        }
        return value.toInt();
      case FilterValueType.text:
        if (value is! String) {
          throw SavedFilterException('Filter "$field" needs text.');
        }
        if (value.length > maxStringLength) {
          throw SavedFilterException('Filter "$field" value is too long.');
        }
        return value;
      case FilterValueType.date:
        if (value is! String || value.length > maxStringLength) {
          throw SavedFilterException('Filter "$field" needs a date.');
        }
        if (!RelativeDateRanges.tokens.contains(value) &&
            DateTime.tryParse(value) == null) {
          throw SavedFilterException('Filter "$field" has an invalid date.');
        }
        return value;
    }
  }

  /// Built-in smart views. They reuse the same AST so the UI has one code
  /// path; a user can copy one into a saved view without inheriting a frozen
  /// timestamp.
  static SavedFilterDefinition builtIn(String id) {
    final json = _builtInFilters[id];
    if (json == null) {
      throw SavedFilterException('Unknown built-in view "$id".');
    }
    return SavedFilterDefinition.parse(scope: 'tasks', filterJson: json);
  }

  static const _builtInFilters = <String, String>{
    'today':
        '{"version":1,"scope":"tasks","any":[{"all":[{"field":"completed","op":"eq","value":false},{"field":"dueDate","op":"within","value":"today"}]},{"all":[{"field":"completed","op":"eq","value":false},{"field":"startDate","op":"within","value":"today"}]}]}',
    'overdue':
        '{"version":1,"scope":"tasks","all":[{"field":"completed","op":"eq","value":false},{"field":"dueDate","op":"before","value":"today"}]}',
    'upcoming':
        '{"version":1,"scope":"tasks","all":[{"field":"completed","op":"eq","value":false},{"field":"dueDate","op":"within","value":"upcoming"}]}',
    'highPriority':
        '{"version":1,"scope":"tasks","all":[{"field":"completed","op":"eq","value":false},{"field":"priority","op":"gte","value":2}]}',
    'completed':
        '{"version":1,"scope":"tasks","all":[{"field":"completed","op":"eq","value":true}]}',
    'unscheduled':
        '{"version":1,"scope":"tasks","all":[{"field":"completed","op":"eq","value":false},{"field":"startDate","op":"isNull"},{"field":"dueDate","op":"isNull"}]}',
  };
}

/// Thrown for every malformed or unsupported saved view. The caller keeps the
/// original stored definition so it can be fixed by a newer build.
class SavedFilterException implements Exception {
  const SavedFilterException(this.message);
  final String message;

  @override
  String toString() => message;
}

sealed class FilterNode {
  const FilterNode();
  Map<String, dynamic> toJson();
}

class FilterGroup extends FilterNode {
  const FilterGroup({required this.any, required this.children});
  final bool any;
  final List<FilterNode> children;

  @override
  Map<String, dynamic> toJson() => {
    any ? 'any' : 'all': [for (final child in children) child.toJson()],
  };
}

class FilterCondition extends FilterNode {
  const FilterCondition({
    required this.field,
    required this.operator,
    this.value,
  });

  final String field;
  final String operator;
  final Object? value;

  /// The relative-date token when the value is one, or null.
  String? get relativeDate =>
      operator == 'within' && value is String ? value as String : null;

  @override
  Map<String, dynamic> toJson() => {
    'field': field,
    'op': operator,
    if (operator != 'isNull' && operator != 'isNotNull') 'value': value,
  };
}

class SortDescriptor {
  const SortDescriptor({required this.field, this.descending = false});
  final String field;
  final bool descending;
}

/// A parameterised WHERE template. [whereSql] is empty when the definition
/// carries no conditions, in which case callers must not add a WHERE keyword.
class CompiledFilter {
  const CompiledFilter({
    required this.whereSql,
    required this.variables,
    required this.orderBySql,
  });

  final String whereSql;
  final List<Variable<Object>> variables;
  final String orderBySql;
}

class _Countdown {
  _Countdown(this.remaining);
  int remaining;

  void take() {
    if (remaining-- <= 0) {
      throw const SavedFilterException('Saved view has too many clauses.');
    }
  }
}

class _Compiler {
  _Compiler({required this.scope, required this.now});

  final String scope;
  final DateTime now;
  final List<Variable<Object>> variables = [];

  String compile(FilterNode node) {
    switch (node) {
      case FilterGroup():
        if (node.children.isEmpty) return '1';
        final joiner = node.any ? ' OR ' : ' AND ';
        return node.children.map((child) => '(${compile(child)})').join(joiner);
      case FilterCondition():
        return _condition(node);
    }
  }

  String _condition(FilterCondition condition) {
    final spec = _fieldSpecs(scope)[condition.field]!;
    final column = spec.column;
    switch (condition.operator) {
      case 'isNull':
        return '$column IS NULL';
      case 'isNotNull':
        return '$column IS NOT NULL';
      case 'contains':
        variables.add(
          Variable.withString('%${_escapeLike(condition.value as String)}%'),
        );
        return "$column LIKE ? ESCAPE '\\'";
      case 'startsWith':
        variables.add(
          Variable.withString('${_escapeLike(condition.value as String)}%'),
        );
        return "$column LIKE ? ESCAPE '\\'";
      case 'in':
        final values = condition.value as List;
        final placeholders = List.filled(values.length, '?').join(', ');
        for (final value in values) {
          variables.add(_variable(spec, value));
        }
        return '$column IN ($placeholders)';
      case 'within':
        final range = RelativeDateRanges.resolve(
          condition.value as String,
          now,
        );
        variables
          ..add(Variable.withDateTime(range.start))
          ..add(Variable.withDateTime(range.end));
        return '$column >= ? AND $column < ?';
      case 'before':
        return '$column < ${_addValue(spec, condition.value!)}';
      case 'after':
        return '$column >= ${_addValue(spec, condition.value!)}';
      case 'gte':
        return '$column >= ${_addValue(spec, condition.value!)}';
      case 'gt':
        return '$column > ${_addValue(spec, condition.value!)}';
      case 'lte':
        return '$column <= ${_addValue(spec, condition.value!)}';
      case 'lt':
        return '$column < ${_addValue(spec, condition.value!)}';
      case 'neq':
        return '$column != ${_addValue(spec, condition.value!)}';
      case 'eq':
        // A date without a time means the whole local day.
        if (spec.type == FilterValueType.date &&
            condition.value is String &&
            _isDayKey(condition.value as String)) {
          final day = DateTime.parse(condition.value as String);
          variables
            ..add(Variable.withDateTime(day))
            ..add(Variable.withDateTime(DayMath.addDays(day, 1)));
          return '$column >= ? AND $column < ?';
        }
        return '$column = ${_addValue(spec, condition.value!)}';
      default:
        throw SavedFilterException(
          'Unsupported operator "${condition.operator}".',
        );
    }
  }

  String _addValue(_FieldSpec spec, Object value) {
    if (spec.type == FilterValueType.date && value is String) {
      final token = RelativeDateRanges.tokens.contains(value) ? value : null;
      if (token != null) {
        final range = RelativeDateRanges.resolve(token, now);
        variables.add(Variable.withDateTime(range.start));
        return '?';
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw SavedFilterException('Invalid date "$value".');
      }
      variables.add(Variable.withDateTime(parsed));
      return '?';
    }
    variables.add(_variable(spec, value));
    return '?';
  }

  static Variable<Object> _variable(_FieldSpec spec, Object value) {
    return switch (spec.type) {
      FilterValueType.boolean => Variable.withBool(value as bool),
      FilterValueType.integer => Variable.withInt(value as int),
      FilterValueType.text => Variable.withString(value as String),
      FilterValueType.date => Variable.withDateTime(
        DateTime.parse(value as String),
      ),
    };
  }

  static bool _isDayKey(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);

  /// `%`, `_` and the escape character itself must be literals inside a
  /// user-supplied search term.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

enum FilterValueType { boolean, integer, text, date }

class _FieldSpec {
  const _FieldSpec(this.column, this.type);

  final String column;
  final FilterValueType type;

  Set<String> get operators => switch (type) {
    FilterValueType.boolean => const {'eq', 'neq', 'isNull', 'isNotNull'},
    FilterValueType.integer => const {
      'eq',
      'neq',
      'in',
      'lt',
      'lte',
      'gt',
      'gte',
      'isNull',
      'isNotNull',
    },
    FilterValueType.text => const {
      'eq',
      'neq',
      'in',
      'contains',
      'startsWith',
      'isNull',
      'isNotNull',
    },
    FilterValueType.date => const {
      'eq',
      'neq',
      'lt',
      'lte',
      'gt',
      'gte',
      'before',
      'after',
      'within',
      'isNull',
      'isNotNull',
    },
  };
}

const _taskFields = <String, _FieldSpec>{
  'id': _FieldSpec('id', FilterValueType.text),
  'title': _FieldSpec('title', FilterValueType.text),
  'notes': _FieldSpec('notes', FilterValueType.text),
  'completed': _FieldSpec('completed', FilterValueType.boolean),
  'createdAt': _FieldSpec('created_at', FilterValueType.date),
  'startDate': _FieldSpec('start_date', FilterValueType.date),
  'dueDate': _FieldSpec('due_date', FilterValueType.date),
  'priority': _FieldSpec('priority', FilterValueType.integer),
  'tags': _FieldSpec('tags', FilterValueType.text),
  'recurrenceRule': _FieldSpec('recurrence_rule', FilterValueType.text),
  'parentId': _FieldSpec('parent_id', FilterValueType.text),
  'projectId': _FieldSpec('project_id', FilterValueType.text),
  'reminderAt': _FieldSpec('reminder_at', FilterValueType.date),
  'estimatedMinutes': _FieldSpec('estimated_minutes', FilterValueType.integer),
};

const _projectFields = <String, _FieldSpec>{
  'id': _FieldSpec('id', FilterValueType.text),
  'name': _FieldSpec('name', FilterValueType.text),
  'description': _FieldSpec('description', FilterValueType.text),
  'createdAt': _FieldSpec('created_at', FilterValueType.date),
  'targetDate': _FieldSpec('target_date', FilterValueType.date),
  'targetProgress': _FieldSpec('target_progress', FilterValueType.integer),
};

const _eventFields = <String, _FieldSpec>{
  'id': _FieldSpec('id', FilterValueType.text),
  'title': _FieldSpec('title', FilterValueType.text),
  'description': _FieldSpec('description', FilterValueType.text),
  'startTime': _FieldSpec('start_time', FilterValueType.date),
  'endTime': _FieldSpec('end_time', FilterValueType.date),
  'category': _FieldSpec('category', FilterValueType.text),
  'hasReminder': _FieldSpec('has_reminder', FilterValueType.boolean),
  'reminderMinutes': _FieldSpec('reminder_minutes', FilterValueType.integer),
  'allDay': _FieldSpec('all_day', FilterValueType.boolean),
  'recurrenceRule': _FieldSpec('recurrence_rule', FilterValueType.text),
};

const _habitFields = <String, _FieldSpec>{
  'id': _FieldSpec('id', FilterValueType.text),
  'name': _FieldSpec('name', FilterValueType.text),
  'icon': _FieldSpec('icon', FilterValueType.text),
  'createdAt': _FieldSpec('created_at', FilterValueType.date),
  'targetPerWeek': _FieldSpec('target_per_week', FilterValueType.integer),
};

Map<String, _FieldSpec> _fieldSpecs(String scope) => switch (scope) {
  'tasks' => _taskFields,
  'projects' => _projectFields,
  'events' => _eventFields,
  'habits' => _habitFields,
  _ => throw SavedFilterException('Unknown saved-view scope "$scope".'),
};

/// Named date ranges are resolved at compile time from the current local day,
/// so saving `thisWeek` never freezes a timestamp into the database.
abstract final class RelativeDateRanges {
  static const tokens = {
    'today',
    'tomorrow',
    'yesterday',
    'thisWeek',
    'nextWeek',
    'lastWeek',
    'thisMonth',
    'nextMonth',
    'upcoming',
    'overdue',
  };

  static ({DateTime start, DateTime end}) resolve(String token, DateTime now) {
    final today = DayMath.dateOnly(now);
    switch (token) {
      case 'today':
        return (start: today, end: DayMath.addDays(today, 1));
      case 'tomorrow':
        final start = DayMath.addDays(today, 1);
        return (start: start, end: DayMath.addDays(start, 1));
      case 'yesterday':
        final start = DayMath.addDays(today, -1);
        return (start: start, end: today);
      case 'thisWeek':
        final start = DayMath.startOfWeek(today);
        return (start: start, end: DayMath.addDays(start, 7));
      case 'nextWeek':
        final start = DayMath.addDays(DayMath.startOfWeek(today), 7);
        return (start: start, end: DayMath.addDays(start, 7));
      case 'lastWeek':
        final start = DayMath.addDays(DayMath.startOfWeek(today), -7);
        return (start: start, end: DayMath.addDays(start, 7));
      case 'thisMonth':
        final start = DateTime(today.year, today.month);
        return (start: start, end: DateTime(today.year, today.month + 1));
      case 'nextMonth':
        final start = DateTime(today.year, today.month + 1);
        return (start: start, end: DateTime(today.year, today.month + 2));
      case 'upcoming':
        return (start: today, end: DayMath.addDays(today, 7));
      case 'overdue':
        return (start: DateTime(1970), end: today);
      default:
        throw SavedFilterException('Unknown relative date "$token".');
    }
  }
}
