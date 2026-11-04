import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/sqlite3mc.dart';

/// On-device E0 proof for the bundled SQLite3MC library.
///
/// Run on a connected Android device or emulator:
///
/// ```text
/// flutter test integration_test/sqlite3mc_e0_test.dart -d <device-id>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled SQLite3MC passes the encrypted round trip', (
    tester,
  ) async {
    Sqlite3mcLoader.resetVerificationForTesting();
    final report = await Sqlite3mcLoader.requireVerified(
      profile: CipherProfiles.active,
    );

    expect(report.passed, isTrue);
    expect(report.runtime.version, contains('2.6.1'));
    expect(report.runtime.cipherPragmaAvailable, isTrue);
    expect(report.encryptedHeader, isTrue);
    expect(report.reopenedWithKey, isTrue);
    expect(report.wrongKeyRejected, isTrue);
    expect(report.tempStore, 2);
    expect(report.pageSize, 4096);
  });
}
