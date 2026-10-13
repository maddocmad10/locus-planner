import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class SingleInstanceService {
  static int? _mutexHandle;

  static const String _mutexName = 'LocusPlanner.SingleInstance';

  static bool acquire() {
    if (!Platform.isWindows) {
      return true;
    }

    final kernel32 = DynamicLibrary.open('kernel32.dll');

    final createMutex = kernel32.lookupFunction<
        IntPtr Function(
          Pointer<Void>,
          Int32,
          Pointer<Utf16>,
        ),
        int Function(
          Pointer<Void>,
          int,
          Pointer<Utf16>,
        )>('CreateMutexW');

    final getLastError = kernel32.lookupFunction<
        Uint32 Function(),
        int Function()>('GetLastError');

    final name = _mutexName.toNativeUtf16();

    try {
      _mutexHandle = createMutex(
        nullptr,
        0,
        name,
      );

      if (_mutexHandle == 0) {
        return false;
      }

      final error = getLastError();

      // ERROR_ALREADY_EXISTS
      if (error == 183) {
        release();
        return false;
      }

      return true;
    } finally {
      calloc.free(name);
    }
  }

  static void release() {
    if (_mutexHandle == null || _mutexHandle == 0) {
      return;
    }

    final kernel32 = DynamicLibrary.open('kernel32.dll');

    final closeHandle = kernel32.lookupFunction<
        Int32 Function(IntPtr),
        int Function(int)>('CloseHandle');

    closeHandle(_mutexHandle!);
    _mutexHandle = null;
  }
}