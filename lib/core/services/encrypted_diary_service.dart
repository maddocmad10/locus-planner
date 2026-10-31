import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import '../utils/day_math.dart';
import 'error_log_service.dart';

/// What an encrypted diary restore changed.
class DiaryRestoreReport {
  const DiaryRestoreReport({required this.restored, required this.skipped});

  /// Entries inserted or updated, matched by calendar day.
  final int restored;

  /// Malformed or duplicate-day entries left out of the backup.
  final int skipped;

  bool get isClean => skipped == 0;
}

/// Password-based encrypted export/restore for diary entries.
///
/// Diary text is the most private part of the planner. The ordinary JSON
/// backup and LAN sync are already local/authenticated, but a file that leaves
/// the machine is protected here with AES-256-GCM and a key derived from the
/// user's passphrase with PBKDF2-HMAC-SHA256. The passphrase is never stored;
/// losing it means the file cannot be recovered, which the UI says explicitly.
class EncryptedDiaryService {
  EncryptedDiaryService(this._db);

  static const format = 'locus.encrypted-diary';
  static const formatVersion = 1;
  static const defaultIterations = 210000;
  static const maxFileBytes = 25 * 1024 * 1024;
  static const _kdfName = 'PBKDF2-HMAC-SHA256';
  static const _cipherName = 'AES-256-GCM';
  static const _aad = 'locus.encrypted-diary:v1';

  final AppDatabase _db;
  final _uuid = const Uuid();
  final _random = Random.secure();

  /// Serialises and encrypts every diary entry into a small JSON envelope.
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

    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = _deriveKey(passphrase, salt, defaultIterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(_aad)),
        ),
      );
    final ciphertext = cipher.process(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );

    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': formatVersion,
      'created_at': AppClock.now().toIso8601String(),
      'kdf': {
        'algorithm': _kdfName,
        'iterations': defaultIterations,
        'salt': base64Encode(salt),
      },
      'cipher': _cipherName,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(ciphertext),
    });
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

  /// Lets the user choose an encrypted backup. Returns its text, or null when
  /// the picker was cancelled.
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

  /// Decrypts [document] and adds/updates entries by calendar day. Entries
  /// already in the diary that are not in the backup are preserved, so this is
  /// safe to use as a partial recovery.
  Future<DiaryRestoreReport> restoreFromEncrypted({
    required String document,
    required String passphrase,
  }) async {
    final entries = _entriesFromPayload(_decrypt(document, passphrase));
    var skipped = 0;
    final parsed = <_DiaryBackupEntry>[];
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
          _DiaryBackupEntry(
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

    var restored = 0;
    await _db.transaction(() async {
      for (final entry in parsed) {
        final existing = await (_db.select(
          _db.diaryEntries,
        )..where((t) => t.date.equals(entry.day))).getSingleOrNull();
        if (existing == null) {
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
        } else {
          await (_db.update(
            _db.diaryEntries,
          )..where((t) => t.id.equals(existing.id))).write(
            DiaryEntriesCompanion(
              mood: Value(entry.mood),
              content: Value(entry.content),
            ),
          );
        }
        restored++;
      }
    });
    return DiaryRestoreReport(restored: restored, skipped: skipped);
  }

  Map<String, dynamic> _decrypt(String document, String passphrase) {
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(document);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      envelope = decoded;
    } on FormatException {
      throw const FormatException(
        'This is not an encrypted Locus diary backup.',
      );
    }

    if (envelope['format'] != format ||
        envelope['version'] != formatVersion ||
        envelope['cipher'] != _cipherName) {
      throw const FormatException(
        'This is not an encrypted Locus diary backup.',
      );
    }
    final kdf = envelope['kdf'];
    if (kdf is! Map<String, dynamic> || kdf['algorithm'] != _kdfName) {
      throw const FormatException('Unsupported encryption settings.');
    }
    final iterations = kdf['iterations'];
    if (iterations is! int || iterations < 10000 || iterations > 1000000) {
      throw const FormatException('Unsupported encryption settings.');
    }

    final salt = _decodeBase64(kdf['salt']);
    final nonce = _decodeBase64(envelope['nonce']);
    final ciphertext = _decodeBase64(envelope['ciphertext']);
    if (salt.length < 16 || nonce.length != 12 || ciphertext.length <= 16) {
      throw const FormatException('The encrypted diary backup is incomplete.');
    }

    final key = _deriveKey(passphrase, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(_aad)),
        ),
      );

    final Uint8List plaintext;
    try {
      plaintext = cipher.process(ciphertext);
    } on InvalidCipherTextException {
      throw const FormatException(
        'The passphrase is wrong, or the diary backup is damaged.',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'locus.diary-backup' ||
          decoded['version'] != 1) {
        throw const FormatException();
      }
      return decoded;
    } on FormatException {
      throw const FormatException('The diary backup is damaged.');
    }
  }

  List<dynamic> _entriesFromPayload(Map<String, dynamic> payload) {
    final entries = payload['entries'];
    if (entries is! List) {
      throw const FormatException('The diary backup has no entries.');
    }
    return entries;
  }

  Uint8List _decodeBase64(Object? value) {
    if (value is! String) {
      throw const FormatException('The diary backup is incomplete.');
    }
    try {
      return base64Decode(value);
    } catch (_) {
      throw const FormatException('The diary backup is incomplete.');
    }
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

  Uint8List _deriveKey(String passphrase, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}

class _DiaryBackupEntry {
  const _DiaryBackupEntry({
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
