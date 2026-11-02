import 'package:locus_planner/core/services/app_lock_service.dart';
import 'package:locus_planner/core/services/crypto/key_derivation.dart';

/// In-memory [AppLockStore] so widget tests never touch the platform's
/// credential vault.
class MemoryAppLockStore implements AppLockStore {
  MemoryAppLockStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String newValue) async => value = newValue;

  @override
  Future<void> delete() async => value = null;
}

/// An app-lock service with the production PBKDF2 shape but a fast iteration
/// count and an in-process derivation, so tests do not pay for an isolate or a
/// slow suite.
AppLockService testAppLockService([
  MemoryAppLockStore? store,
  DateTime Function()? clock,
]) => AppLockService(
  store: store ?? MemoryAppLockStore(),
  iterations: 1000,
  derive: (secret, salt, iterations) async =>
      KeyDerivation.deriveSync(secret, salt, iterations),
  clock: clock,
);
