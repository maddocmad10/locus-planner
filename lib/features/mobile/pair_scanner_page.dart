import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/sync_tls.dart';

/// Scans the pairing QR code shown in Locus Settings on the desktop and closes
/// with the parsed [SyncPairingPayload].
class PairScannerPage extends StatefulWidget {
  const PairScannerPage({super.key});

  @override
  State<PairScannerPage> createState() => _PairScannerPageState();
}

class _PairScannerPageState extends State<PairScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue;
      if (text == null) continue;
      final payload = SyncPairingPayload.tryParse(text);
      if (payload != null) {
        _handled = true;
        Navigator.of(context).pop(payload);
        return;
      }
      setState(() => _hint = 'That is not a Locus pairing code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing code')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _hint ??
                      'On the desktop, open Settings → Device Sync and point '
                          'the camera at the QR code.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
