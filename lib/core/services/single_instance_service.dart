import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'error_log_service.dart';

enum SingleInstanceResult { acquired, alreadyRunning, checkFailed }

/// Takes the exclusive file lock. Replaceable in tests, because the operating
/// system can't be made to refuse a lock on demand (and POSIX locks are per
/// process, so a second lock in the same process would simply succeed).
typedef FileLockFunction = Future<void> Function(RandomAccessFile file);

/// Coordinates a single running Locus instance and asks an existing instance
/// to show its window when a second launch is attempted.
///
/// The exclusive lock on `locus.lock` is what guarantees there is only one
/// copy. The loopback activation channel is a courtesy on top of it: it lets a
/// second launch bring the first window forward, and nothing depends on it.
class SingleInstanceService {
  SingleInstanceService({
    FileLockFunction? lock,
    Duration activationReadTimeout = const Duration(seconds: 2),
  }) : _lock = lock ?? _lockExclusively,
       _activationReadTimeout = activationReadTimeout;
    

  static Future<void> _lockExclusively(RandomAccessFile file) =>
      file.lock(FileLock.exclusive);

  /// OS error codes meaning "another process holds the lock": Windows
  /// ERROR_SHARING_VIOLATION (32) and ERROR_LOCK_VIOLATION (33), and POSIX
  /// EAGAIN/EWOULDBLOCK (11 on Linux, 35 on macOS) and EACCES (13).
  ///
  /// Other lock failures (a file system without locking, say) are deliberately
  /// not in this list: they say nothing about another instance.
  static const lockHeldErrorCodes = <int>{11, 13, 32, 33, 35};

  static bool isLockHeldError(Object error) =>
      error is FileSystemException &&
      error.osError != null &&
      lockHeldErrorCodes.contains(error.osError!.errorCode);

  /// An activation request is `activate <token>`; anything longer than this is
  /// not one, and is dropped without being read further.
  static const maxActivationBytes = 128;

  final FileLockFunction _lock;
  final Duration _activationReadTimeout;

  RandomAccessFile? _lockFile;
  ServerSocket? _activationServer;
  File? _activationPortFile;
  String? _activationToken;
  Future<void> Function()? _onSecondInstance;
  bool _activationPending = false;

  set onSecondInstance(Future<void> Function()? callback) {
    _onSecondInstance = callback;
    if (callback != null && _activationPending) {
      _activationPending = false;
      unawaited(_runActivation(callback));
    }
  }

  Future<SingleInstanceResult> acquire({Directory? directory}) async {
    if (_lockFile != null) return SingleInstanceResult.acquired;

    File? lockFile;
    try {
      final lockDirectory =
          directory ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}locus_planner',
          );
      await lockDirectory.create(recursive: true);
      final file = File(
        '${lockDirectory.path}${Platform.pathSeparator}locus.lock',
      );
      lockFile = file;
      final raf = await file.open(mode: FileMode.append);

      try {
        await _lock(raf);
      } on Object catch (error, stack) {
        await raf.close();
        if (isLockHeldError(error)) {
          // Another process certainly holds the lock. Asking it to show its
          // window is a courtesy and must not decide the outcome: otherwise a
          // second copy would start whenever the first could not open its
          // activation channel. A short wait is enough for the courtesy.
          await _notifyExistingInstance(file, attempts: 3);
          return SingleInstanceResult.alreadyRunning;
        }
        // Not a plain "lock is taken" error. If an instance answers, that is
        // still proof there is one; otherwise the check is inconclusive.
        if (await _notifyExistingInstance(file)) {
          return SingleInstanceResult.alreadyRunning;
        }
        await ErrorLogService.log(error, stack);
        return SingleInstanceResult.checkFailed;
      }

      _lockFile = raf;
      await _openActivationChannel(file);
      return SingleInstanceResult.acquired;
    } catch (error, stack) {
      // Opening the file itself can fail when another process has it open.
      // If its activation endpoint responds, this is a second launch; if not,
      // treat the lock status as unknown and let the planner start.
      if (lockFile != null && await _notifyExistingInstance(lockFile)) {
        return SingleInstanceResult.alreadyRunning;
      }
      await ErrorLogService.log(error, stack);
      return SingleInstanceResult.checkFailed;
    }
  }

  Future<void> _openActivationChannel(File lockFile) async {
    try {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      _activationServer = server;
      server.listen(_handleActivationSocket);

      // The token proves a request comes from a process that can read this
      // user's data folder, not from any program that finds the port.
      final token = _newToken();
      _activationToken = token;
      final portFile = File('${lockFile.path}.port');
      _activationPortFile = portFile;
      await portFile.writeAsString('${server.port}\n$token\n', flush: true);
    } catch (error, stack) {
      // The file lock still protects against a concurrent launch even if the
      // optional activation channel cannot be created.
      await ErrorLogService.log(error, stack);
      await _activationServer?.close();
      _activationServer = null;
      _activationToken = null;
      final portFile = _activationPortFile;
      _activationPortFile = null;
      if (portFile != null) {
        try {
          await portFile.delete();
        } catch (_) {
          // Stale endpoint metadata is harmless; the next owner overwrites it.
        }
      }
    }
  }

  static String _newToken() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<bool> _notifyExistingInstance(
    File lockFile, {
    int attempts = 5,
  }) async {
    // The owner writes its activation port immediately after acquiring the
    // lock. Retry briefly to cover the small interval between those actions.
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        // Keep activation metadata outside the OS-locked file: Windows can
        // deny reads of the lock file while another process owns its lock.
        final portFile = File('${lockFile.path}.port');
        final lines = (await portFile.readAsString()).trim().split('\n');
        final port = int.tryParse(lines.first.trim());
        // An instance from before tokens existed wrote only the port.
        final token = lines.length > 1 ? lines[1].trim() : '';
        if (port != null && port > 0 && port <= 65535) {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(milliseconds: 250),
          );
          socket.write(token.isEmpty ? 'activate' : 'activate $token');
          await socket.flush();
          await socket.close();
          return true;
        }
      } catch (_) {
        // The owner may still be starting; retry before declaring the check
        // inconclusive.
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  void _handleActivationSocket(Socket socket) {
    final request = BytesBuilder(copy: false);
    var rejected = false;

    // A client that connects and goes quiet must not hold the connection open.
    final timeout = Timer(_activationReadTimeout, socket.destroy);

    void finish() {
      timeout.cancel();
      socket.destroy();
    }

    socket.listen(
      (chunk) {
        if (rejected) return;
        request.add(chunk);
        if (request.length > maxActivationBytes) {
          // Not an activation request: stop reading instead of buffering
          // whatever the client sends.
          rejected = true;
          request.clear();
          finish();
        }
      },
      onError: (Object error, StackTrace stack) {
        unawaited(ErrorLogService.log(error, stack));
        finish();
      },
      onDone: () {
        final command = utf8.decode(request.takeBytes(), allowMalformed: true);
        if (!rejected && _isAuthorizedActivation(command)) {
          final callback = _onSecondInstance;
          if (callback == null) {
            _activationPending = true;
          } else {
            unawaited(_runActivation(callback));
          }
        }
        finish();
      },
      cancelOnError: true,
    );
  }

  bool _isAuthorizedActivation(String command) {
    final token = _activationToken;
    if (token == null) return false;
    final parts = command.trim().split(RegExp(r'\s+'));
    if (parts.length != 2 || parts[0] != 'activate') return false;
    return _constantTimeEquals(parts[1], token);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _runActivation(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
    }
  }

  Future<void> release() async {
    _activationToken = null;
    final server = _activationServer;
    _activationServer = null;
    if (server != null) {
      await server.close();
    }

    final activationPortFile = _activationPortFile;
    _activationPortFile = null;
    if (activationPortFile != null) {
      try {
        await activationPortFile.delete();
      } catch (_) {
        // The endpoint metadata may already have been removed.
      }
    }

    final file = _lockFile;
    _lockFile = null;
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
