import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/sync_tls.dart';
import 'package:locus_planner/features/mobile/pair_scanner_page.dart';

void main() {
  testWidgets('the camera error view explains the problem', (tester) async {
    var manualEntries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PairScannerErrorView(
            error: 'Camera permission denied',
            onManualEntry: () => manualEntries++,
          ),
        ),
      ),
    );

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(find.textContaining('Camera permission denied'), findsOneWidget);

    await tester.tap(find.text('Enter details manually'));
    expect(manualEntries, 1);
  });

  test('a scan result distinguishes a payload from manual entry', () {
    const payload = SyncPairingPayload(
      host: '192.168.1.20',
      port: 43821,
      code: 'A1B2C3D4',
      fingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    const success = PairScanSuccess(payload);
    expect(success, isA<PairScanResult>());
    expect(success.payload.host, '192.168.1.20');
    expect(success.payload.code, 'A1B2C3D4');
    expect(const PairScanManualEntry(), isA<PairScanResult>());
  });
}
