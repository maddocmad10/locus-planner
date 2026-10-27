import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_tls.dart';

/// UDP port the desktop answers "where are you?" questions on. It is separate
/// from the HTTPS sync port.
const syncDiscoveryPort = 43822;

const _discoveryRequest = 'locus-discover/1';
const _discoveryService = 'locus-sync';

/// Where a desktop was found, and the HTTPS port it syncs on.
typedef DiscoveredDesktop = ({String host, int port});

/// Lets a paired phone find the desktop again after its address changed (a new
/// DHCP lease, a router restart), without the user typing an IP address.
///
/// This is only a hint about *where* to connect. It carries nothing secret and
/// grants nothing: the phone still connects over HTTPS, pinned to the
/// certificate it saw at pairing, and still needs its bearer token. Someone
/// else on the network who answers a discovery request can at worst send the
/// phone to an address where the TLS check then fails, and the phone also
/// ignores any answer whose fingerprint is not the pinned one.
///
/// Only devices on the local network are answered, and answers are rate
/// limited, so the port cannot be used to bounce traffic at someone else.
class SyncDiscoveryResponder {
  SyncDiscoveryResponder({
    required this.fingerprint,
    required this.syncPort,
    this.port = syncDiscoveryPort,
  });

  /// Fingerprint of the certificate the desktop serves; public information.
  final String fingerprint;

  /// The HTTPS port the desktop syncs on.
  final int syncPort;

  /// The UDP port to listen on; 0 picks a free one (tests).
  final int port;

  static const _maxRepliesPerSecond = 20;

  RawDatagramSocket? _socket;
  final _window = Stopwatch()..start();
  int _repliesInWindow = 0;

  /// The UDP port actually bound, or null while stopped.
  int? get boundPort => _socket?.port;

  /// Starts answering. Returns false, without throwing, when the port cannot
  /// be bound (another program uses it): discovery is a convenience and must
  /// never stop sync from starting.
  Future<bool> start() async {
    if (_socket != null) return true;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: false,
      );
      _socket = socket;
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) _drain(socket);
        },
        onError: (Object _) {
          // A broken datagram or a closing socket must not escape.
        },
      );
      return true;
    } on SocketException catch (error) {
      stderr.writeln('LAN sync: discovery unavailable: $error');
      return false;
    }
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  void _drain(RawDatagramSocket socket) {
    var datagram = socket.receive();
    while (datagram != null) {
      _answer(socket, datagram);
      datagram = socket.receive();
    }
  }

  void _answer(RawDatagramSocket socket, Datagram datagram) {
    if (datagram.data.length > 64) return;
    if (!(datagram.address.isLoopback || isPrivateIPv4(datagram.address))) {
      return;
    }
    if (utf8.decode(datagram.data, allowMalformed: true).trim() !=
        _discoveryRequest) {
      return;
    }
    if (_window.elapsedMilliseconds >= 1000) {
      _window
        ..reset()
        ..start();
      _repliesInWindow = 0;
    }
    if (_repliesInWindow >= _maxRepliesPerSecond) return;
    _repliesInWindow++;
    final reply = utf8.encode(
      jsonEncode({
        'service': _discoveryService,
        'port': syncPort,
        'fp': fingerprint,
      }),
    );
    try {
      socket.send(reply, datagram.address, datagram.port);
    } on SocketException {
      // The sender went away; nothing to do.
    }
  }
}

/// Looks for the desktop whose certificate has [fingerprint] on the local
/// network, by asking every device on it where that desktop is. Returns null
/// if nobody with that fingerprint answers within [timeout].
///
/// [port] and [targets] exist so tests can aim at a loopback responder; the app
/// uses the defaults (a broadcast on [syncDiscoveryPort]).
Future<DiscoveredDesktop?> discoverDesktop({
  required String fingerprint,
  int port = syncDiscoveryPort,
  Duration timeout = const Duration(seconds: 2),
  List<InternetAddress>? targets,
}) async {
  final expected = normalizeFingerprint(fingerprint);
  if (expected == null) return null;
  final destinations = targets ?? await _broadcastTargets();
  if (destinations.isEmpty) return null;

  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } on SocketException {
    return null;
  }
  final found = Completer<DiscoveredDesktop?>();
  final subscription = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    var datagram = socket.receive();
    while (datagram != null) {
      final result = _parseReply(datagram, expected);
      if (result != null && !found.isCompleted) found.complete(result);
      datagram = socket.receive();
    }
  });
  Timer? retry;
  try {
    try {
      socket.broadcastEnabled = true;
    } on SocketException {
      // Directed sends can still work without it.
    }
    final request = utf8.encode(_discoveryRequest);
    void send() {
      for (final target in destinations) {
        try {
          socket.send(request, target, port);
        } on SocketException {
          // This interface may be down; try the others.
        }
      }
    }

    send();
    // UDP is lossy and Wi-Fi power saving can swallow a broadcast, so ask once
    // more shortly afterwards.
    retry = Timer(const Duration(milliseconds: 600), send);
    return await found.future.timeout(timeout, onTimeout: () => null);
  } finally {
    retry?.cancel();
    await subscription.cancel();
    socket.close();
  }
}

DiscoveredDesktop? _parseReply(Datagram datagram, String expectedFingerprint) {
  if (datagram.data.length > 512) return null;
  try {
    final decoded = jsonDecode(utf8.decode(datagram.data));
    if (decoded is! Map<String, dynamic> ||
        decoded['service'] != _discoveryService) {
      return null;
    }
    final fingerprint = normalizeFingerprint('${decoded['fp']}');
    final port = decoded['port'];
    if (fingerprint != expectedFingerprint ||
        port is! int ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return (host: datagram.address.address, port: port);
  } on FormatException {
    return null;
  }
}

/// The limited broadcast address plus the /24 broadcast address of each local
/// private network. Some Wi-Fi stacks only deliver one of the two.
Future<List<InternetAddress>> _broadcastTargets() async {
  final targets = <String>{'255.255.255.255'};
  try {
    for (final address in await localLanAddresses()) {
      final parts = address.split('.');
      if (parts.length == 4) {
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
  } on SocketException {
    // The limited broadcast alone is still worth trying.
  }
  return [for (final target in targets) InternetAddress(target)];
}
