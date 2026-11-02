import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import '../utils/day_math.dart';
import 'crypto/encrypted_envelope.dart';
import 'crypto/key_derivation.dart';
import 'error_log_service.dart';

/// What an encrypted diary restore changed.
class DiaryRestoreReport {
  const DiaryRestoreReport({
    required this.restored,
    required this.skipped,
    this.identical = 0,
    this.keptMine = 0,
  });

  /// Entries inserted or changed, matched by calendar day.
  final int restored;

  /// Malformed or duplicate-day entries left out of the backup.
  final int skipped;

  /// Days whose local text already matched the backup.
  final int identical;

  /// Conflicting days the user chose to keep unchanged.
  final int keptMine;

  bool get isClean => skipped == 0;
}

/// One diary entry parsed from a backup, before it is written.
class DiaryBackupEntry {
  const DiaryBackupEntry({
    required this.id,
    required this.day,
    required this.mood,
    required this.content,
  });

  final String id;
  final DateTime day;
  final int mood;
  final String content;
}

enum DiaryConflictPolicy { keepMine, replaceWithBackup, keepBoth }

/// What a diary restore would do, shown before anything is written.
class DiaryRestorePreview {
  const DiaryRestorePreview({
    required this.newCount,
    required this.identicalCount,
    required this.conflictCount,
    required this.skipped,
    required this.newEntries,
    required this.conflicts,
  });

  final int newCount;
  final int identicalCount;
  final int conflictCount;
  final int skipped;
  final List<DiaryBackupEntry> newEntries;
  final List<DiaryRestoreConflict> conflicts;

  int get total => newCount + conflictCount;
  bool get hasConflicts => conflictCount > 0;
}

class DiaryRestoreConflict {
  const DiaryRestoreConflict({required this.existing, required this.backup});

  final DiaryEntry existing;
  final DiaryBackupEntry backup;
}

/// Password-based encrypted export/restore for diary entries.
///
/// Diary text is the most private part of the planner. The ordinary JSON
/// backup and LAN sync are already local/authenticated, but a file that leaves
/// the machine is protected here with AES-256-GCM and a key derived from the
/// user's passphrase with PBKDF2-HMAC-SHA256. The passphrase is never stored;
/// losing it means the file cannot be recovered, which the UI says explicitly.
class EncryptedDiaryService {
  EncryptedDiaryService(
    this._db, {
    this.derive = KeyDerivation.derive,
    this.recoveryBackup,
  });

  static const maxFileBytes = 25 * 1024 * 1024;

  /// Kept for older callers and tests that read the envelope format name.
  static const format = EncryptedEnvelope.format;
  static const formatVersion = EncryptedEnvelope.version;
  static const defaultIterations = EncryptedEnvelope.defaultIterations;

  final AppDatabase _db;
  final DeriveKey derive;
  final Future<void> Function()? recoveryBackup;
  final _uuid = const Uuid();

  /// Serialises and encrypts every diary entry into one envelope.
  Future<String> buildEncryptedExport(String passphrase) async {
    if (passphrase.trim().isEmpty) {
      throw const FormatException('Enter a passphrase for the backup.');
    }
    final entries = await _db.watchDiaryEntries().first;
    final payload = <String, dynamic>{
      'format': 'locus.diary-backup',
      'version': 1,
      'exported_at': AppClock.now().toIso8601String(),
      'entries': [
        for (final entry in entries)
          {
            'id': entry.id,
            'date': DayMath.dateOnly(entry.date).toIso8601String(),
            'mood': entry.mood,
            'content': entry.content,
          },
      ],
    };
    return EncryptedEnvelope.seal(
      jsonEncode(payload),
      passphrase,
      payloadType: EncryptedEnvelope.payloadDiary,
      derive: derive,
    );
  }

  /// Encrypts the diary and lets the user choose where to save it.
  Future<bool> exportEncryptedDiary(String passphrase) async {
    try {
      final document = await buildEncryptedExport(passphrase);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Encrypted Diary',
        fileName:
            'locus_diary_${DateFormat('yyyy-MM-dd').format(AppClock.now())}'
            '.locusdiary',
      );
      if (path == null) return false;
      await File(path).writeAsString(document);
      return true;
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      rethrow;
    }
  }

  /// Lets the user choose an encrypted diary backup. Returns its text, or null
  /// when the picker was cancelled.
  Future<String?> pickEncryptedDiaryFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['locusdiary', 'json'],
      dialogTitle: 'Select Encrypted Locus Diary Backup',
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    return readEncryptedDiaryFile(File(path));
  }

  /// Applies the size limit before reading, so a mistaken pick of a huge file
  /// cannot exhaust memory.
  Future<String> readEncryptedDiaryFile(File file) async {
    final length = await file.length();
    if (length > maxFileBytes) {
      throw FormatException(
        'Diary backup is too large. Maximum size is '
        '${maxFileBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return file.readAsString();
  }

  /// Decrypts and classifies entries without writing anything.
  Future<DiaryRestorePreview> previewEncryptedRestore({
    required String document,
    required String passphrase,
  }) async {
    final payload = await _decrypt(document, passphrase);
    final entries = _entriesFromPayload(payload);
    var skipped = 0;
    final parsed = <DiaryBackupEntry>[];
    final seenDays = <DateTime>{};

    for (final raw in entries) {
      if (raw is! Map) {
        skipped++;
        continue;
      }
      final row = Map<String, dynamic>.from(raw);
      try {
        final day = _parseDay(row['date']);
        final mood = row['mood'];
        final content = row['content'];
        if (!seenDays.add(day) || mood is! int || content is! String) {
          skipped++;
          continue;
        }
        parsed.add(
          DiaryBackupEntry(
            id: row['id'] is String && (row['id'] as String).isNotEmpty
                ? row['id'] as String
                : _uuid.v4(),
            day: day,
            mood: mood < 1 ? 1 : (mood > 5 ? 5 : mood),
            content: content,
          ),
        );
      } on FormatException {
        skipped++;
      }
    }

    final newEntries = <DiaryBackupEntry>[];
    final conflicts = <DiaryRestoreConflict>[];
    var identical = 0;
    for (final entry in parsed) {
      final existing = await (_db.select(
        _db.diaryEntries,
      )..where((t) => t.date.equals(entry.day))).getSingleOrNull();
      if (existing == null) {
        newEntries.add(entry);
      } else if (existing.content == entry.content) {
        identical++;
      } else {
        conflicts.add(DiaryRestoreConflict(existing: existing, backup: entry));
      }
    }

    return DiaryRestorePreview(
      newCount: newEntries.length,
      identicalCount: identical,
      conflictCount: conflicts.length,
      skipped: skipped,
      newEntries: newEntries,
      conflicts: conflicts,
    );
  }

  /// Writes a preview. A recovery backup runs first; all writes then happen in
  /// one transaction so a failure leaves the diary unchanged.
  Future<DiaryRestoreReport> applyEncryptedRestore(
    DiaryRestorePreview preview, {
    DiaryConflictPolicy policy = DiaryConflictPolicy.keepBoth,
  }) async {
    final recovery = recoveryBackup;
    if (recovery != null) await recovery();

    var restored = 0;
    var keptMine = 0;
    await _db.transaction(() async {
      for (final entry in preview.newEntries) {
        var id = entry.id;
        final idTaken = await (_db.select(
          _db.diaryEntries,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (idTaken != null) id = _uuid.v4();
        await _db
            .into(_db.diaryEntries)
            .insert(
              DiaryEntriesCompanion(
                id: Value(id),
                date: Value(entry.day),
                mood: Value(entry.mood),
                content: Value(entry.content),
              ),
            );
        restored++;
      }

      for (final conflict in preview.conflicts) {
        switch (policy) {
          case DiaryConflictPolicy.keepMine:
            keptMine++;
          case DiaryConflictPolicy.replaceWithBackup:
            await (_db.update(
              _db.diaryEntries,
            )..where((t) => t.id.equals(conflict.existing.id))).write(
              DiaryEntriesCompanion(
                mood: Value(conflict.backup.mood),
                content: Value(conflict.backup.content),
              ),
            );
            restored++;
          case DiaryConflictPolicy.keepBoth:
            final merged = _keepBothText(
              conflict.existing.content,
              conflict.backup.content,
              conflict.backup.day,
            );
            if (merged != conflict.existing.content) {
              await (_db.update(_db.diaryEntries)
                    ..where((t) => t.id.equals(conflict.existing.id)))
                  .write(DiaryEntriesCompanion(content: Value(merged)));
              restored++;
            } else {
              keptMine++;
            }
        }
      }
    });

    return DiaryRestoreReport(
      restored: restored,
      skipped: preview.skipped,
      identical: preview.identicalCount,
      keptMine: keptMine,
    );
  }

  /// Decrypts [document] and adds/updates entries by calendar day.
  ///
  /// Kept as a convenient one-call path; use [previewEncryptedRestore] and
  /// [applyEncryptedRestore] to let the user choose how conflicts are handled.
  Future<DiaryRestoreReport> restoreFromEncrypted({
    required String document,
    required String passphrase,
    DiaryConflictPolicy policy = DiaryConflictPolicy.keepBoth,
  }) async {
    final preview = await previewEncryptedRestore(
      document: document,
      passphrase: passphrase,
    );
    return applyEncryptedRestore(preview, policy: policy);
  }

  Future<Map<String, dynamic>> _decrypt(
    String document,
    String passphrase,
  ) async {
    final opened = await EncryptedEnvelope.open(
      document,
      passphrase,
      derive: derive,
    );
    if (opened.payloadType != EncryptedEnvelope.payloadDiary) {
      throw const BackupDecryptionException(
        'That file is an encrypted full backup, not a diary backup.',
      );
    }
    try {
      final decoded = jsonDecode(opened.plaintext);
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'locus.diary-backup' ||
          decoded['version'] != 1) {
        throw const FormatException();
      }
      return decoded;
    } on FormatException {
      throw const BackupDecryptionException('The diary backup is damaged.');
    }
  }

  List<dynamic> _entriesFromPayload(Map<String, dynamic> payload) {
    final entries = payload['entries'];
    if (entries is! List) {
      throw const BackupDecryptionException('The diary backup has no entries.');
    }
    return entries;
  }

  DateTime _parseDay(Object? value) {
    if (value is int) {
      return DayMath.dateOnly(DateTime.fromMillisecondsSinceEpoch(value));
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return DayMath.dateOnly(parsed);
    }
    throw const FormatException('Invalid diary date in backup.');
  }

  String _keepBothText(String current, String backup, DateTime day) {
    final marker =
        '--- restored from backup (${DateFormat('yyyy-MM-dd').format(day)}) ---';
    if (current.contains(marker)) return current;
    return '$current\n\n$marker\n\n$backup';
  }
}
