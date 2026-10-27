import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

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

  /// Returns the identity stored with the database, creating and storing one
  /// the first time. It is reused on every start, so the fingerprint stays the
  /// same across restarts and address changes. The settings are transient, so
  /// they are never written to backups and a restore cannot bring an old key
  /// back.
  static Future<SyncTlsIdentity> loadOrCreate(AppDatabase db) async {
    final certificate = await db.getSetting(
      AppDatabase.syncTlsCertificateSettingKey,
    );
    final privateKey = await db.getSetting(
      AppDatabase.syncTlsPrivateKeySettingKey,
    );
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
    await db.setSetting(
      AppDatabase.syncTlsPrivateKeySettingKey,
      created.privateKeyPem,
    );
    return created;
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

/// Private IPv4 addresses of this machine, which are the ones a phone on the
/// same Wi-Fi can reach.
Future<List<String>> localLanAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  return [
    for (final nic in interfaces)
      for (final address in nic.addresses)
        if (_isPrivateIPv4(address)) address.address,
  ];
}

bool _isPrivateIPv4(InternetAddress address) {
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
    queryParameters: {
      'h': host,
      'p': '$port',
      'c': code,
      'f': fingerprint,
    },
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
