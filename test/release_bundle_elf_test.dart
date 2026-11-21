import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_release_bundle.dart';

List<int> elf64(List<int> alignments) {
  final bytes = List<int>.filled(64 + alignments.length * 56, 0);
  bytes[0] = 0x7f;
  bytes[1] = 0x45;
  bytes[2] = 0x4c;
  bytes[3] = 0x46;
  bytes[4] = 2; // ELF64
  bytes[5] = 1; // little endian
  void u16(int offset, int value) {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >> 8) & 0xff;
  }

  void u32(int offset, int value) {
    for (var i = 0; i < 4; i++) {
      bytes[offset + i] = (value >> (8 * i)) & 0xff;
    }
  }

  void u64(int offset, int value) {
    for (var i = 0; i < 8; i++) {
      bytes[offset + i] = (value >> (8 * i)) & 0xff;
    }
  }

  u64(32, 64); // e_phoff
  u16(54, 56); // e_phentsize
  u16(56, alignments.length); // e_phnum
  for (var index = 0; index < alignments.length; index++) {
    final offset = 64 + index * 56;
    u32(offset, 1); // PT_LOAD
    u64(offset + 48, alignments[index]);
  }
  return bytes;
}

void main() {
  test('all 16 KB PT_LOAD segments pass', () {
    expect(verifyElfAlignmentBytes(elf64([16384, 16384])), isNull);
  });

  test('mixed 4 KB and 16 KB segments fail on the small segment', () {
    final error = verifyElfAlignmentBytes(elf64([4096, 16384]));
    expect(error, contains('16384'));
  });

  test('truncated, absent and malformed objects fail closed', () {
    expect(verifyElfAlignmentBytes(List<int>.filled(10, 0)), isNotNull);
    expect(verifyElfAlignmentBytes(List<int>.filled(64, 0)), isNotNull);
    expect(verifyElfAlignmentBytes(elf64(const [])), isNotNull);
  });
}
