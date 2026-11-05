import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/saved_filter.dart';
import '../../../core/providers/database_provider.dart';
import '../data/saved_filter_repository.dart';

/// Creates one validated condition through a small builder, so users never
/// type raw SQL or hand-written JSON.
class SavedViewDialog extends ConsumerStatefulWidget {
  const SavedViewDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SavedViewDialog(),
    );
  }

  @override
  ConsumerState<SavedViewDialog> createState() => _SavedViewDialogState();
}

class _SavedViewDialogState extends ConsumerState<SavedViewDialog> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  String _scope = 'tasks';
  late String _field;
  late String _operator;
  bool _booleanValue = false;
  bool _pinned = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final fields = SavedFilterDefinition.fieldOperators(_scope).keys.toList();
    _field = fields.first;
    _operator = SavedFilterDefinition.fieldOperators(_scope)[_field]!.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  void _changeScope(String scope) {
    final fields = SavedFilterDefinition.fieldOperators(scope).keys.toList();
    setState(() {
      _scope = scope;
      _field = fields.first;
      _operator = SavedFilterDefinition.fieldOperators(scope)[_field]!.first;
      _value.clear();
    });
  }

  void _changeField(String field) {
    final operators = SavedFilterDefinition.fieldOperators(
      _scope,
    )[field]!.toList();
    setState(() {
      _field = field;
      _operator = operators.first;
      _value.clear();
    });
  }

  Object? _parsedValue() {
    if (_operator == 'isNull' || _operator == 'isNotNull') return null;
    switch (SavedFilterDefinition.valueType(_scope, _field)) {
      case FilterValueType.boolean:
        return _booleanValue;
      case FilterValueType.integer:
        final parsed = int.tryParse(_value.text.trim());
        if (parsed == null) throw const SavedFilterException('Enter a number.');
        return parsed;
      case FilterValueType.text:
        return _value.text;
      case FilterValueType.date:
        final text = _value.text.trim();
        if (text.isEmpty) {
          throw const SavedFilterException('Enter a date or relative range.');
        }
        return text;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final condition = <String, Object?>{
        'field': _field,
        'op': _operator,
        if (_operator != 'isNull' && _operator != 'isNotNull')
          'value': _parsedValue(),
      };
      final filterJson =
          '{"version":1,"scope":"$_scope","all":[${_jsonCondition(condition)}]}';
      await ref
          .read(savedFilterRepositoryProvider)
          .create(
            scope: _scope,
            name: _name.text,
            filterJson: filterJson,
            isPinned: _pinned,
          );
      if (mounted) Navigator.of(context).pop();
    } on SavedFilterException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  static String _jsonCondition(Map<String, Object?> condition) {
    final field = condition['field'] as String;
    final op = condition['op'] as String;
    if (op == 'isNull' || op == 'isNotNull') {
      return '{"field":"$field","op":"$op"}';
    }
    final value = condition['value'];
    final encoded = switch (value) {
      String() => '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"',
      bool() => value.toString(),
      int() => value.toString(),
      _ => 'null',
    };
    return '{"field":"$field","op":"$op","value":$encoded}';
  }

  @override
  Widget build(BuildContext context) {
    final fields = SavedFilterDefinition.fieldOperators(_scope);
    final operators = fields[_field] ?? const <String>{};
    final type = SavedFilterDefinition.valueType(_scope, _field);
    return AlertDialog(
      title: const Text('New saved view'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'View name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _scope,
                decoration: const InputDecoration(labelText: 'Applies to'),
                items: [
                  for (final scope in SavedFilterDefinition.scopes)
                    DropdownMenuItem(value: scope, child: Text(scope)),
                ],
                onChanged: (scope) {
                  if (scope != null) _changeScope(scope);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _field,
                decoration: const InputDecoration(labelText: 'Field'),
                items: [
                  for (final field in fields.keys)
                    DropdownMenuItem(value: field, child: Text(field)),
                ],
                onChanged: (field) {
                  if (field != null) _changeField(field);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _operator,
                decoration: const InputDecoration(labelText: 'Condition'),
                items: [
                  for (final operator in operators)
                    if (operator != 'in')
                      DropdownMenuItem(
                        value: operator,
                        child: Text(_operatorLabel(operator)),
                      ),
                ],
                onChanged: (operator) {
                  if (operator != null) {
                    setState(() => _operator = operator);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_operator != 'isNull' && _operator != 'isNotNull')
                if (type == FilterValueType.boolean)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_booleanValue ? 'True' : 'False'),
                    value: _booleanValue,
                    onChanged: (value) => setState(() => _booleanValue = value),
                  )
                else
                  TextField(
                    controller: _value,
                    decoration: InputDecoration(
                      labelText: type == FilterValueType.date
                          ? 'Date (YYYY-MM-DD or today/thisWeek/...)'
                          : 'Value',
                    ),
                  ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pin to sidebar'),
                value: _pinned,
                onChanged: (value) => setState(() => _pinned = value ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save view'),
        ),
      ],
    );
  }

  static String _operatorLabel(String operator) => switch (operator) {
    'eq' => 'equals',
    'neq' => 'does not equal',
    'in' => 'is one of',
    'isNull' => 'is empty',
    'isNotNull' => 'is not empty',
    'lt' => '<',
    'lte' => '<=',
    'gt' => '>',
    'gte' => '>=',
    'contains' => 'contains',
    'startsWith' => 'starts with',
    'before' => 'before',
    'after' => 'on or after',
    'within' => 'within',
    _ => operator,
  };
}

/// Runs a saved view through the parameterised compiler and shows its rows.
class SavedViewResultsDialog extends ConsumerStatefulWidget {
  const SavedViewResultsDialog({super.key, required this.filter});

  final SavedFilter filter;

  static Future<void> show(BuildContext context, SavedFilter filter) {
    return showDialog<void>(
      context: context,
      builder: (_) => SavedViewResultsDialog(filter: filter),
    );
  }

  @override
  ConsumerState<SavedViewResultsDialog> createState() =>
      _SavedViewResultsDialogState();
}

class _SavedViewResultsDialogState
    extends ConsumerState<SavedViewResultsDialog> {
  late Future<List<({String id, String title, String? subtitle})>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<({String id, String title, String? subtitle})>> _load() async {
    final filter = widget.filter;
    final compiled = SavedFilterDefinition.parse(
      scope: filter.entityScope,
      filterJson: filter.filterJson,
      sortJson: filter.sortJson,
      definitionVersion: filter.definitionVersion,
    ).compile();
    final (table, titleColumn, subtitleColumn) = switch (filter.entityScope) {
      'projects' => ('projects', 'name', 'description'),
      'events' => ('events', 'title', 'category'),
      'habits' => ('habits', 'name', 'icon'),
      _ => ('todo_items', 'title', 'notes'),
    };
    final where = compiled.whereSql.isEmpty
        ? ''
        : ' WHERE ${compiled.whereSql}';
    final rows = await ref
        .read(databaseProvider)
        .customSelect(
          'SELECT id, $titleColumn AS title, $subtitleColumn AS subtitle '
          'FROM $table$where${compiled.orderBySql} LIMIT 200',
          variables: compiled.variables.cast<Variable>(),
        )
        .get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          subtitle: row.readNullable<String>('subtitle'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.filter.name),
      content: SizedBox(
        width: 480,
        height: 420,
        child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'This saved view could not be loaded: ${snapshot.error}',
              );
            }
            final rows = snapshot.data;
            if (rows == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rows.isEmpty) {
              return const Center(child: Text('No matching items.'));
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                return ListTile(
                  title: Text(row.title),
                  subtitle: row.subtitle == null || row.subtitle!.isEmpty
                      ? null
                      : Text(row.subtitle!),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
