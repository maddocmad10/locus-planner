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
}
