import 'dart:convert';

/// One sealed attachment file carried by a raw recovery package.
///
/// [sha256] is the hash of the plaintext bytes, [sealedSha256] is the hash of
/// the stored (already encrypted) file. The archive path is inside the package
/// and is validated against the fixed attachment layout.
class RecoveryPackageAttachment {
  const RecoveryPackageAttachment({
    required this.archivePath,
    required this.sha256,
    required this.sealedSha256,
    required this.bytes,
    this.thumbnail = false,
  });

  final String archivePath;
  final String sha256;
  final String sealedSha256;
  final int bytes;
  final bool thumbnail;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': archivePath,
    'sha256': sha256,
    'sealedSha256': sealedSha256,
    'bytes': bytes,
    'thumbnail': thumbnail,
  };

  static RecoveryPackageAttachment decode(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('An attachment entry must be an object.');
    }
    final path = value['path'];
    final sha = value['sha256'];
    final sealed = value['sealedSha256'];
    final bytes = value['bytes'];
    if (path is! String ||
        sha is! String ||
        sealed is! String ||
        bytes is! int ||
        bytes < 0) {
      throw const FormatException('An attachment entry is incomplete.');
    }
    return RecoveryPackageAttachment(
      archivePath: path,
      sha256: sha,
      sealedSha256: sealed,
      bytes: bytes,
      thumbnail: value['thumbnail'] == true,
    );
  }
}

/// Non-secret manifest carried by a `.locusrecovery` package.
///
/// The manifest is not a security boundary: every field is re-derived and
/// compared with the encrypted database identity and the recovery envelope
/// before a restore is allowed.
class RecoveryPackageManifest {
  const RecoveryPackageManifest({
    required this.createdAt,
    required this.databaseId,
    required this.keyId,
    required this.keyGeneration,
    required this.cipherProfileId,
    required this.databaseFile,
    required this.databaseSha256,
    required this.databaseBytes,
    required this.schemaVersion,
    required this.attachmentsIncluded,
    this.attachments = const [],
    this.skippedAttachmentCount = 0,
  });

  static const format = 'locus.raw.recovery';
  static const formatVersion = 1;
  static const databaseEntry = 'database/locus_planner.db';

  final DateTime createdAt;
  final String databaseId;
  final String keyId;
  final int keyGeneration;
  final String cipherProfileId;
  final String databaseFile;
  final String databaseSha256;
  final int databaseBytes;
  final int schemaVersion;
  final bool attachmentsIncluded;
  final List<RecoveryPackageAttachment> attachments;
  final int skippedAttachmentCount;

  int get attachmentFileCount => attachments.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'formatVersion': formatVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'databaseId': databaseId,
    'keyId': keyId,
    'keyGeneration': keyGeneration,
    'cipherProfileId': cipherProfileId,
    'databaseFile': databaseFile,
    'databaseSha256': databaseSha256,
    'databaseBytes': databaseBytes,
    'schemaVersion': schemaVersion,
    'attachmentsIncluded': attachmentsIncluded,
    'attachments': attachments.map((entry) => entry.toJson()).toList(),
    'skippedAttachmentCount': skippedAttachmentCount,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static RecoveryPackageManifest decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('The recovery manifest is not valid JSON.', error);
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['formatVersion'] != formatVersion) {
      throw const FormatException('This is not a supported recovery package.');
    }
    final createdAt = _date(decoded, 'createdAt');
    final databaseId = _string(decoded, 'databaseId');
    final keyId = _string(decoded, 'keyId');
    final cipherProfileId = _string(decoded, 'cipherProfileId');
    final databaseFile = _string(decoded, 'databaseFile');
    final databaseSha256 = _checksum(decoded, 'databaseSha256');
    final keyGeneration = _int(decoded, 'keyGeneration');
    final databaseBytes = _int(decoded, 'databaseBytes');
    final schemaVersion = _int(decoded, 'schemaVersion');
    if (keyGeneration < 1 ||
        keyGeneration > 1000000 ||
        databaseBytes <= 0 ||
        schemaVersion < 1 ||
        schemaVersion > 1000000) {
      throw const FormatException('The recovery manifest has invalid values.');
    }
    if (databaseFile != 'locus_planner.db') {
      throw const FormatException(
        'The recovery package uses an unsupported database file name.',
      );
    }
    final attachmentsIncluded = decoded['attachmentsIncluded'] == true;
    final rawAttachments = decoded['attachments'];
    if (rawAttachments is! List) {
      throw const FormatException('The recovery manifest has no file list.');
    }
    if (rawAttachments.length > 100000) {
      throw const FormatException('The recovery package has too many files.');
    }
    final seen = <String>{};
    final attachments = <RecoveryPackageAttachment>[];
    for (final raw in rawAttachments) {
      final entry = RecoveryPackageAttachment.decode(raw);
      if (!_validAttachmentPath(entry.archivePath)) {
        throw const FormatException(
          'The recovery package contains an unsafe file path.',
        );
      }
      if (!seen.add(entry.archivePath)) {
        throw const FormatException(
          'The recovery package contains a duplicate file path.',
        );
      }
      if (!_checksumPattern.hasMatch(entry.sealedSha256)) {
        throw const FormatException(
          'The recovery package contains an invalid checksum.',
        );
      }
      if (entry.thumbnail) {
        if (entry.sha256.isNotEmpty) {
          throw const FormatException(
            'A thumbnail entry must not claim a plaintext hash.',
          );
        }
      } else if (!_checksumPattern.hasMatch(entry.sha256)) {
        throw const FormatException(
          'The recovery package contains an invalid content hash.',
        );
      }
      attachments.add(entry);
    }
    if (!attachmentsIncluded && attachments.isNotEmpty) {
      throw const FormatException(
        'The recovery manifest lists attachments while attachments are off.',
      );
    }
    final skipped = decoded['skippedAttachmentCount'];
    return RecoveryPackageManifest(
      createdAt: createdAt,
      databaseId: databaseId,
      keyId: keyId,
      keyGeneration: keyGeneration,
      cipherProfileId: cipherProfileId,
      databaseFile: databaseFile,
      databaseSha256: databaseSha256,
      databaseBytes: databaseBytes,
      schemaVersion: schemaVersion,
      attachmentsIncluded: attachmentsIncluded,
      attachments: attachments,
      skippedAttachmentCount: skipped is int && skipped >= 0 ? skipped : 0,
    );
  }

  static final _checksumPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _attachmentPathPattern = RegExp(
    r'^attachments/(ab/[0-9a-f]{64}|thumbs/[0-9a-f]{64}\.t)$',
  );

  static bool _validAttachmentPath(String value) =>
      !value.contains(r'\') && _attachmentPathPattern.hasMatch(value);

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty || value.length > 512) {
      throw FormatException('The recovery manifest is missing "$key".');
    }
    return value;
  }

  static String _checksum(Map<String, dynamic> json, String key) {
    final value = _string(json, key);
    if (!_checksumPattern.hasMatch(value)) {
      throw FormatException('The recovery manifest has an invalid "$key".');
    }
    return value;
  }

  static int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('The recovery manifest is missing "$key".');
    }
    return value;
  }

  static DateTime _date(Map<String, dynamic> json, String key) {
    final value = _string(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('The recovery manifest has an invalid "$key".');
    }
    return parsed;
  }
}
