import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import '../../features/tasks/data/task_metadata.dart';
import '../../features/tasks/data/task_repository.dart';

enum TodoistDisposition { import, skip, review, error }

enum TodoistDecisionAction { create, reuse, skip }

/// One user decision for a preview row. [targetId] is the explicitly selected
/// live task when [action] is [TodoistDecisionAction.reuse].
class TodoistDecision {
  const TodoistDecision(this.action, {this.targetId});

  const TodoistDecision.create()
    : action = TodoistDecisionAction.create,
      targetId = null;

  const TodoistDecision.reuse(String target)
    : action = TodoistDecisionAction.reuse,
      targetId = target;

  const TodoistDecision.skip()
    : action = TodoistDecisionAction.skip,
      targetId = null;

  final TodoistDecisionAction action;
  final String? targetId;
}

/// A live task in the destination that a changed export may match. Details are
/// shown so two genuinely similar tasks can be told apart before reuse.
class TodoistCandidate {
  const TodoistCandidate({
    required this.targetId,
    required this.title,
    this.projectId,
    this.projectName,
    this.parentId,
    this.parentPath,
    this.dueDate,
    this.dueDateKey,
  });

  final String targetId;
  final String title;
  final String? projectId;
  final String? projectName;
  final String? parentId;
  final String? parentPath;
  final DateTime? dueDate;
  final String? dueDateKey;

  String? get projectPath => projectName;

  String? get parent => parentPath;

  String get label {
    final parts = <String>[
      if (projectName != null && projectName!.isNotEmpty) projectName!,
      if (parentPath != null && parentPath!.isNotEmpty) parentPath!,
      title,
      if (dueDate != null)
        'due ${dueDate!.toIso8601String().split('T').first}'
      else if (dueDateKey != null)
        'due $dueDateKey',
    ];
    return parts.join(' / ');
  }
}

class TodoistRow {
  TodoistRow({
    required this.rowNumber,
    required this.type,
    required this.content,
    required this.description,
    required this.priority,
    required this.indent,
    required this.dateRaw,
    required this.dueDate,
    required this.dateNeedsChoice,
    required this.parentRow,
    required this.fingerprint,
    required this.disposition,
    required this.reason,
    this.candidates = const [],
    this.selectedTargetId,
  });

  final int rowNumber;
  final String type;
  final String content;
  final String description;
  final int priority;
  final int indent;
  final String dateRaw;
  final DateTime? dueDate;
  final bool dateNeedsChoice;
  final int? parentRow;
  final String fingerprint;
  TodoistDisposition disposition;
  String? reason;

  /// Distinct live tasks in the destination whose receipt fingerprint matches.
  List<TodoistCandidate> candidates;

  /// The explicitly selected candidate, or the prior target already imported.
  String? selectedTargetId;

  /// Convenience for UI and older callers: an unambiguous match.
  String? get candidateTargetId =>
      candidates.length == 1 ? candidates.single.targetId : selectedTargetId;

  List<String> get candidateTargetIds => [
    for (final candidate in candidates) candidate.targetId,
  ];
}

class TodoistPreview {
  const TodoistPreview({
    required this.fileName,
    required this.fileSha256,
    required this.rows,
    required this.defaultPriority,
    required this.missingColumns,
    this.destinationId,
    this.proposedProjectId,
    this.proposedProjectName,
  });

  final String fileName;
  final String fileSha256;
  final List<TodoistRow> rows;
  final int defaultPriority;
  final List<String> missingColumns;

  /// Existing destination, or null when the preview proposes a new project.
  final String? destinationId;
  final String? proposedProjectId;
  final String? proposedProjectName;

  int get importable =>
      rows.where((row) => row.disposition == TodoistDisposition.import).length;
  int get skipped =>
      rows.where((row) => row.disposition == TodoistDisposition.skip).length;
  int get review =>
      rows.where((row) => row.disposition == TodoistDisposition.review).length;
  int get errors =>
      rows.where((row) => row.disposition == TodoistDisposition.error).length;
}

class TodoistImportService {
  TodoistImportService(this._db, this._tasks);

  static const sourceKind = 'todoist_csv';
  static const _required = ['TYPE', 'CONTENT'];
  static const _known = [
    'TYPE',
    'CONTENT',
    'DESCRIPTION',
    'PRIORITY',
    'INDENT',
    'DATE',
    'DATE_LANG',
    'TIMEZONE',
  ];

  final AppDatabase _db;
  final TaskRepository _tasks;

  Future<TodoistPreview> preview({
    required String fileName,
    required String csv,
    String? destinationId,
    String? proposedProjectId,
    String? proposedProjectName,
    int defaultPriority = 0,
  }) async {
    tzdata.initializeTimeZones();
    final destination = destinationId ?? proposedProjectId ?? '';
    final projectName = proposedProjectName?.trim() ?? '';
    if (destinationId == null && (destination.isEmpty || projectName.isEmpty)) {
      throw const FormatException(
        'Choose a project or name the new destination project.',
      );
    }
    final records = parseCsv(csv);
    if (records.isEmpty) {
      throw const FormatException('The CSV file is empty.');
    }
    final header = [
      for (final value in records.first) value.trim().toUpperCase(),
    ];
    for (final required in _required) {
      if (!header.contains(required)) {
        throw FormatException('The CSV is missing the $required column.');
      }
    }
    final missing = [
      for (final column in _known)
        if (!header.contains(column)) column,
    ];
    final fileSha256 = sha256.convert(utf8.encode(csv)).toString();
    final committed = await _db
        .customSelect(
          'SELECT row_number, target_id FROM import_receipts '
          'WHERE source_kind = ? AND destination_id = ? AND file_sha256 = ?',
          variables: [
            Variable.withString(sourceKind),
            Variable.withString(destination),
            Variable.withString(fileSha256),
          ],
        )
        .get();
    final committedRows = <int, String?>{
      for (final row in committed)
        row.read<int>('row_number'): row.readNullable<String>('target_id'),
    };
    final rows = <TodoistRow>[];
    final stack = <int>[];
    final byRow = <int, TodoistRow>{};
    var rowNumber = 0;
    for (final record in records.skip(1)) {
      if (record.every((value) => value.trim().isEmpty)) continue;
      rowNumber++;
      String value(String name) {
        final index = header.indexOf(name);
        return index < 0 || index >= record.length ? '' : record[index].trim();
      }

      final type = value('TYPE').toLowerCase();
      final content = value('CONTENT');
      final description = value('DESCRIPTION');
      final rawIndent = value('INDENT');
      final indent = rawIndent.isEmpty ? 0 : int.tryParse(rawIndent) ?? -1;
      final rawPriority = value('PRIORITY');
      final priority = _priority(rawPriority) ?? defaultPriority;
      final dateRaw = value('DATE');
      final parsedDate = _date(
        dateRaw,
        dateLang: value('DATE_LANG'),
        timezone: value('TIMEZONE'),
      );
      int? parentRow;
      String? reason;
      String? rowCandidate;
      var disposition = TodoistDisposition.import;
      if (type == 'section' || type == 'note') {
        disposition = TodoistDisposition.skip;
        reason = '${type}_row';
      } else if (type != 'task') {
        disposition = TodoistDisposition.skip;
        reason = 'unsupported_type';
      } else if (content.isEmpty) {
        disposition = TodoistDisposition.error;
        reason = 'missing_content';
      } else if (indent < 0) {
        disposition = TodoistDisposition.error;
        reason = 'invalid_indent';
      } else if (indent > stack.length) {
        disposition = TodoistDisposition.error;
        reason = 'invalid_depth_jump';
      }
      if (disposition == TodoistDisposition.import ||
          disposition == TodoistDisposition.error ||
          (disposition == TodoistDisposition.skip && type == 'section')) {
        if (indent >= 0 && indent <= stack.length) {
          stack.length = indent;
          if (indent > 0) parentRow = stack.isEmpty ? null : stack.last;
          stack.add(rowNumber);
        }
      }
      final parentPath = _parentPath(parentRow, byRow);
      final fingerprint = sha256
          .convert(
            utf8.encode(
              '$parentPath|${content.toLowerCase()}|$priority|'
              '${parsedDate?.toIso8601String() ?? ''}|$description',
            ),
          )
          .toString();
      if (disposition == TodoistDisposition.import &&
          committedRows.containsKey(rowNumber)) {
        final target = committedRows[rowNumber];
        final live =
            target != null && await _targetInDestination(target, destination);
        disposition = live
            ? TodoistDisposition.skip
            : TodoistDisposition.review;
        reason = live ? 'already_imported' : 'prior_target_missing';
        if (live) rowCandidate = target;
      }
      if (disposition == TodoistDisposition.import &&
          parsedDate == null &&
          dateRaw.isNotEmpty) {
        disposition = TodoistDisposition.review;
        reason = 'date_requires_choice';
      }
      final row = TodoistRow(
        rowNumber: rowNumber,
        type: type,
        content: content,
        description: description,
        priority: priority,
        indent: indent,
        dateRaw: dateRaw,
        dueDate: parsedDate,
        dateNeedsChoice: parsedDate == null && dateRaw.isNotEmpty,
        parentRow: parentRow,
        fingerprint: fingerprint,
        disposition: disposition,
        reason: reason,
        selectedTargetId: rowCandidate,
      );
      byRow[rowNumber] = row;
      rows.add(row);
    }

    // A changed export: offer distinct live targets in this destination for
    // review. A title alone never silently identifies an existing task, and the
    // same target recorded by several earlier files is still one candidate.
    final priorReceipts = await _db
        .customSelect(
          'SELECT row_fingerprint, target_id FROM import_receipts '
          'WHERE source_kind = ? AND destination_id = ? '
          'AND target_id IS NOT NULL',
          variables: [
            Variable.withString(sourceKind),
            Variable.withString(destination),
          ],
        )
        .get();
    final byFingerprint = <String, Set<String>>{};
    for (final receipt in priorReceipts) {
      byFingerprint
          .putIfAbsent(
            receipt.read<String>('row_fingerprint'),
            () => <String>{},
          )
          .add(receipt.read<String>('target_id'));
    }
    final targetIds = byFingerprint.values.expand((ids) => ids).toSet();
    final liveTargets = await _liveTargetsInDestination(destination, targetIds);
    final destinationName = await _projectName(destination);
    final parentCache = <String, ({String title, String? parentId})>{};
    for (final row in rows) {
      if (row.disposition != TodoistDisposition.import) continue;
      final ids = byFingerprint[row.fingerprint];
      if (ids == null || ids.isEmpty) continue;
      final candidates = <TodoistCandidate>[];
      for (final id in ids) {
        final target = liveTargets[id];
        if (target == null) continue;
        candidates.add(
          await _candidateFor(
            target,
            projectName: destinationName,
            parentCache: parentCache,
          ),
        );
      }
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) => a.targetId.compareTo(b.targetId));
      row.candidates = candidates;
      row.disposition = TodoistDisposition.review;
      row.reason = candidates.length > 1
          ? 'ambiguous_candidate'
          : 'candidate_match';
      if (candidates.length == 1) {
        row.selectedTargetId = candidates.single.targetId;
      }
    }
    return TodoistPreview(
      fileName: fileName,
      fileSha256: fileSha256,
      rows: rows,
      defaultPriority: defaultPriority,
      missingColumns: missing,
      destinationId: destinationId,
      proposedProjectId: destinationId == null ? destination : null,
      proposedProjectName: destinationId == null ? projectName : null,
    );
  }

  /// Commits approved rows and their receipts in one transaction. A cancelled
  /// preview or failed transaction leaves the project exactly as it was.
  Future<({int imported, int skipped, String destinationId})> commit({
    required TodoistPreview preview,
    required String destinationId,
    Map<int, Object?> decisions = const {},
    Map<int, String> selectedTargets = const {},
  }) async {
    var imported = 0;
    var skipped = 0;
    await _db.transaction(() async {
      final now = AppClock.now().millisecondsSinceEpoch;
      final existingDestination = await _rowExists('projects', destinationId);
      if (!existingDestination) {
        final name = preview.proposedProjectName?.trim() ?? '';
        if (preview.proposedProjectId != destinationId || name.isEmpty) {
          throw StateError(
            'The proposed destination project is not available.',
          );
        }
        await _db
            .into(_db.projects)
            .insert(
              ProjectsCompanion.insert(
                id: destinationId,
                name: name,
                createdAt: AppClock.now(),
              ),
            );
        await _db.ensureProjectStatuses(destinationId);
      }
      final created = <int, String>{};
      for (final row in preview.rows) {
        if (row.disposition == TodoistDisposition.error) continue;
        if (row.disposition == TodoistDisposition.skip) {
          skipped++;
          // An already-imported (or explicitly kept) parent must still be
          // available to a new child in this export.
          final known = row.selectedTargetId;
          if (known != null &&
              await _targetInDestination(known, destinationId)) {
            created[row.rowNumber] = known;
          }
          continue;
        }

        // Exact prior receipt for this very file: re-read inside the
        // transaction and revalidate both existence and destination.
        final prior = await _db
            .customSelect(
              'SELECT target_id FROM import_receipts '
              'WHERE source_kind = ? AND destination_id = ? '
              'AND file_sha256 = ? AND row_number = ?',
              variables: [
                Variable.withString(sourceKind),
                Variable.withString(destinationId),
                Variable.withString(preview.fileSha256),
                Variable.withInt(row.rowNumber),
              ],
            )
            .getSingleOrNull();
        final priorTarget = prior?.readNullable<String>('target_id');
        if (priorTarget != null &&
            await _targetInDestination(priorTarget, destinationId)) {
          created[row.rowNumber] = priorTarget;
          skipped++;
          continue;
        }

        final requested = _requestedDecision(
          decisions[row.rowNumber],
          selectedTargets[row.rowNumber],
        );
        final action = requested?.action ?? _defaultAction(row);
        if (action == TodoistDecisionAction.skip) {
          skipped++;
          await _insertReceipt(
            preview.fileSha256,
            destinationId,
            row,
            null,
            now,
          );
          continue;
        }
        if (action == TodoistDecisionAction.reuse) {
          final chosen =
              requested?.targetId ??
              row.selectedTargetId ??
              (row.candidates.length == 1
                  ? row.candidates.single.targetId
                  : null);
          if (chosen == null ||
              !await _targetInDestination(chosen, destinationId)) {
            // The chosen task was removed or moved after preview. Record the
            // skip instead of silently dropping the row or re-creating it.
            skipped++;
            await _insertReceipt(
              preview.fileSha256,
              destinationId,
              row,
              null,
              now,
            );
            continue;
          }
          created[row.rowNumber] = chosen;
          skipped++;
          await _insertReceipt(
            preview.fileSha256,
            destinationId,
            row,
            chosen,
            now,
          );
          continue;
        }

        String? parentId;
        if (row.parentRow != null) {
          parentId = created[row.parentRow];
          if (parentId == null) {
            // A held or skipped parent must not silently turn the child into a
            // top-level task.
            skipped++;
            await _insertReceipt(
              preview.fileSha256,
              destinationId,
              row,
              null,
              now,
            );
            continue;
          }
        }
        final id = await _tasks.add(
          title: row.content,
          notes: row.description.isEmpty ? null : row.description,
          dueDate: row.dateNeedsChoice ? null : row.dueDate,
          priority: TaskPriority.fromStorage(row.priority),
          parentId: parentId,
          projectId: destinationId,
        );
        created[row.rowNumber] = id;
        imported++;
        await _insertReceipt(preview.fileSha256, destinationId, row, id, now);
      }
    });
    return (imported: imported, skipped: skipped, destinationId: destinationId);
  }

  /// Accepts the typed decision used by the dialog, older action strings, and
  /// a separate selected-target map for callers that keep decisions simple.
  TodoistDecision? _requestedDecision(Object? value, String? selectedTarget) {
    if (value is TodoistDecision) {
      if (value.action == TodoistDecisionAction.reuse &&
          value.targetId == null &&
          selectedTarget != null) {
        return TodoistDecision.reuse(selectedTarget);
      }
      return value;
    }
    if (value is String) {
      switch (value) {
        case 'create':
          return const TodoistDecision.create();
        case 'skip':
          return const TodoistDecision.skip();
        case 'reuse':
          return TodoistDecision(
            TodoistDecisionAction.reuse,
            targetId: selectedTarget,
          );
        default:
          if (value.startsWith('reuse:')) {
            return TodoistDecision.reuse(value.substring(6));
          }
      }
    }
    if (selectedTarget != null) return TodoistDecision.reuse(selectedTarget);
    return null;
  }

  TodoistDecisionAction _defaultAction(TodoistRow row) {
    if (row.disposition != TodoistDisposition.review) {
      return TodoistDecisionAction.create;
    }
    // One live match (or an explicit row selection) is safe to reuse.
    // Ambiguous or incomplete review rows require an explicit choice; never
    // fall back to creating a duplicate.
    return row.selectedTargetId != null || row.candidates.length == 1
        ? TodoistDecisionAction.reuse
        : TodoistDecisionAction.skip;
  }

  Future<bool> _rowExists(String table, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 AS present FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<bool> _targetInDestination(String id, String destinationId) async {
    if (destinationId.isEmpty) return false;
    final rows = await _db
        .customSelect(
          'SELECT 1 AS present FROM todo_items '
          'WHERE id = ? AND project_id = ?',
          variables: [
            Variable.withString(id),
            Variable.withString(destinationId),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<Map<String, _LiveTarget>> _liveTargetsInDestination(
    String destinationId,
    Set<String> ids,
  ) async {
    final result = <String, _LiveTarget>{};
    if (destinationId.isEmpty || ids.isEmpty) return result;
    final all = ids.toList();
    for (var start = 0; start < all.length; start += 400) {
      final end = start + 400 < all.length ? start + 400 : all.length;
      final chunk = all.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db
          .customSelect(
            'SELECT id, title, project_id, parent_id, due_date, due_date_key '
            'FROM todo_items WHERE project_id = ? AND id IN ($placeholders)',
            variables: [
              Variable.withString(destinationId),
              ...chunk.map(Variable.withString),
            ],
          )
          .get();
      for (final row in rows) {
        final id = row.read<String>('id');
        result[id] = _LiveTarget(
          id: id,
          title: row.read<String>('title'),
          projectId: row.readNullable<String>('project_id'),
          parentId: row.readNullable<String>('parent_id'),
          dueDate: row.readNullable<DateTime>('due_date'),
          dueDateKey: row.readNullable<String>('due_date_key'),
        );
      }
    }
    return result;
  }

  Future<String?> _projectName(String projectId) async {
    if (projectId.isEmpty) return null;
    final row = await _db
        .customSelect(
          'SELECT name FROM projects WHERE id = ?',
          variables: [Variable.withString(projectId)],
        )
        .getSingleOrNull();
    return row?.readNullable<String>('name');
  }

  Future<TodoistCandidate> _candidateFor(
    _LiveTarget target, {
    required String? projectName,
    required Map<String, ({String title, String? parentId})> parentCache,
  }) async => TodoistCandidate(
    targetId: target.id,
    title: target.title,
    projectId: target.projectId,
    projectName: projectName,
    parentId: target.parentId,
    parentPath: await _parentPathFor(target.parentId, parentCache),
    dueDate: target.dueDate,
    dueDateKey: target.dueDateKey,
  );

  Future<String?> _parentPathFor(
    String? parentId,
    Map<String, ({String title, String? parentId})> cache,
  ) async {
    if (parentId == null) return null;
    final parts = <String>[];
    final seen = <String>{};
    String? cursor = parentId;
    while (cursor != null && seen.add(cursor)) {
      var info = cache[cursor];
      if (info == null) {
        final row = await _db
            .customSelect(
              'SELECT title, parent_id FROM todo_items WHERE id = ?',
              variables: [Variable.withString(cursor)],
            )
            .getSingleOrNull();
        if (row == null) break;
        info = (
          title: row.read<String>('title'),
          parentId: row.readNullable<String>('parent_id'),
        );
        cache[cursor] = info;
      }
      parts.insert(0, info.title);
      cursor = info.parentId;
    }
    return parts.isEmpty ? null : parts.join(' / ');
  }

  Future<void> _insertReceipt(
    String fileSha256,
    String destinationId,
    TodoistRow row,
    String? targetId,
    int now,
  ) async {
    await _db.customStatement(
      'INSERT INTO import_receipts '
      '(source_kind, destination_id, file_sha256, row_number, target_id, '
      'row_fingerprint, imported_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(source_kind, destination_id, file_sha256, row_number) '
      'DO UPDATE SET target_id = excluded.target_id, '
      'row_fingerprint = excluded.row_fingerprint, '
      'imported_at_ms = excluded.imported_at_ms',
      [
        sourceKind,
        destinationId,
        fileSha256,
        row.rowNumber,
        targetId,
        row.fingerprint,
        now,
      ],
    );
  }

  static int? _priority(String raw) => switch (raw.trim()) {
    '1' => TaskPriority.high.value,
    '2' => TaskPriority.medium.value,
    '3' => TaskPriority.low.value,
    '4' || '' => TaskPriority.none.value,
    _ => null,
  };

  static DateTime? _date(
    String raw, {
    required String dateLang,
    required String timezone,
  }) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      return DateTime(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
      );
    }
    final parts = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})',
    ).firstMatch(value);
    if (parts == null) return null;
    final year = int.parse(parts.group(1)!);
    final month = int.parse(parts.group(2)!);
    final day = int.parse(parts.group(3)!);
    final hour = int.parse(parts.group(4)!);
    final minute = int.parse(parts.group(5)!);
    if (timezone.trim().isNotEmpty) {
      try {
        final location = tz.getLocation(timezone.trim());
        return tz.TZDateTime(
          location,
          year,
          month,
          day,
          hour,
          minute,
        ).toLocal();
      } catch (_) {
        // Fall through to local time when the zone name is unknown.
      }
    }
    return DateTime(year, month, day, hour, minute);
  }

  static String _parentPath(int? parentRow, Map<int, TodoistRow> byRow) {
    final parts = <String>[];
    var cursor = parentRow;
    final seen = <int>{};
    while (cursor != null && seen.add(cursor)) {
      final row = byRow[cursor];
      if (row == null) break;
      parts.insert(0, row.content.toLowerCase());
      cursor = row.parentRow;
    }
    return parts.join('/');
  }

  /// RFC 4180 reader with quoted commas, doubled quotes, multiline cells and a
  /// UTF-8 BOM. Blank lines are ignored later, not inside a quoted cell.
  static List<List<String>> parseCsv(String input) {
    var text = input;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final records = <List<String>>[];
    var record = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (quoted) {
        if (char == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            cell.write('"');
            index++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(char);
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        record.add(cell.toString());
        cell.clear();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        record.add(cell.toString());
        cell.clear();
        records.add(record);
        record = <String>[];
      } else {
        cell.write(char);
      }
    }
    if (cell.isNotEmpty || record.isNotEmpty) {
      record.add(cell.toString());
      records.add(record);
    }
    return records;
  }
}

class _LiveTarget {
  const _LiveTarget({
    required this.id,
    required this.title,
    this.projectId,
    this.parentId,
    this.dueDate,
    this.dueDateKey,
  });

  final String id;
  final String title;
  final String? projectId;
  final String? parentId;
  final DateTime? dueDate;
  final String? dueDateKey;
}
