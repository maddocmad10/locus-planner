import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/sync_tls.dart';

/// What the scanner returns: either a parsed pairing payload or a request to
/// enter the desktop details by hand (camera unavailable or QR unreadable).
sealed class PairScanResult {
  const PairScanResult();
}

class PairScanSuccess extends PairScanResult {
  const PairScanSuccess(this.payload);

  final SyncPairingPayload payload;
}

class PairScanManualEntry extends PairScanResult {
  const PairScanManualEntry();
}

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
    // The scanner stream can deliver a frame after this page was popped; a
    // setState or Navigator call then throws.
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue;
      if (text == null) continue;
      final payload = SyncPairingPayload.tryParse(text);
      if (payload != null) {
        _handled = true;
        Navigator.of(context).pop(PairScanSuccess(payload));
        return;
      }
      setState(() => _hint = 'That is not a Locus pairing code.');
    }
  }

  void _enterManually() {
    if (!mounted) return;
    _handled = true;
    Navigator.of(context).pop(const PairScanManualEntry());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            onDetectError: (error, stackTrace) {
              if (!mounted) return;
              setState(
                () => _hint =
                    'Could not read that code. Try again or enter the details '
                    'manually.',
              );
            },
            errorBuilder: (context, error, child) => PairScannerErrorView(
              error: error,
              onManualEntry: _enterManually,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hint ??
                          'On the desktop, open Settings → Device Sync and '
                              'point the camera at the QR code.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _enterManually,
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Enter details manually'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a black preview when the camera is denied or unavailable.
/// It is a separate widget so its fallback can be tested without a camera.
class PairScannerErrorView extends StatelessWidget {
  const PairScannerErrorView({
    required this.error,
    required this.onManualEntry,
    super.key,
  });

  final Object error;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Camera unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Locus could not open the camera. Check the camera permission, '
                'or enter the desktop address and pairing code by hand.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onManualEntry,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter details manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
