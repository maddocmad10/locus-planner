import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SingleInstanceService {
  static RandomAccessFile? _lockFile;
  // static Directory? _lockDirectory;

  static Future<bool> acquire() async {
    if (_lockFile != null) return false;

    try {
      final directory = await getApplicationSupportDirectory();
        final lockDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}locus_planner',
        );

      if (!await lockDirectory.exists()) {
        await lockDirectory.create(recursive: true);
      }

      final file = File(
        '${lockDirectory.path}${Platform.pathSeparator}locus.lock',
      );

      final raf = await file.open(mode: FileMode.write);

      try {
        await raf.lock(FileLock.exclusive);
      } catch (_) {
        await raf.close();
        return false;
      }

      _lockFile = raf;
    //  _lockDirectory = lockDirectory;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> release() async {
    final file = _lockFile;
    _lockFile = null;
  //  _lockDirectory = null;

    if (file != null) {
      try {
        await file.unlock();
      } catch (_) {
        // The OS may already have released the lock.
      } finally {
        await file.close();
      }
    }
  }
}
