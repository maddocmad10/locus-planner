import 'package:locus_planner/core/services/sync_tls.dart';

/// A fixed self-signed certificate (EC P-256, valid for 100 years) for the sync
/// tests, so they do not have to generate an RSA key on every run. Created with
/// `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes
/// -days 36500`. It protects nothing: the private key is public.
final testTlsIdentity = SyncTlsIdentity(
  certificatePem: _certificate,
  privateKeyPem: _privateKey,
);

/// SHA-256 of [testTlsIdentity]'s DER certificate, as printed by
/// `openssl x509 -outform der | sha256sum`.
const testTlsFingerprint =
    'ce080bb6ae3e1bdd2df30863c7fe2ae8d486536436cc1a713831a3dd2d4b492c';

const _certificate = '''-----BEGIN CERTIFICATE-----
MIIBkDCCATegAwIBAgIUTWQnaCmFJ6WWzuWcsXHhWAXo3t0wCgYIKoZIzj0EAwIw
HTEbMBkGA1UEAwwSTG9jdXMgUGxhbm5lciBUZXN0MCAXDTI2MTAyNzA2Mzc1NVoY
DzIxMjYxMDAzMDYzNzU1WjAdMRswGQYDVQQDDBJMb2N1cyBQbGFubmVyIFRlc3Qw
WTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATpwysfnmtW0ntRBJadiNWz1Dsn2jzc
0eRZrT5JUVGYnvEQwZHUQ2gj5pVyZNGhoeH1+yw+U3423FtLwh4lKX2to1MwUTAd
BgNVHQ4EFgQUO1q2XcTfuKX/YcCcZNYjGYp1Pn4wHwYDVR0jBBgwFoAUO1q2XcTf
uKX/YcCcZNYjGYp1Pn4wDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBE
AiB/zBip1aY0MjATDPF/4cSvQcI8lWbVGtvcMeyscVYNdgIgLqP+6IVnJo4bCw5B
SSZmr6ZZlKE0Jfsbm4xGMjLOxMo=
-----END CERTIFICATE-----
''';

const _privateKey = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg90WbNRliijW3oUHF
b4cSukIPItvhbCyISbxALzv3TPShRANCAATpwysfnmtW0ntRBJadiNWz1Dsn2jzc
0eRZrT5JUVGYnvEQwZHUQ2gj5pVyZNGhoeH1+yw+U3423FtLwh4lKX2t
-----END PRIVATE KEY-----
''';
