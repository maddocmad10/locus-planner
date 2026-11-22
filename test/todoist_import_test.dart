import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/todoist_import_service.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late TodoistImportService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db, UndoService());
    service = TodoistImportService(db, tasks);
  });
  tearDown(() => db.close());

  const header =
      'TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,DATE,DATE_LANG,TIMEZONE\n';

  test('CSV reader handles BOM, quoted commas and multiline cells', () {
    final records = TodoistImportService.parseCsv(
      '\uFEFFTYPE,CONTENT\n'
      'task,"One, two"\n'
      'task,"line one\nline two"\n',
    );
    expect(records[0], ['TYPE', 'CONTENT']);
    expect(records[1][1], 'One, two');
    expect(records[2][1], 'line one\nline two');
  });

  test('preview maps priority, hierarchy and dates', () async {
    final project = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Imported',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    final preview = await service.preview(
      fileName: 'todoist.csv',
      destinationId: 'p1',
      csv:
          '$header'
          'task,Parent,,1,0,2026-12-02,,,\n'
          'task,Child,,2,1,2026-12-03 09:30,,,\n'
          'note,A note,,4,1,,,,\n'
          'section,Later,,4,0,,,,\n',
    );
    expect(project, greaterThan(0));
    expect(preview.rows[0].priority, 3);
    expect(preview.rows[0].dueDate, DateTime(2026, 12, 2));
    expect(preview.rows[1].parentRow, 1);
    expect(preview.rows[1].priority, 2);
    expect(preview.rows[1].dueDate, DateTime(2026, 12, 3, 9, 30));
    expect(preview.rows[2].disposition, TodoistDisposition.skip);
    expect(preview.rows[3].disposition, TodoistDisposition.skip);
  });

  test('commit writes tasks and receipts, and a rerun skips them', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Imported',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    const csv =
        '$header'
        'task,Parent,,4,0,,,,\n'
        'task,Child,,4,1,,,,\n';
    final preview = await service.preview(
      fileName: 'todoist.csv',
      csv: csv,
      destinationId: 'p1',
    );
    final result = await service.commit(
      preview: preview,
      destinationId: 'p1',
      decisions: const {},
    );
    expect(result.imported, 2);
    final rows = await db.select(db.todoItems).get();
    expect(rows, hasLength(2));
    final parent = rows.singleWhere((row) => row.title == 'Parent');
    final child = rows.singleWhere((row) => row.title == 'Child');
    expect(child.parentId, parent.id);
    expect(child.projectId, 'p1');

    final rerun = await service.preview(
      fileName: 'todoist.csv',
      csv: csv,
      destinationId: 'p1',
    );
    expect(rerun.rows.every((row) => row.reason == 'already_imported'), isTrue);
  });

  test(
    'a changed export offers a candidate without silently matching',
    () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Imported',
              createdAt: DateTime(2026, 11, 21),
            ),
          );
      const first =
          '$header'
          'task,Same title,,4,0,,,,\n';
      final preview = await service.preview(
        fileName: 'a.csv',
        csv: first,
        destinationId: 'p1',
      );
      await service.commit(
        preview: preview,
        destinationId: 'p1',
        decisions: const {},
      );

      const second =
          '$header'
          'task,Same title,,4,0,,,,\n'
          'task,Another,,4,0,,,,\n';
      final changed = await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      );
      expect(changed.rows[0].disposition, TodoistDisposition.review);
      expect(changed.rows[0].candidateTargetId, isNotNull);
      expect(changed.rows[1].disposition, TodoistDisposition.import);
    },
  );

  test('an invalid depth jump is reported per row', () async {
    final preview = await service.preview(
      fileName: 'x.csv',
      csv:
          '$header'
          'task,Jump,,4,3,,,,\n',
      destinationId: 'p1',
    );
    expect(preview.rows.single.disposition, TodoistDisposition.error);
    expect(preview.rows.single.reason, 'invalid_depth_jump');
  });

  test('imported tasks enter the normal sync outbox', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Imported',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    final preview = await service.preview(
      fileName: 'x.csv',
      csv:
          '$header'
          'task,Sync me,,4,0,,,,\n',
      destinationId: 'p1',
    );
    await service.commit(
      preview: preview,
      destinationId: 'p1',
      decisions: const {},
    );
    final pending = await db
        .customSelect(
          "SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = 'todo'",
        )
        .getSingle();
    expect(pending.read<int>('count'), greaterThan(0));
  });

  test('a proposed project is created only at commit', () async {
    const csv =
        '$header'
        'task,New task,,4,0,,,,\n';
    final preview = await service.preview(
      fileName: 'new.csv',
      csv: csv,
      proposedProjectId: 'proposed-project',
      proposedProjectName: 'Proposed',
    );
    expect(
      (await db
              .customSelect('SELECT COUNT(*) AS count FROM projects')
              .getSingle())
          .read<int>('count'),
      0,
    );
    final result = await service.commit(
      preview: preview,
      destinationId: 'proposed-project',
      decisions: const {},
    );
    expect(result.imported, 1);
    final project = await (db.select(
      db.projects,
    )..where((row) => row.id.equals('proposed-project'))).getSingle();
    expect(project.name, 'Proposed');
    final task = await db.select(db.todoItems).getSingle();
    expect(task.projectId, 'proposed-project');

    // A retry of the same proposed id does not create a second project.
    final again = await service.preview(
      fileName: 'new.csv',
      csv: csv,
      destinationId: 'proposed-project',
    );
    expect(again.rows.single.reason, 'already_imported');
  });

  test('cancelling a preview writes nothing', () async {
    await service.preview(
      fileName: 'cancel.csv',
      csv:
          '$header'
          'task,Not written,,4,0,,,,\n',
      proposedProjectId: 'cancel-project',
      proposedProjectName: 'Cancel',
    );
    expect((await db.select(db.projects).get()), isEmpty);
    expect((await db.select(db.todoItems).get()), isEmpty);
    expect(
      (await db.customSelect('SELECT * FROM import_receipts').get()),
      isEmpty,
    );
  });

  test(
    'successive changed exports reuse one live parent without duplicates',
    () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Imported',
              createdAt: DateTime(2026, 11, 21),
            ),
          );
      const first =
          '$header'
          'task,Parent,,4,0,,,,\n';
      await service.commit(
        preview: await service.preview(
          fileName: 'a.csv',
          csv: first,
          destinationId: 'p1',
        ),
        destinationId: 'p1',
        decisions: const {},
      );
      final parentId = (await db.select(db.todoItems).getSingle()).id;

      const second =
          '$header'
          'task,Parent,,4,0,,,,\n'
          'task,Second,,4,0,,,,\n';
      final secondPreview = await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      );
      expect(secondPreview.rows[0].disposition, TodoistDisposition.review);
      expect(secondPreview.rows[0].candidates, hasLength(1));
      expect(secondPreview.rows[0].candidateTargetId, parentId);
      final secondResult = await service.commit(
        preview: secondPreview,
        destinationId: 'p1',
        decisions: const {},
      );
      expect(secondResult.imported, 1);
      expect(secondResult.skipped, 1);
      expect(
        (await db.select(db.todoItems).get()).where(
          (task) => task.title == 'Parent',
        ),
        hasLength(1),
      );

      const third =
          '$header'
          'task,Parent,,4,0,,,,\n'
          'task,Second,,4,0,,,,\n'
          'task,Third,,4,0,,,,\n';
      final thirdPreview = await service.preview(
        fileName: 'c.csv',
        csv: third,
        destinationId: 'p1',
      );
      // The same parent target is recorded by two prior exports but is one
      // distinct live candidate.
      expect(thirdPreview.rows[0].candidates, hasLength(1));
      expect(thirdPreview.rows[0].candidates.single.targetId, parentId);
      final thirdResult = await service.commit(
        preview: thirdPreview,
        destinationId: 'p1',
        decisions: const {},
      );
      expect(thirdResult.imported, 1);

      final tasks = await db.select(db.todoItems).get();
      expect(tasks, hasLength(3));
      expect(tasks.where((task) => task.title == 'Parent'), hasLength(1));
      expect(tasks.where((task) => task.title == 'Second'), hasLength(1));
      expect(tasks.where((task) => task.title == 'Third'), hasLength(1));

      // Replaying the final export must not create a fourth task.
      final replay = await service.preview(
        fileName: 'c.csv',
        csv: third,
        destinationId: 'p1',
      );
      final replayResult = await service.commit(
        preview: replay,
        destinationId: 'p1',
        decisions: const {},
      );
      expect(replayResult.imported, 0);
      expect(await db.select(db.todoItems).get(), hasLength(3));
    },
  );

  test('two genuine matching parents require an explicit selection', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Imported',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    const first =
        '$header'
        'task,Match,,4,0,2026-12-05,,,\n';
    await service.commit(
      preview: await service.preview(
        fileName: 'a.csv',
        csv: first,
        destinationId: 'p1',
      ),
      destinationId: 'p1',
      decisions: const {},
    );
    final firstMatch = (await db.select(db.todoItems).getSingle()).id;
    final parentId = await tasks.add(title: 'Parent task', projectId: 'p1');
    await db.customStatement(
      'UPDATE todo_items SET parent_id = ? WHERE id = ?',
      [parentId, firstMatch],
    );

    const second =
        '$header'
        'task,Match,,4,0,2026-12-05,,,\n'
        'task,Other,,4,0,,,,\n';
    await service.commit(
      preview: await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      ),
      destinationId: 'p1',
      decisions: const {1: TodoistDecision.create()},
    );
    final matches = (await db.select(db.todoItems).get())
        .where((task) => task.title == 'Match')
        .toList();
    expect(matches, hasLength(2));
    final secondMatch = matches.singleWhere((task) => task.id != firstMatch).id;

    const third =
        '$header'
        'task,Match,,4,0,2026-12-05,,,\n'
        '\n';
    final thirdPreview = await service.preview(
      fileName: 'c.csv',
      csv: third,
      destinationId: 'p1',
    );
    final row = thirdPreview.rows.single;
    expect(row.disposition, TodoistDisposition.review);
    expect(row.reason, 'ambiguous_candidate');
    expect(row.candidates, hasLength(2));

    final firstCandidate = row.candidates.singleWhere(
      (candidate) => candidate.targetId == firstMatch,
    );
    expect(firstCandidate.projectId, 'p1');
    expect(firstCandidate.projectName, 'Imported');
    expect(firstCandidate.parentPath, 'Parent task');
    expect(firstCandidate.dueDate, DateTime(2026, 12, 5));
    final secondCandidate = row.candidates.singleWhere(
      (candidate) => candidate.targetId == secondMatch,
    );
    expect(secondCandidate.projectName, 'Imported');

    final selected = await service.commit(
      preview: thirdPreview,
      destinationId: 'p1',
      decisions: {1: TodoistDecision.reuse(secondMatch)},
    );
    expect(selected.imported, 0);
    expect(selected.skipped, 1);
    expect(
      (await db.select(db.todoItems).get()).where(
        (task) => task.title == 'Match',
      ),
      hasLength(2),
    );
    final receipt = await db
        .customSelect(
          'SELECT target_id FROM import_receipts '
          'WHERE file_sha256 = ? AND row_number = 1',
          variables: [Variable.withString(thirdPreview.fileSha256)],
        )
        .getSingle();
    expect(receipt.read<String>('target_id'), secondMatch);

    final replay = await service.preview(
      fileName: 'c.csv',
      csv: third,
      destinationId: 'p1',
    );
    expect(replay.rows.single.reason, 'already_imported');
    expect(
      (await service.commit(
        preview: replay,
        destinationId: 'p1',
        decisions: const {},
      )).imported,
      0,
    );
  });

  test(
    'legacy action strings can carry an explicitly selected target',
    () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Imported',
              createdAt: DateTime(2026, 11, 21),
            ),
          );
      const first =
          '$header'
          'task,Match,,4,0,,,,\n';
      await service.commit(
        preview: await service.preview(
          fileName: 'a.csv',
          csv: first,
          destinationId: 'p1',
        ),
        destinationId: 'p1',
        decisions: const {},
      );
      final targetId = (await db.select(db.todoItems).getSingle()).id;

      const second =
          '$header'
          'task,Match,,4,0,,,,\n'
          '\n';
      final preview = await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      );

      final result = await service.commit(
        preview: preview,
        destinationId: 'p1',
        decisions: const {1: 'reuse'},
        selectedTargets: {1: targetId},
      );

      expect(result.imported, 0);
      expect(result.skipped, 1);
      expect(await db.select(db.todoItems).get(), hasLength(1));
      final receipt = await db
          .customSelect(
            'SELECT target_id FROM import_receipts '
            'WHERE file_sha256 = ? AND row_number = 1',
            variables: [Variable.withString(preview.fileSha256)],
          )
          .getSingle();
      expect(receipt.read<String>('target_id'), targetId);
    },
  );

  test(
    'a chosen target removed after preview records a skip receipt',
    () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Imported',
              createdAt: DateTime(2026, 11, 21),
            ),
          );
      const first =
          '$header'
          'task,Match,,4,0,,,,\n';
      await service.commit(
        preview: await service.preview(
          fileName: 'a.csv',
          csv: first,
          destinationId: 'p1',
        ),
        destinationId: 'p1',
        decisions: const {},
      );
      final targetId = (await db.select(db.todoItems).getSingle()).id;

      const second =
          '$header'
          'task,Match,,4,0,,,,\n'
          '\n';
      final preview = await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      );
      expect(preview.rows.single.candidates, hasLength(1));
      await db.customStatement('DELETE FROM todo_items WHERE id = ?', [
        targetId,
      ]);

      final result = await service.commit(
        preview: preview,
        destinationId: 'p1',
        decisions: {1: TodoistDecision.reuse(targetId)},
      );

      expect(result.imported, 0);
      expect(result.skipped, 1);
      expect(await db.select(db.todoItems).get(), isEmpty);
      final receipt = await db
          .customSelect(
            'SELECT target_id FROM import_receipts '
            'WHERE file_sha256 = ? AND row_number = 1',
            variables: [Variable.withString(preview.fileSha256)],
          )
          .getSingle();
      expect(receipt.readNullable<String>('target_id'), isNull);
    },
  );

  test('a chosen target moved after preview records a skip receipt', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Imported',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p2',
            name: 'Elsewhere',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    const first =
        '$header'
        'task,Match,,4,0,,,,\n';
    await service.commit(
      preview: await service.preview(
        fileName: 'a.csv',
        csv: first,
        destinationId: 'p1',
      ),
      destinationId: 'p1',
      decisions: const {},
    );
    final targetId = (await db.select(db.todoItems).getSingle()).id;

    const second =
        '$header'
        'task,Match,,4,0,,,,\n'
        '\n';
    final preview = await service.preview(
      fileName: 'b.csv',
      csv: second,
      destinationId: 'p1',
    );
    await db.customStatement(
      'UPDATE todo_items SET project_id = ? WHERE id = ?',
      ['p2', targetId],
    );

    final result = await service.commit(
      preview: preview,
      destinationId: 'p1',
      decisions: {1: TodoistDecision.reuse(targetId)},
    );

    expect(result.imported, 0);
    expect(result.skipped, 1);
    final task = (await db.select(db.todoItems).getSingle());
    expect(task.projectId, 'p2');
    final receipt = await db
        .customSelect(
          'SELECT target_id FROM import_receipts '
          'WHERE file_sha256 = ? AND row_number = 1',
          variables: [Variable.withString(preview.fileSha256)],
        )
        .getSingle();
    expect(receipt.readNullable<String>('target_id'), isNull);
  });

  test('a reused parent is carried into a new child parent map', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Imported',
            createdAt: DateTime(2026, 11, 21),
          ),
        );
    const first =
        '$header'
        'task,Parent,,4,0,,,,\n';
    await service.commit(
      preview: await service.preview(
        fileName: 'a.csv',
        csv: first,
        destinationId: 'p1',
      ),
      destinationId: 'p1',
      decisions: const {},
    );
    final parentId = (await db.select(db.todoItems).getSingle()).id;

    const second =
        '$header'
        'task,Parent,,4,0,,,,\n'
        'task,Child,,4,1,,,,\n';
    final preview = await service.preview(
      fileName: 'b.csv',
      csv: second,
      destinationId: 'p1',
    );
    expect(preview.rows[0].disposition, TodoistDisposition.review);
    expect(preview.rows[0].candidates, hasLength(1));

    final result = await service.commit(
      preview: preview,
      destinationId: 'p1',
      decisions: const {},
    );

    expect(result.imported, 1);
    expect(result.skipped, 1);
    final tasks = await db.select(db.todoItems).get();
    expect(tasks.where((task) => task.title == 'Parent'), hasLength(1));
    final child = tasks.singleWhere((task) => task.title == 'Child');
    expect(child.parentId, parentId);
  });

  test(
    'an already-imported parent is carried into a new child parent map',
    () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Imported',
              createdAt: DateTime(2026, 11, 21),
            ),
          );
      const first =
          '$header'
          'task,Parent,,4,0,,,,\n';
      await service.commit(
        preview: await service.preview(
          fileName: 'a.csv',
          csv: first,
          destinationId: 'p1',
        ),
        destinationId: 'p1',
        decisions: const {},
      );
      final parentId = (await db.select(db.todoItems).getSingle()).id;

      const second =
          '$header'
          'task,Parent,,4,0,,,,\n'
          'task,Child,,4,1,,,,\n';
      final seedPreview = await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      );
      // Simulate a prior partial import where the parent row was already
      // committed but the child row was not.
      await db.customStatement(
        'INSERT INTO import_receipts '
        '(source_kind, destination_id, file_sha256, row_number, target_id, '
        'row_fingerprint, imported_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          TodoistImportService.sourceKind,
          'p1',
          seedPreview.fileSha256,
          1,
          parentId,
          'seed',
          DateTime(2026, 11, 21).millisecondsSinceEpoch,
        ],
      );

      final preview = await service.preview(
        fileName: 'b.csv',
        csv: second,
        destinationId: 'p1',
      );
      expect(preview.rows[0].disposition, TodoistDisposition.skip);
      expect(preview.rows[0].reason, 'already_imported');
      expect(preview.rows[1].disposition, TodoistDisposition.import);

      final result = await service.commit(
        preview: preview,
        destinationId: 'p1',
        decisions: const {},
      );

      expect(result.imported, 1);
      expect(result.skipped, 1);
      final tasks = await db.select(db.todoItems).get();
      expect(tasks.where((task) => task.title == 'Parent'), hasLength(1));
      final child = tasks.singleWhere((task) => task.title == 'Child');
      expect(child.parentId, parentId);
    },
  );
}
