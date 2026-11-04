import 'dart:io';

import '../utils/app_clock.dart';
import 'database_security_errors.dart';

enum DatabaseLockMode { shared, exclusive }

/// Cross-process advisory lock for database lifecycle operations.
///
/// Conversion, rotation, raw restore, replacement and backup snapshots must not
/// overlap. An in-process mutex is not enough because a second application
/// process (or a crash-recovery helper) can open the same database directory.
///
/// The lock is advisory: every lifecycle operation in this application uses
/// this class, and the bounded acquisition timeout turns contention into a
/// clear recovery state instead of an indefinite hang.
class DatabaseLifecycleLock {
  DatabaseLifecycleLock(
    this.file, {
    this.timeout = const Duration(seconds: 10),
    this.retryDelay = const Duration(milliseconds: 50),
  });

  final File file;
  final Duration timeout;
  final Duration retryDelay;

  Future<T> withLock<T>(
    DatabaseLockMode mode,
    Future<T> Function() action, {
    Duration? timeout,
  }) async {
    final handle = await acquire(mode, timeout: timeout);
    try {
      return await action();
    } finally {
      await handle.release();
    }
  }

  Future<DatabaseLifecycleLockHandle> acquire(
    DatabaseLockMode mode, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? this.timeout;
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    final started = AppClock.now();
    while (true) {
      try {
        await handle.lock(
          mode == DatabaseLockMode.exclusive
              ? FileLock.exclusive
              : FileLock.shared,
        );
        return DatabaseLifecycleLockHandle._(handle);
      } on FileSystemException {
        if (AppClock.now().difference(started) >= effectiveTimeout) {
          await handle.close();
          throw DatabaseSecurityException(
            DatabaseSecurityErrorCode.lifecycleBusy,
            'Another database operation is still running. Close the other '
            'window or retry after it finishes.',
          );
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}

class DatabaseLifecycleLockHandle {
  DatabaseLifecycleLockHandle._(this._handle);

  final RandomAccessFile _handle;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } on FileSystemException {
      // Closing the handle releases the OS lock anyway.
    } finally {
      await _handle.close();
    }
  }
}
