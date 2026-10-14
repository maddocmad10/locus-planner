import 'dart:io';

class SingleInstanceService {
  static RandomAccessFile? _lockFile;
  static String? _lockPath;

  static Future<bool> acquire() async {
    if (_lockFile != null) return true;

    final dir = await Directory.systemTemp.createTemp('locus_planner');
    _lockPath = '${dir.path}${Platform.pathSeparator}locus.lock';

    try {
      final file = File(_lockPath!);
      final raf = await file.open(mode: FileMode.write);
      final locked = await raf.lock(FileLock.exclusive).then((_) => true).catchError((_) => false);

      if (!locked) {
        await raf.close();
        return false;
      }

      _lockFile = raf;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> release() async {
    final file = _lockFile;
    _lockFile = null;
    if (file != null) {
      try {
        await file.unlock();
      } finally {
        await file.close();
      }
    }
  }
}
