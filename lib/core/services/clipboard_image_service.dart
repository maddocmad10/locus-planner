import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Reads an image from the system clipboard.
///
/// Windows reads CF_DIB through user32/kernel32 and converts it to PNG. Android
/// reads a clipboard content URI through a small MethodChannel. Unsupported
/// platforms, an empty clipboard or a non-image clipboard return null.
class ClipboardImageService {
  const ClipboardImageService._();

  static const _channel = MethodChannel('locus_planner/clipboard');

  static Future<Uint8List?> read() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<Uint8List>('readImage');
      }
      if (Platform.isWindows) return _readWindowsClipboard();
    } catch (_) {
      // Clipboard access is best-effort and must never break the dialog.
    }
    return null;
  }

  static Uint8List? _readWindowsClipboard() {
    if (_winIsClipboardFormatAvailable(_cfDib) == 0) return null;
    if (_winOpenClipboard(nullptr) == 0) return null;
    Pointer<Void>? handle;
    Pointer<Uint8>? locked;
    try {
      handle = _winGetClipboardData(_cfDib);
      if (handle == nullptr) return null;
      locked = _winGlobalLock(handle).cast<Uint8>();
      if (locked == nullptr) return null;
      final size = _winGlobalSize(handle);
      if (size < 40) return null;
      return _dibToPng(locked, size);
    } finally {
      if (locked != null && locked != nullptr) _winGlobalUnlock(handle!);
      _winCloseClipboard();
    }
  }

  static Uint8List? _dibToPng(Pointer<Uint8> data, int size) {
    int u16(int offset) => data[offset] | (data[offset + 1] << 8);
    int u32(int offset) =>
        data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
    int i32(int offset) {
      final value = u32(offset);
      return value >= 0x80000000 ? value - 0x100000000 : value;
    }

    final headerSize = u32(0);
    final width = i32(4);
    final rawHeight = i32(8);
    final bitCount = u16(14);
    final compression = u32(16);
    if (headerSize < 40 ||
        width <= 0 ||
        rawHeight == 0 ||
        (bitCount != 24 && bitCount != 32) ||
        compression != 0) {
      return null;
    }
    final height = rawHeight.abs();
    final topDown = rawHeight < 0;
    final bytesPerPixel = bitCount ~/ 8;
    final stride = ((width * bitCount + 31) ~/ 32) * 4;
    final pixelOffset = headerSize;
    if (pixelOffset + stride * height > size) return null;

    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      final sourceY = topDown ? y : height - 1 - y;
      final row = pixelOffset + sourceY * stride;
      for (var x = 0; x < width; x++) {
        final offset = row + x * bytesPerPixel;
        final b = data[offset];
        final g = data[offset + 1];
        final r = data[offset + 2];
        final a = bitCount == 32
            ? (data[offset + 3] == 0 ? 255 : data[offset + 3])
            : 255;
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  static const _cfDib = 8;

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _winIsClipboardFormatAvailable = _user32
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IsClipboardFormatAvailable',
      );
  static final _winOpenClipboard = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('OpenClipboard');
  static final _winCloseClipboard = _user32
      .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
  static final _winGetClipboardData = _user32
      .lookupFunction<
        Pointer<Void> Function(Uint32),
        Pointer<Void> Function(int)
      >('GetClipboardData');
  static final _winGlobalLock = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GlobalLock');
  static final _winGlobalUnlock = _kernel32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('GlobalUnlock');
  static final _winGlobalSize = _kernel32
      .lookupFunction<
        IntPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('GlobalSize');
}
