import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/network_guard.dart';

void main() {
  test('allows private, loopback and link-local addresses', () {
    for (final address in [
      '127.0.0.1',
      '10.0.0.5',
      '172.16.4.2',
      '172.31.255.1',
      '192.168.1.20',
      '169.254.10.1',
      '::1',
      'fe80::1',
      'fd00::1',
    ]) {
      expect(
        NetworkGuard.isAllowed(InternetAddress(address)),
        isTrue,
        reason: address,
      );
    }
  });

  test('blocks public addresses and CGNAT unless opted in', () {
    expect(NetworkGuard.isAllowed(InternetAddress('8.8.8.8')), isFalse);
    expect(NetworkGuard.isAllowed(InternetAddress('172.32.0.1')), isFalse);
    expect(NetworkGuard.isAllowed(InternetAddress('100.64.0.1')), isFalse);
    expect(
      NetworkGuard.isAllowed(InternetAddress('100.64.0.1'), allowCgnat: true),
      isTrue,
    );
  });
}
