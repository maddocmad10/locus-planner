import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'error_log_service.dart';

enum SingleInstanceResult {
  acquired,
  alreadyRunning,
  checkFailed,
}

/// Coordinates a single running Locus instance and asks an existing instance
/// to show its window when a second launch is attempted.
class SingleInstanceService {
  SingleInstanceService();

  RandomAccessFile? _lockFile;
  ServerSocket? _activationServer;
  File? _activationPortFile;
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
      final lockDirectory = directory ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}locus_planner',
          );
      await lockDirectory.create(recursive: true);
      final lockPath =
          '${lockDirectory.path}${Platform.pathSeparator}locus.lock';
      final lock = File(lockPath);
      lockFile = lock;
      final raf = await lock.open(mode: FileMode.append);

      try {
        await raf.lock(FileLock.exclusive);
      } on Object catch (error, stack) {
        await raf.close();
        if (await _notifyExistingInstance(lock)) {
          return SingleInstanceResult.alreadyRunning;
        }
        await ErrorLogService.log(error, stack);
        return SingleInstanceResult.checkFailed;
      }

      _lockFile = raf;
      try {
        _activationServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
          shared: false,
        );
        _activationServer!.listen(_handleActivationSocket);
        final activationPortFile = File('${lock.path}.port');
        _activationPortFile = activationPortFile;
        await activationPortFile.writeAsString(
          '${_activationServer!.port}\n',
          flush: true,
        );
      } catch (error, stack) {
        // The file lock still protects against a concurrent launch even if
        // the optional activation channel cannot be created.
        await ErrorLogService.log(error, stack);
        await _activationServer?.close();
        _activationServer = null;
        final activationPortFile = _activationPortFile;
        _activationPortFile = null;
        if (activationPortFile != null) {
          try {
            await activationPortFile.delete();
          } catch (_) {
            // Stale endpoint metadata is harmless; the next owner overwrites it.
          }
        }
      }
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

  Future<bool> _notifyExistingInstance(File lockFile) async {
    // The owner writes its activation port immediately after acquiring the
    // lock. Retry briefly to cover the small interval between those actions.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        // Keep activation metadata outside the OS-locked file: Windows can
        // deny reads of the lock file while another process owns its lock.
        final portFile = File('${lockFile.path}.port');
        final contents = await portFile.readAsString();
        final port = int.tryParse(contents.trim());
        if (port != null && port > 0 && port <= 65535) {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(milliseconds: 250),
          );
          socket.write('activate');
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
    socket.listen(
      request.add,
      onError: (Object error, StackTrace stack) {
        unawaited(ErrorLogService.log(error, stack));
        socket.destroy();
      },
      onDone: () {
        final command = utf8.decode(request.takeBytes(), allowMalformed: true);
        if (command.contains('activate')) {
          final callback = _onSecondInstance;
          if (callback == null) {
            _activationPending = true;
          } else {
            unawaited(_runActivation(callback));
          }
        }
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  Future<void> _runActivation(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
    }
  }

  Future<void> release() async {
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
