import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/services/app_lock_service.dart';

/// The lock state the UI gate renders.
class AppLockState {
  const AppLockState({required this.enabled, required this.unlocked});

  /// A PIN has been configured on this installation.
  final bool enabled;

  /// The user has entered the PIN in this app session, or no lock is set.
  final bool unlocked;

  bool get locked => enabled && !unlocked;

  AppLockState copyWith({bool? enabled, bool? unlocked}) => AppLockState(
    enabled: enabled ?? this.enabled,
    unlocked: unlocked ?? this.unlocked,
  );
}

/// Owns whether the app is locked now and mutates the secure PIN verifier.
///
/// The gate starts after the async secure-storage read. If protected storage
/// is unavailable (for example in a widget test without the plugin), the app is
/// treated as unlocked rather than trapping the owner behind a lock that can
/// never be verified.
class AppLockController extends AsyncNotifier<AppLockState> {
  AppLockService get _service => ref.read(appLockServiceProvider);

  /// Exposed for the settings card so validation happens before a second
  /// confirmation dialog is opened.
  static String? newPinProblem(String pin) => AppLockService.validatePin(pin);

  @override
  Future<AppLockState> build() async {
    try {
      final enabled = await _service.isEnabled();
      return AppLockState(enabled: enabled, unlocked: !enabled);
    } catch (_) {
      return const AppLockState(enabled: false, unlocked: true);
    }
  }

  Future<bool> unlock(String pin) async {
    final current = state.valueOrNull;
    if (current == null || !current.enabled) return true;
    if (!await _service.verify(pin)) return false;
    state = AsyncData(current.copyWith(unlocked: true));
    return true;
  }

  /// Locks a running app, for example when it goes to the background.
  void lock() {
    final current = state.valueOrNull;
    if (current == null || !current.enabled || !current.unlocked) return;
    state = AsyncData(current.copyWith(unlocked: false));
  }

  /// Enables the lock. The current session stays unlocked so the user sees the
  /// setting change immediately. Returns an error message for the UI.
  Future<String?> enable(String pin) async {
    final problem = AppLockService.validatePin(pin);
    if (problem != null) return problem;
    try {
      await _service.enable(pin);
      state = const AsyncData(AppLockState(enabled: true, unlocked: true));
      return null;
    } catch (error) {
      return 'Could not save the app lock: $error';
    }
  }

  Future<String?> disable(String pin) async {
    try {
      await _service.disable(pin);
      state = const AsyncData(AppLockState(enabled: false, unlocked: true));
      return null;
    } on InvalidPinException {
      return 'That PIN is not correct.';
    } catch (error) {
      return 'Could not remove the app lock: $error';
    }
  }

  Future<String?> changePin(String currentPin, String newPin) async {
    final problem = AppLockService.validatePin(newPin);
    if (problem != null) return problem;
    try {
      await _service.changePin(currentPin, newPin);
      return null;
    } on InvalidPinException {
      return 'That PIN is not correct.';
    } catch (error) {
      return 'Could not change the app lock PIN: $error';
    }
  }
}

final appLockControllerProvider =
    AsyncNotifierProvider<AppLockController, AppLockState>(
      AppLockController.new,
    );
