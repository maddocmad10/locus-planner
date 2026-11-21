import 'dart:io';

/// Private-network guard for the LAN sync listener.
///
/// The server still binds anyIPv4 so the Windows firewall prompt behaves as it
/// always has, but every request is checked before authentication. Loopback,
/// RFC1918, CGNAT (opt-in) and IPv6 link-local addresses are accepted.
abstract final class NetworkGuard {
  static bool isAllowed(InternetAddress address, {bool allowCgnat = false}) {
    if (address.isLoopback) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      if (a == 10) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 169 && b == 254) return true;
      if (allowCgnat && a == 100 && b >= 64 && b <= 127) return true;
      return false;
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      // fe80::/10 link-local
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
      // fc00::/7 unique-local, useful on some home networks.
      if ((bytes[0] & 0xfe) == 0xfc) return true;
    }
    return false;
  }
}
