import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ErrorLogService {
  const ErrorLogService._();

  static Future<void> log(Object error, StackTrace stack) async {
    try {
      final support = await getApplicationSupportDirectory();
      final logFile = File(
        '${support.path}${Platform.pathSeparator}locus_error.log',
      );
      await logFile.parent.create(recursive: true);
      final entry = utf8.encode(
        '${DateTime.now().toIso8601String()}\n$error\n$stack\n\n',
      );
      const maxLogBytes = 1024 * 1024;
      final existingBytes = await logFile.exists() ? await logFile.length() : 0;
      if (existingBytes + entry.length <= maxLogBytes) {
        await logFile.writeAsBytes(entry, mode: FileMode.append, flush: true);
        return;
      }

      for (var generation = 2; generation >= 1; generation--) {
        final source = File('${logFile.path}.$generation');
        if (!await source.exists()) continue;
        final target = File('${logFile.path}.${generation + 1}');
        if (await target.exists()) await target.delete();
        await source.rename(target.path);
      }
      if (await logFile.exists()) {
        await logFile.rename('${logFile.path}.1');
      }
      await logFile.writeAsBytes(entry, flush: true);
    } catch (_) {
      // Error reporting must never become another failure.
    }
  }
}
