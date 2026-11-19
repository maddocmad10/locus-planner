import 'dart:convert';
import 'dart:io';

/// Fails when a tracked text file is not valid UTF-8 or contains the most
/// common double-encoding signatures (for example a double-encoded middle
/// dot instead of the real punctuation character).
///
/// Deliberately narrow: it only flags byte sequences that are almost certainly
/// mojibake, so ordinary accented text and emoji are not rejected.
void main(List<String> arguments) {
  final roots = arguments.isEmpty
      ? const ['lib', 'test', 'docs', 'tool', '.github']
      : arguments;
  final extensions = <String>{
    '.dart',
    '.md',
    '.yml',
    '.yaml',
    '.kt',
    '.kts',
    '.xml',
    '.json',
    '.iss',
  };
  final suspicious = RegExp(
    '[\u00C2\u00C3][\u0080-\u00BF]|'
    '\u00E2[\u20AC\u0080-\u00BF\u2018-\u201D\u2020-\u203A]|'
    '\uFFFD|\u00EF\u00BF\u00BD',
  );
  var failures = 0;
  final files = <File>[];
  for (final root in roots) {
    final entity = FileSystemEntity.typeSync(root);
    if (entity == FileSystemEntityType.file) {
      files.add(File(root));
      continue;
    }
    if (entity != FileSystemEntityType.directory) continue;
    for (final child in Directory(root).listSync(recursive: true)) {
      if (child is File && _isTextFile(child.path, extensions)) {
        files.add(child);
      }
    }
  }

  for (final file in files) {
    final bytes = file.readAsBytesSync();
    if (_hasUtf8Bom(bytes)) {
      _fail(file.path, 1, 'file starts with a UTF-8 BOM');
      failures++;
      continue;
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      _fail(file.path, 1, 'file is not valid UTF-8');
      failures++;
      continue;
    }
    var line = 1;
    for (final match in suspicious.allMatches(text)) {
      line += '\n'.allMatches(text.substring(0, match.start)).length;
      final before = text.substring(0, match.start);
      final lineStart = before.lastIndexOf('\n') + 1;
      final lineEnd = text.indexOf('\n', match.end);
      final snippet = text
          .substring(lineStart, lineEnd < 0 ? text.length : lineEnd)
          .trim();
      _fail(file.path, line, 'possible mojibake: $snippet');
      failures++;
      line = 1;
    }
  }

  if (failures > 0) {
    stderr.writeln(
      '\nEncoding check failed with $failures problem(s). '
      'Re-save the files as UTF-8 (without BOM) and repair double-encoded text.',
    );
    exitCode = 1;
  } else {
    stdout.writeln('Encoding check passed for ${files.length} text files.');
  }
}

bool _isTextFile(String path, Set<String> extensions) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.g.dart')) return false;
  if (lower.contains(
    '${Platform.pathSeparator}build${Platform.pathSeparator}',
  )) {
    return false;
  }
  if (lower.contains(
    '${Platform.pathSeparator}generated_migrations${Platform.pathSeparator}',
  )) {
    return false;
  }
  return extensions.any(lower.endsWith);
}

bool _hasUtf8Bom(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xEF &&
    bytes[1] == 0xBB &&
    bytes[2] == 0xBF;

void _fail(String path, int line, String message) {
  stderr.writeln('$path:$line: $message');
}
