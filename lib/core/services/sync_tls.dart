import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../db/app_database.dart';

/// SHA-256 of a DER-encoded certificate as 64 lowercase hex characters. This
/// is what a phone pins when it pairs with a desktop.
String certificateFingerprint(List<int> der) => sha256.convert(der).toString();

/// Accepts a fingerprint typed or scanned in any common notation (upper or
/// lower case, with spaces or colons) and returns the canonical 64 lowercase
/// hex characters, or null if it is not a SHA-256 fingerprint.
String? normalizeFingerprint(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(cleaned) ? cleaned : null;
}

/// The first 96 bits of a fingerprint in groups of four, for people to compare
/// on two screens, for example `CE08 0BB6 AE3E 1BDD 2DF3 0863`.
String shortSyncFingerprint(String fingerprint) {
  final length = fingerprint.length < 24 ? fingerprint.length : 24;
  final head = fingerprint.substring(0, length).toUpperCase();
  return [
    for (var i = 0; i < head.length; i += 4)
      head.substring(i, i + 4 > head.length ? head.length : i + 4),
  ].join(' ');
}

/// Where the desktop keeps its TLS private key. Production uses the operating
/// system's protected storage (on Windows, tied to the signed-in user account),
/// so copying the database file, or a cloud-synced AppData folder, does not
/// copy the key with it. Tests substitute an in-memory store.
abstract interface class SyncSecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureSyncSecretStore implements SyncSecretStore {
  const SecureSyncSecretStore();

  static const _privateKeyKey = 'locus.sync.tls_private_key';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _privateKeyKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _privateKeyKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _privateKeyKey);
}

/// The desktop's self-signed TLS certificate and private key.
///
/// Phones do not trust it through any certificate authority. They pin its
/// [fingerprint], which the desktop shows as a QR code next to the pairing
/// code, so a phone only ever talks to the desktop it was paired with.
class SyncTlsIdentity {
  SyncTlsIdentity({required this.certificatePem, required this.privateKeyPem});

  final String certificatePem;
  final String privateKeyPem;

  late final String fingerprint = certificateFingerprint(
    _derFromPem(certificatePem),
  );

  SecurityContext toSecurityContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  /// Creates a new certificate valid for ten years. Generating an RSA key in
  /// pure Dart takes a few seconds, so it runs on another isolate.
  static Future<SyncTlsIdentity> generate() async {
    final (certificate, privateKey) = await Isolate.run(_generatePems);
    return SyncTlsIdentity(
      certificatePem: certificate,
      privateKeyPem: privateKey,
    );
  }

  /// Returns the stored identity, creating and storing one the first time. It
  /// is reused on every start, so the fingerprint stays the same across
  /// restarts and address changes.
  ///
  /// The certificate is public and lives in the database settings. The private
  /// key lives in [keyStore]. A key that an earlier version left in the
  /// database is moved to [keyStore] the first time it is loaded, so existing
  /// phones stay paired. If [keyStore] cannot be used (for example the
  /// system's credential vault is unavailable), the key stays in the database
  /// so sync keeps working, and a note is written to stderr. The settings are
  /// transient, so they are never written to backups and a restore cannot
  /// bring an old identity back.
  static Future<SyncTlsIdentity> loadOrCreate(
    AppDatabase db, {
    SyncSecretStore keyStore = const SecureSyncSecretStore(),
  }) async {
    final certificate = await db.getSetting(
      AppDatabase.syncTlsCertificateSettingKey,
    );
    final privateKey = await _loadPrivateKey(db, keyStore);
    if (certificate != null && privateKey != null) {
      final stored = SyncTlsIdentity(
        certificatePem: certificate,
        privateKeyPem: privateKey,
      );
      try {
        stored.toSecurityContext();
        return stored;
      } on TlsException {
        // Unreadable (for example a damaged setting): make a new one. Phones
        // will have to pair again.
      }
    }
    final created = await generate();
    await db.setSetting(
      AppDatabase.syncTlsCertificateSettingKey,
      created.certificatePem,
    );
    await _storePrivateKey(db, keyStore, created.privateKeyPem);
    return created;
  }

  /// Finds the private key: first in [keyStore], then in the database, where
  /// versions before the key moved kept it. A key found only in the database
  /// is moved across.
  static Future<String?> _loadPrivateKey(
    AppDatabase db,
    SyncSecretStore keyStore,
  ) async {
    String? stored;
    try {
      stored = await keyStore.read();
    } catch (error) {
      stderr.writeln('LAN sync: secure key storage unavailable: $error');
    }
    final legacy = await db.getSetting(AppDatabase.syncTlsPrivateKeySettingKey);
    if (stored != null && stored.isNotEmpty) {
      // The protected copy is authoritative; make sure no plaintext copy stays.
      if (legacy != null) {
        await db.deleteSetting(AppDatabase.syncTlsPrivateKeySettingKey);
      }
      return stored;
    }
    if (legacy == null) return null;
    await _storePrivateKey(db, keyStore, legacy);
    return legacy;
  }

  /// Saves [pem] in [keyStore] and removes any copy from the database. If the
  /// store fails, the key is kept in the database instead so the server can
  /// still start.
  static Future<void> _storePrivateKey(
    AppDatabase db,
    SyncSecretStore keyStore,
    String pem,
  ) async {
    try {
      await keyStore.write(pem);
      // Read it back: some vaults accept a write and lose it.
      if (await keyStore.read() == pem) {
        await db.deleteSetting(AppDatabase.syncTlsPrivateKeySettingKey);
        return;
      }
    } catch (error) {
      stderr.writeln('LAN sync: could not use secure key storage: $error');
    }
    await db.setSetting(AppDatabase.syncTlsPrivateKeySettingKey, pem);
  }
}

(String, String) _generatePems() {
  // basic_utils returns the key pair untyped but its other functions want RSA
  // keys. Left dynamic so no direct dependency on pointycastle is needed; the
  // runtime types are RSAPublicKey and RSAPrivateKey.
  final dynamic pair = CryptoUtils.generateRSAKeyPair();
  final csr = X509Utils.generateRsaCsrPem(
    {'CN': 'Locus Planner'},
    pair.privateKey,
    pair.publicKey,
  );
  final certificate = X509Utils.generateSelfSignedCertificate(
    pair.privateKey,
    csr,
    3650,
  );
  return (certificate, CryptoUtils.encodeRSAPrivateKeyToPem(pair.privateKey));
}

List<int> _derFromPem(String pem) {
  final body = pem
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

/// An HTTP client that trusts exactly one certificate. No system or built-in
/// root is trusted, so a certificate from any authority, including a valid
/// one, is rejected unless it has the pinned fingerprint.
HttpClient pinnedSyncHttpClient(String pinnedFingerprint) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 8);
  client.badCertificateCallback = (certificate, host, port) =>
      certificateFingerprint(certificate.der) == pinnedFingerprint;
  return client;
}

/// Connects to a desktop and returns the fingerprint of the certificate it
/// presents, without sending any data. The phone shows the result so the user
/// can compare it with the desktop before trusting it (manual pairing).
Future<String> fetchSyncFingerprint(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final socket = await SecureSocket.connect(
    host,
    port,
    context: SecurityContext(withTrustedRoots: false),
    onBadCertificate: (_) => true,
    timeout: timeout,
  );
  try {
    final certificate = socket.peerCertificate;
    if (certificate == null) {
      throw StateError('The desktop did not present a certificate.');
    }
    return certificateFingerprint(certificate.der);
  } finally {
    socket.destroy();
  }
}

/// A private IPv4 address that a phone on the same network may reach, together
/// with the operating system's name for the adapter.
class LanAddress {
  const LanAddress({required this.address, required this.interfaceName});

  final String address;
  final String interfaceName;

  String get label =>
      interfaceName.isEmpty ? address : '$address ($interfaceName)';
}

/// Picks the private IPv4 addresses from [interfaces], removes duplicates and
/// puts the adapters most likely to be a real Wi-Fi/Ethernet connection first.
///
/// Virtual adapters (WSL, Hyper-V, Docker, VPNs) are kept because one of them
/// can occasionally be the reachable one, but they sort last. This stops the
/// pairing QR code from defaulting to an unreachable WSL/Hyper-V address.
List<LanAddress> selectLanAddresses(
  Iterable<({String name, List<String> addresses})> interfaces,
) {
  final seen = <String>{};
  final selected = <LanAddress>[];
  for (final nic in interfaces) {
    for (final text in nic.addresses) {
      final parsed = InternetAddress.tryParse(text);
      if (parsed == null || parsed.type != InternetAddressType.IPv4) continue;
      if (!isPrivateIPv4(parsed) || !seen.add(text)) continue;
      selected.add(LanAddress(address: text, interfaceName: nic.name));
    }
  }
  selected.sort((a, b) {
    final byInterface = _interfaceRank(
      a.interfaceName,
    ).compareTo(_interfaceRank(b.interfaceName));
    if (byInterface != 0) return byInterface;
    final byRange = _addressRangeRank(
      a.address,
    ).compareTo(_addressRangeRank(b.address));
    if (byRange != 0) return byRange;
    return a.address.compareTo(b.address);
  });
  return selected;
}

const _virtualInterfaceHints = <String>[
  'wsl',
  'hyper-v',
  'vethernet',
  'docker',
  'vmware',
  'virtualbox',
  'vbox',
  'veth',
  'tap',
  'tun',
  'vpn',
  'tailscale',
  'zerotier',
  'hamachi',
  'npcap',
  'bluetooth',
];

const _physicalInterfaceHints = <String>[
  'wi-fi',
  'wifi',
  'wlan',
  'wireless',
  'ethernet',
  'eth',
  'en',
  'lan',
];

int _interfaceRank(String name) {
  final lower = name.toLowerCase();
  if (_virtualInterfaceHints.any(lower.contains)) return 2;
  if (_physicalInterfaceHints.any(lower.contains)) return 0;
  return 1;
}

int _addressRangeRank(String address) {
  final bytes = InternetAddress.tryParse(address)?.rawAddress;
  if (bytes == null || bytes.length != 4) return 3;
  if (bytes[0] == 192 && bytes[1] == 168) return 0;
  if (bytes[0] == 10) return 1;
  return 2;
}

/// Every private IPv4 address of this machine, with the adapter name, ordered
/// so a real Wi-Fi/Ethernet address is the default.
Future<List<LanAddress>> localLanInterfaces() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  return selectLanAddresses([
    for (final nic in interfaces)
      (
        name: nic.name,
        addresses: [for (final address in nic.addresses) address.address],
      ),
  ]);
}

/// Private IPv4 addresses of this machine, which are the ones a phone on the
/// same Wi-Fi can reach.
Future<List<String>> localLanAddresses() async => [
  for (final address in await localLanInterfaces()) address.address,
];

/// Whether [address] is in one of the private IPv4 ranges (10/8, 172.16/12,
/// 192.168/16) used on home and office networks.
bool isPrivateIPv4(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length != 4) return false;
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);
}

/// What the pairing QR code carries: where the desktop is, the one-time code
/// and the fingerprint of its certificate.
class SyncPairingPayload {
  const SyncPairingPayload({
    required this.host,
    required this.port,
    required this.code,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String code;
  final String fingerprint;

  Uri toUri() => Uri(
    scheme: 'locus',
    host: 'pair',
    queryParameters: {'h': host, 'p': '$port', 'c': code, 'f': fingerprint},
  );

  /// Returns null for anything that is not a well-formed pairing code.
  static SyncPairingPayload? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'locus' || uri.host != 'pair') return null;
    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } on FormatException {
      return null;
    }
    final host = query['h'] ?? '';
    final port = int.tryParse(query['p'] ?? '');
    final code = query['c'] ?? '';
    final fingerprint = normalizeFingerprint(query['f'] ?? '');
    if (!RegExp(r'^[A-Za-z0-9.\-]{1,253}$').hasMatch(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-Za-z0-9]{1,32}$').hasMatch(code) ||
        fingerprint == null) {
      return null;
    }
    return SyncPairingPayload(
      host: host,
      port: port,
      code: code,
      fingerprint: fingerprint,
    );
  }
}
