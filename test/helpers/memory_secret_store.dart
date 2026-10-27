import 'package:locus_planner/core/services/sync_tls.dart';

/// In-memory [SyncSecretStore] so tests never touch the operating system's
/// credential vault.
class MemorySecretStore implements SyncSecretStore {
  MemorySecretStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String newValue) async => value = newValue;

  @override
  Future<void> delete() async => value = null;
}

/// A store that always fails, like a broken or locked credential vault.
class BrokenSecretStore implements SyncSecretStore {
  @override
  Future<String?> read() async => throw StateError('vault unavailable');

  @override
  Future<void> write(String value) async =>
      throw StateError('vault unavailable');

  @override
  Future<void> delete() async => throw StateError('vault unavailable');
}
