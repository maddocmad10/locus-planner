import 'dart:convert';
import 'dart:typed_data';

/// Thrown when an attachment is rejected by policy. The message is safe to show
/// to the user and never contains file contents.
class AttachmentImportException implements Exception {
  const AttachmentImportException(this.message);

  final String message;

  @override
  String toString() => 'AttachmentImportException: $message';
}

/// Small, closed set of rules shared by import, sync and backup.
class AttachmentRules {
  static const maxFileBytes = 25 * 1024 * 1024;
  static const maxPerItem = 20;
  static const softQuotaBytes = 1024 * 1024 * 1024;
  static const maxImagePixels = 50 * 1000 * 1000;
  static const maxLongEdge = 2048;
  static const thumbnailEdge = 256;
  static const jpegQuality = 85;
  static const thumbnailQuality = 80;
  static const orphanGrace = Duration(days: 7);

  /// Settings key on this device only. Never synced and never included in a
  /// logical backup because it describes local storage behaviour.
  static const keepOriginalSettingKey = 'attachments.keep_original';

  /// Phone download policy: `auto`, `all` or `manual`.
  static const downloadPolicySettingKey = 'attachments.download_policy';
  static const downloadPolicyAuto = 'auto';
  static const downloadPolicyAll = 'all';
  static const downloadPolicyManual = 'manual';
  static const autoDownloadMaxImageBytes = 2 * 1024 * 1024;
  static const phoneCacheCapBytes = 500 * 1024 * 1024;

  static const blockedExtensions = <String>{
    'exe',
    'msi',
    'bat',
    'cmd',
    'ps1',
    'psm1',
    'vbs',
    'vbe',
    'js',
    'jse',
    'wsf',
    'wsh',
    'jar',
    'lnk',
    'scr',
    'apk',
    'appx',
    'msix',
    'dll',
    'com',
    'pif',
    'cpl',
  };

  static const _reservedWindowsNames = <String>{
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// Sanitized display text. The result is never used as a disk path; files on
  /// disk are named from the HMAC of their content hash.
  static String sanitizeDisplayName(String raw) {
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'\.{2,}'), '.');
    name = name.trim();
    if (name.isEmpty) name = 'attachment';

    final dot = name.lastIndexOf('.');
    var base = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    if (_reservedWindowsNames.contains(base.toUpperCase())) {
      base = 'file_$base';
    }
    name = '$base$extension';
    if (name.length > 120) {
      final keepExtension = extension.length <= 16 ? extension : '';
      final baseLimit = 120 - keepExtension.length;
      name = '${name.substring(0, baseLimit)}$keepExtension';
    }
    return name;
  }

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static bool hasBlockedExtension(String name) =>
      blockedExtensions.contains(extensionOf(name));
}

/// Detected media type and a content-derived kind.
class SniffedType {
  const SniffedType({required this.mimeType, required this.kind});

  final String mimeType;

  /// `image` or `file`.
  final String kind;

  bool get isImage => kind == 'image';
}

/// Magic-byte detection. The extension is advisory and never trusted alone.
class AttachmentMime {
  const AttachmentMime._();

  static SniffedType sniff(Uint8List bytes) {
    if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return const SniffedType(mimeType: 'image/png', kind: 'image');
    }
    if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) {
      return const SniffedType(mimeType: 'image/jpeg', kind: 'image');
    }
    if (_asciiAt(bytes, 0, 'GIF87a') || _asciiAt(bytes, 0, 'GIF89a')) {
      return const SniffedType(mimeType: 'image/gif', kind: 'image');
    }
    if (_asciiAt(bytes, 0, 'RIFF') && _asciiAt(bytes, 8, 'WEBP')) {
      return const SniffedType(mimeType: 'image/webp', kind: 'image');
    }
    if (_asciiAt(bytes, 0, '%PDF-')) {
      return const SniffedType(mimeType: 'application/pdf', kind: 'file');
    }
    if (_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04]) ||
        _startsWith(bytes, const [0x50, 0x4B, 0x05, 0x06]) ||
        _startsWith(bytes, const [0x50, 0x4B, 0x07, 0x08])) {
      return const SniffedType(mimeType: 'application/zip', kind: 'file');
    }
    if (_asciiAt(bytes, 4, 'ftyp')) {
      return const SniffedType(mimeType: 'video/mp4', kind: 'file');
    }
    if (_startsWith(bytes, const [0x7F, 0x45, 0x4C, 0x46])) {
      return const SniffedType(
        mimeType: 'application/x-executable',
        kind: 'file',
      );
    }
    if (_asciiAt(bytes, 0, 'MZ')) {
      return const SniffedType(
        mimeType: 'application/vnd.microsoft.portable-executable',
        kind: 'file',
      );
    }
    if (_startsWith(bytes, const [0x1F, 0x8B])) {
      return const SniffedType(mimeType: 'application/gzip', kind: 'file');
    }
    if (_startsWith(bytes, const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
      return const SniffedType(
        mimeType: 'application/x-7z-compressed',
        kind: 'file',
      );
    }
    if (_asciiAt(bytes, 0, 'Rar!')) {
      return const SniffedType(mimeType: 'application/vnd.rar', kind: 'file');
    }
    if (_asciiAt(bytes, 0, '#!')) {
      return const SniffedType(
        mimeType: 'text/x-shellscript',
        kind: 'file',
      );
    }
    if (_looksLikeText(bytes)) {
      return const SniffedType(mimeType: 'text/plain', kind: 'file');
    }
    return const SniffedType(
      mimeType: 'application/octet-stream',
      kind: 'file',
    );
  }

  /// Executables and scripts are refused at import. Even if a file slips in
  /// through a future sync peer, callers must never auto-open it.
  static bool isDangerous(SniffedType type, String fileName) {
    if (AttachmentRules.hasBlockedExtension(fileName)) return true;
    const dangerous = <String>{
      'application/x-executable',
      'application/vnd.microsoft.portable-executable',
      'application/x-msdownload',
      'application/x-msdos-program',
      'application/x-sh',
      'text/x-shellscript',
      'application/x-bat',
      'application/x-powershell',
    };
    return dangerous.contains(type.mimeType);
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  static bool _asciiAt(Uint8List bytes, int offset, String value) {
    if (bytes.length < offset + value.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static bool _looksLikeText(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final sample = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;
    if (sample.contains(0)) return false;
    try {
      utf8.decode(sample);
      return true;
    } on FormatException {
      return false;
    }
  }
}
