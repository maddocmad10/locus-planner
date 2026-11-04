import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Win32 `DATA_BLOB` / `CRYPT_INTEGER_BLOB`.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative =
    Int32 Function(
      Pointer<_DataBlob> pDataIn,
      Pointer<Utf16> szDataDescr,
      Pointer<_DataBlob> pOptionalEntropy,
      Pointer<Void> pvReserved,
      Pointer<Void> pPromptStruct,
      Uint32 dwFlags,
      Pointer<_DataBlob> pDataOut,
    );
typedef _CryptProtectDataDart =
    int Function(
      Pointer<_DataBlob> pDataIn,
      Pointer<Utf16> szDataDescr,
      Pointer<_DataBlob> pOptionalEntropy,
      Pointer<Void> pvReserved,
      Pointer<Void> pPromptStruct,
      int dwFlags,
      Pointer<_DataBlob> pDataOut,
    );

typedef _CryptUnprotectDataNative =
    Int32 Function(
      Pointer<_DataBlob> pDataIn,
      Pointer<Pointer<Utf16>> ppszDataDescr,
      Pointer<_DataBlob> pOptionalEntropy,
      Pointer<Void> pvReserved,
      Pointer<Void> pPromptStruct,
      Uint32 dwFlags,
      Pointer<_DataBlob> pDataOut,
    );
typedef _CryptUnprotectDataDart =
    int Function(
      Pointer<_DataBlob> pDataIn,
      Pointer<Pointer<Utf16>> ppszDataDescr,
      Pointer<_DataBlob> pOptionalEntropy,
      Pointer<Void> pvReserved,
      Pointer<Void> pPromptStruct,
      int dwFlags,
      Pointer<_DataBlob> pDataOut,
    );

typedef _LocalFreeNative = IntPtr Function(Pointer<Void>);
typedef _LocalFreeDart = int Function(Pointer<Void>);

/// Minimal DPAPI wrapper for the database key store.
///
/// This deliberately does **not** delete the backing file when decryption
/// fails: a missing key is a recovery condition, and preserving the blob keeps
/// the evidence available for diagnosis. Windows-only; callers guard with
/// `Platform.isWindows`.
abstract final class WindowsDpapiStore {
  static const _uiForbidden = 0x1;

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _protect = _crypt32
      .lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
        'CryptProtectData',
      );
  static final _unprotect = _crypt32
      .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
        'CryptUnprotectData',
      );
  static final _localFree = _kernel32
      .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');

  static Uint8List protect(String plaintext) =>
      _call(utf8.encode(plaintext), protect: true);

  static String unprotect(Uint8List ciphertext) =>
      utf8.decode(_call(ciphertext, protect: false));

  static Uint8List _call(List<int> data, {required bool protect}) {
    return using<Uint8List>((alloc) {
      final inputBytes = alloc<Uint8>(data.length);
      inputBytes.asTypedList(data.length).setAll(0, data);
      final input = alloc<_DataBlob>()
        ..ref.cbData = data.length
        ..ref.pbData = inputBytes;

      final output = alloc<_DataBlob>();
      final result = protect
          ? _protect(
              input,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _uiForbidden,
              output,
            )
          : _unprotect(
              input,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _uiForbidden,
              output,
            );
      if (result == 0) {
        throw WindowsException(
          _getLastError(),
          message: protect
              ? 'CryptProtectData failed'
              : 'CryptUnprotectData failed',
        );
      }
      try {
        if (output.ref.pbData == nullptr || output.ref.cbData == 0) {
          return Uint8List(0);
        }
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        if (output.ref.pbData != nullptr) {
          _localFree(output.ref.pbData.cast<Void>());
        }
      }
    });
  }

  static final _getLastError = _kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
}

class WindowsException implements Exception {
  const WindowsException(this.errorCode, {this.message});

  final int errorCode;
  final String? message;

  @override
  String toString() => message == null
      ? 'Windows error $errorCode'
      : '$message (Windows error $errorCode)';
}
