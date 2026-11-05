import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/planning/saved_filter.dart';

String definitionJson(
  String scope,
  Map<String, dynamic> root, {
  int version = 1,
  Map<String, dynamic>? extra,
}) {
  return jsonEncode({'version': version, 'scope': scope, ...root, ...?extra});
}

void main() {
  group('saved filter parsing', () {
    test('parses and canonically re-encodes a nested definition', () {
      final json = definitionJson('tasks', {
        'all': [
          {'field': 'completed', 'op': 'eq', 'value': false},
          {'field': 'priority', 'op': 'gte', 'value': 2},
        ],
      });

      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: json,
        sortJson: jsonEncode([
          {'field': 'dueDate', 'descending': false},
          {'field': 'priority', 'descending': true},
        ]),
      );

      expect(definition.scope, 'tasks');
      expect(definition.root, isA<FilterGroup>());
      final group = definition.root as FilterGroup;
      expect(group.any, isFalse);
      expect(group.children, hasLength(2));
      expect(definition.sort, hasLength(2));
      expect(definition.sort.last.descending, isTrue);

      final reencoded = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definition.toFilterJson(),
        sortJson: definition.toSortJson(),
      );
      expect(reencoded.toFilterJson(), definition.toFilterJson());
      expect(reencoded.toSortJson(), definition.toSortJson());
    });

    test('rejects unknown fields, operators and malformed values', () {
      final invalid = <String>[
        definitionJson('tasks', {
          'field': 'title; DROP TABLE todo_items',
          'op': 'eq',
          'value': 'x',
        }),
        definitionJson('tasks', {'field': 'title', 'op': 'exec', 'value': 'x'}),
        definitionJson('tasks', {'field': 'title', 'op': 'eq'}),
        definitionJson('tasks', {
          'field': 'title',
          'op': 'within',
          'value': 'today',
        }),
        definitionJson('tasks', {
          'field': 'dueDate',
          'op': 'within',
          'value': 'someday',
        }),
        definitionJson('tasks', {
          'field': 'dueDate',
          'op': 'eq',
          'value': 'not-a-date',
        }),
        definitionJson('tasks', {
          'field': 'completed',
          'op': 'eq',
          'value': 'false',
        }),
        definitionJson('tasks', {'all': []}),
        definitionJson('tasks', {
          'all': [
            {'field': 'completed', 'op': 'eq', 'value': false},
          ],
          'any': [
            {'field': 'completed', 'op': 'eq', 'value': true},
          ],
        }),
        definitionJson('tasks', {
          'field': 'title',
          'op': 'in',
          'value': <String>[],
        }),
      ];

      for (final json in invalid) {
        expect(
          () => SavedFilterDefinition.parse(scope: 'tasks', filterJson: json),
          throwsA(isA<SavedFilterException>()),
          reason: json,
        );
      }
    });

    test('rejects unsupported versions and mismatched scopes', () {
      expect(
        () => SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: definitionJson('tasks', {
            'field': 'completed',
            'op': 'eq',
            'value': false,
          }, version: 2),
        ),
        throwsA(isA<SavedFilterException>()),
      );
      expect(
        () => SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: definitionJson('projects', {
            'field': 'completed',
            'op': 'eq',
            'value': false,
          }),
        ),
        throwsA(isA<SavedFilterException>()),
      );
      expect(
        () => SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: definitionJson('tasks', {
            'field': 'completed',
            'op': 'eq',
            'value': false,
          }),
          definitionVersion: 2,
        ),
        throwsA(isA<SavedFilterException>()),
      );
      expect(
        () => SavedFilterDefinition.parse(
          scope: 'unknown',
          filterJson: definitionJson('tasks', {
            'field': 'completed',
            'op': 'eq',
            'value': false,
          }),
        ),
        throwsA(isA<SavedFilterException>()),
      );
    });

    test('rejects definitions that are too deep or too large', () {
      Map<String, dynamic> nested(int depth) {
        if (depth == 0) {
          return {'field': 'completed', 'op': 'eq', 'value': false};
        }
        return {
          'all': [nested(depth - 1)],
        };
      }

      final tooDeep = definitionJson('tasks', nested(5));
      expect(
        () => SavedFilterDefinition.parse(scope: 'tasks', filterJson: tooDeep),
        throwsA(isA<SavedFilterException>()),
      );

      final tooMany = definitionJson('tasks', {
        'all': [
          for (var i = 0; i < 51; i++)
            {'field': 'priority', 'op': 'gte', 'value': i},
        ],
      });
      expect(
        () => SavedFilterDefinition.parse(scope: 'tasks', filterJson: tooMany),
        throwsA(isA<SavedFilterException>()),
      );
    });

    test('rejects invalid sort descriptors', () {
      final json = definitionJson('tasks', {
        'field': 'completed',
        'op': 'eq',
        'value': false,
      });

      expect(
        () => SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: json,
          sortJson: jsonEncode([
            {'field': 'title; DROP TABLE', 'descending': false},
          ]),
        ),
        throwsA(isA<SavedFilterException>()),
      );
      expect(
        () => SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: json,
          sortJson: jsonEncode([
            {'field': 'title', 'descending': 'yes'},
          ]),
        ),
        throwsA(isA<SavedFilterException>()),
      );
      expect(
        () => SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: json,
          sortJson: jsonEncode([
            for (var i = 0; i < 11; i++)
              {'field': 'title', 'descending': false},
          ]),
        ),
        throwsA(isA<SavedFilterException>()),
      );
    });
  });

  group('saved filter compilation', () {
    test('binds every value as a parameter and uses no raw text', () {
      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definitionJson('tasks', {
          'any': [
            {
              'all': [
                {'field': 'completed', 'op': 'eq', 'value': false},
                {'field': 'priority', 'op': 'gte', 'value': 2},
              ],
            },
            {'field': 'title', 'op': 'contains', 'value': "O'Brien"},
          ],
        }),
      );

      final compiled = definition.compile(now: DateTime(2026, 5, 20));
      expect(compiled.whereSql, contains('completed = ?'));
      expect(compiled.whereSql, contains('priority >= ?'));
      expect(compiled.whereSql, contains('title LIKE ?'));
      expect(compiled.whereSql, contains(' OR '));
      expect(compiled.whereSql, contains(' AND '));
      expect(compiled.whereSql, isNot(contains("O'Brien")));
      expect(compiled.variables.map((v) => v.value), [false, 2, "%O'Brien%"]);
    });

    test('escapes LIKE metacharacters', () {
      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definitionJson('tasks', {
          'field': 'title',
          'op': 'contains',
          'value': r'50%_off\done',
        }),
      );

      final compiled = definition.compile();
      expect(compiled.variables.single.value, r'%50\%\_off\\done%');
      expect(compiled.whereSql, contains("ESCAPE '\\'"));
    });

    test('resolves relative date ranges at compile time', () {
      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definitionJson('tasks', {
          'field': 'dueDate',
          'op': 'within',
          'value': 'today',
        }),
      );

      final compiled = definition.compile(now: DateTime(2026, 5, 20, 14, 30));
      expect(compiled.variables.map((v) => v.value), [
        DateTime(2026, 5, 20),
        DateTime(2026, 5, 21),
      ]);
    });

    test('a date-only equality covers the whole local day', () {
      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definitionJson('tasks', {
          'field': 'dueDate',
          'op': 'eq',
          'value': '2026-05-20',
        }),
      );

      final compiled = definition.compile();
      expect(compiled.whereSql, 'due_date >= ? AND due_date < ?');
      expect(compiled.variables.map((v) => v.value), [
        DateTime(2026, 5, 20),
        DateTime(2026, 5, 21),
      ]);
    });

    test('compiles allowlisted sort columns', () {
      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definitionJson('tasks', {
          'field': 'completed',
          'op': 'eq',
          'value': false,
        }),
        sortJson: jsonEncode([
          {'field': 'dueDate', 'descending': false},
          {'field': 'priority', 'descending': true},
        ]),
      );

      expect(
        definition.compile().orderBySql,
        ' ORDER BY due_date ASC, priority DESC',
      );
    });

    test('built-in smart views compile without a frozen timestamp', () {
      for (final id in const [
        'today',
        'overdue',
        'upcoming',
        'highPriority',
        'completed',
        'unscheduled',
      ]) {
        final definition = SavedFilterDefinition.builtIn(id);
        final compiled = definition.compile(now: DateTime(2026, 5, 20));
        expect(compiled.whereSql, isNotEmpty);
        expect(compiled.whereSql, isNot(contains('2026-05-20')));
      }
    });
  });

  group('saved filter execution', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('a contains clause matches literal percent and underscore', () async {
      await db.addTodoItem('100% done', null);
      await db.addTodoItem('100 done', null);
      await db.addTodoItem('under_score', null);
      await db.addTodoItem('underXscore', null);

      Future<List<String>> run(String value) async {
        final definition = SavedFilterDefinition.parse(
          scope: 'tasks',
          filterJson: definitionJson('tasks', {
            'field': 'title',
            'op': 'contains',
            'value': value,
          }),
        );
        final compiled = definition.compile();
        final rows = await db
            .customSelect(
              'SELECT title FROM todo_items WHERE ${compiled.whereSql} '
              'ORDER BY title',
              variables: compiled.variables,
            )
            .get();
        return rows.map((row) => row.read<String>('title')).toList();
      }

      expect(await run('100%'), ['100% done']);
      expect(await run('under_'), ['under_score']);
    });

    test('a compiled date range uses Drift datetime parameters', () async {
      await db.addTodoItem('today', DateTime(2026, 5, 20, 9));
      await db.addTodoItem('tomorrow', DateTime(2026, 5, 21, 9));

      final definition = SavedFilterDefinition.parse(
        scope: 'tasks',
        filterJson: definitionJson('tasks', {
          'field': 'dueDate',
          'op': 'within',
          'value': 'today',
        }),
      );
      final compiled = definition.compile(now: DateTime(2026, 5, 20));
      final rows = await db
          .customSelect(
            'SELECT title FROM todo_items WHERE ${compiled.whereSql}',
            variables: compiled.variables,
          )
          .get();

      expect(rows.map((row) => row.read<String>('title')), ['today']);
    });
  });
}
