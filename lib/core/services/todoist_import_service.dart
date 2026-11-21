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
    this.candidateTargetId,
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
  String? candidateTargetId;
}

class TodoistPreview {
  const TodoistPreview({
    required this.fileName,
    required this.fileSha256,
    required this.rows,
    required this.defaultPriority,
    required this.missingColumns,
  });

  final String fileName;
  final String fileSha256;
  final List<TodoistRow> rows;
  final int defaultPriority;
  final List<String> missingColumns;

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
    required String destinationId,
    int defaultPriority = 0,
  }) async {
    tzdata.initializeTimeZones();
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
          'SELECT row_number FROM import_receipts '
          'WHERE source_kind = ? AND destination_id = ? AND file_sha256 = ?',
          variables: [
            Variable.withString(sourceKind),
            Variable.withString(destinationId),
            Variable.withString(fileSha256),
          ],
        )
        .get();
    final committedRows = {
      for (final row in committed) row.read<int>('row_number'),
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
          committedRows.contains(rowNumber)) {
        disposition = TodoistDisposition.skip;
        reason = 'already_imported';
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
      );
      byRow[rowNumber] = row;
      rows.add(row);
    }

    // A changed export: offer fingerprint candidates for review. A title alone
    // never silently identifies an existing task.
    final priorReceipts = await _db
        .customSelect(
          'SELECT row_fingerprint, target_id FROM import_receipts '
          'WHERE source_kind = ? AND destination_id = ? '
          'AND target_id IS NOT NULL',
          variables: [
            Variable.withString(sourceKind),
            Variable.withString(destinationId),
          ],
        )
        .get();
    final byFingerprint = <String, List<String>>{};
    for (final receipt in priorReceipts) {
      byFingerprint
          .putIfAbsent(receipt.read<String>('row_fingerprint'), () => [])
          .add(receipt.read<String>('target_id'));
    }
    for (final row in rows) {
      if (row.disposition != TodoistDisposition.import) continue;
      final candidates = byFingerprint[row.fingerprint];
      if (candidates == null || candidates.isEmpty) continue;
      row.disposition = TodoistDisposition.review;
      row.reason = candidates.length > 1
          ? 'ambiguous_candidate'
          : 'candidate_match';
      if (candidates.length == 1) row.candidateTargetId = candidates.first;
    }
    return TodoistPreview(
      fileName: fileName,
      fileSha256: fileSha256,
      rows: rows,
      defaultPriority: defaultPriority,
      missingColumns: missing,
    );
  }

  /// Commits approved rows and their receipts in one transaction. A cancelled
  /// preview or failed transaction leaves the project exactly as it was.
  Future<({int imported, int skipped})> commit({
    required TodoistPreview preview,
    required String destinationId,
    required Map<int, String> decisions,
  }) async {
    var imported = 0;
    var skipped = 0;
    await _db.transaction(() async {
      final created = <int, String>{};
      final now = AppClock.now().millisecondsSinceEpoch;
      for (final row in preview.rows) {
        if (row.disposition == TodoistDisposition.error ||
            row.disposition == TodoistDisposition.skip) {
          if (row.disposition == TodoistDisposition.skip) skipped++;
          continue;
        }
        final decision = decisions[row.rowNumber] ?? 'create';
        if (row.disposition == TodoistDisposition.review &&
            decision != 'create') {
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
        if (row.disposition == TodoistDisposition.import ||
            decision == 'create') {
          final id = await _tasks.add(
            title: row.content,
            notes: row.description.isEmpty ? null : row.description,
            dueDate: row.dateNeedsChoice ? null : row.dueDate,
            priority: TaskPriority.fromStorage(row.priority),
            parentId: row.parentRow == null ? null : created[row.parentRow],
            projectId: destinationId,
          );
          created[row.rowNumber] = id;
          imported++;
          await _insertReceipt(preview.fileSha256, destinationId, row, id, now);
        }
      }
    });
    return (imported: imported, skipped: skipped);
  }

  Future<void> _insertReceipt(
    String fileSha256,
    String destinationId,
    TodoistRow row,
    String? targetId,
    int now,
  ) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO import_receipts '
      '(source_kind, destination_id, file_sha256, row_number, target_id, '
      'row_fingerprint, imported_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
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
