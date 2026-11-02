import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/services/app_lock_service.dart';
import '../../../core/services/error_log_service.dart';
import '../../../core/services/privacy_screen_service.dart';
import '../../../core/utils/app_clock.dart';

/// The lock state the UI gate renders.
class AppLockState {
  const AppLockState({
    required this.enabled,
    required this.unlocked,
    this.autoLockSeconds = AppLockService.defaultAutoLockSeconds,
    this.lockedOutUntil,
    this.notice,
  });

  /// A PIN has been configured on this installation.
  final bool enabled;

  /// The user has entered the PIN in this app session, or no lock is set.
  final bool unlocked;

  /// 0 means lock immediately on return; otherwise a grace period.
  final int autoLockSeconds;

  /// Set while too many wrong attempts are being rate limited.
  final DateTime? lockedOutUntil;

  /// One-time warning shown in Settings (for example a damaged store).
  final String? notice;

  bool get locked => enabled && !unlocked;

  AppLockState copyWith({
    bool? enabled,
    bool? unlocked,
    int? autoLockSeconds,
    DateTime? lockedOutUntil,
    bool clearLockedOut = false,
    String? notice,
    bool clearNotice = false,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    unlocked: unlocked ?? this.unlocked,
    autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    lockedOutUntil: clearLockedOut
        ? null
        : (lockedOutUntil ?? this.lockedOutUntil),
    notice: clearNotice ? null : (notice ?? this.notice),
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
  PrivacyScreen get _privacy => ref.read(privacyScreenProvider);

  DateTime? _leftAt;
  int _externalActivityDepth = 0;

  /// Exposed for the settings card so validation happens before a second
  /// confirmation dialog is opened.
  static String? newPinProblem(String pin) => AppLockService.validatePin(pin);

  @override
  Future<AppLockState> build() async {
    AppLockSettings settings;
    try {
      settings = await _service.settings();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      settings = const AppLockSettings(
        enabled: false,
        autoLockSeconds: AppLockService.defaultAutoLockSeconds,
        damaged: true,
      );
    }
    final state = AppLockState(
      enabled: settings.enabled,
      unlocked: !settings.enabled,
      autoLockSeconds: settings.autoLockSeconds,
      notice: settings.damaged ? AppLockService.damagedNotice : null,
    );
    unawaited(_privacy.setSecure(settings.enabled));
    return state;
  }

  /// Checks [pin]. Returns the service result so the gate can render the
  /// remaining attempts or the countdown. It never reports success while the
  /// state is still loading.
  Future<PinCheck> unlock(String pin) async {
    final current = state.valueOrNull;
    if (current == null) return const PinWrong();
    if (!current.enabled) return const PinAccepted();

    final check = await _service.verify(pin);
    if (check is PinAccepted) {
      state = AsyncData(
        current.copyWith(
          unlocked: true,
          clearLockedOut: true,
          clearNotice: true,
        ),
      );
    } else if (check is PinLockedOut) {
      state = AsyncData(current.copyWith(lockedOutUntil: check.until));
    } else if (check is PinWrong && check.lockedUntil != null) {
      state = AsyncData(current.copyWith(lockedOutUntil: check.lockedUntil));
    }
    return check;
  }

  /// Locks a running app, for example when it returns from the background
  /// after the grace period.
  void lock() {
    final current = state.valueOrNull;
    if (current == null || !current.enabled || !current.unlocked) return;
    state = AsyncData(current.copyWith(unlocked: false));
  }

  /// Records that the app left. Calls made while an external activity is in
  /// progress are ignored so a file picker or camera does not lock the app.
  void noteLeftApp() {
    if (_externalActivityDepth == 0) _leftAt ??= AppClock.now();
  }

  /// Applies the grace period when the app returns.
  void noteReturned() {
    final left = _leftAt;
    _leftAt = null;
    final current = state.valueOrNull;
    if (left == null || current == null || !current.enabled || current.locked) {
      return;
    }
    final away = AppClock.now().difference(left);
    // A clock that moved backwards is treated as "away too long".
    if (away.isNegative || away.inSeconds >= current.autoLockSeconds) {
      lock();
    }
  }

  /// Runs an action that leaves the app (file picker, camera, permission
  /// prompt) without treating its lifecycle pauses as leaving the app.
  Future<T> runExternal<T>(Future<T> Function() action) async {
    _externalActivityDepth++;
    try {
      return await action();
    } finally {
      _externalActivityDepth--;
    }
  }

  /// Enables the lock. The current session stays unlocked so the user sees the
  /// setting change immediately. Returns an error message for the UI.
  Future<String?> enable(
    String pin, {
    int autoLockSeconds = AppLockService.defaultAutoLockSeconds,
  }) async {
    final problem = AppLockService.validatePin(pin);
    if (problem != null) return problem;
    try {
      await _service.enable(pin, autoLockSeconds: autoLockSeconds);
      state = AsyncData(
        AppLockState(
          enabled: true,
          unlocked: true,
          autoLockSeconds: autoLockSeconds,
        ),
      );
      await _privacy.setSecure(true);
      return null;
    } catch (error) {
      return 'Could not save the app lock: $error';
    }
  }

  Future<String?> disable(String pin) async {
    try {
      await _service.disable(pin);
      final current = state.valueOrNull;
      state = AsyncData(
        AppLockState(
          enabled: false,
          unlocked: true,
          autoLockSeconds:
              current?.autoLockSeconds ?? AppLockService.defaultAutoLockSeconds,
        ),
      );
      await _privacy.setSecure(false);
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

  Future<String?> setAutoLockSeconds(int seconds) async {
    try {
      await _service.updateAutoLockSeconds(seconds);
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current.copyWith(autoLockSeconds: seconds));
      }
      return null;
    } catch (error) {
      return 'Could not save the lock delay: $error';
    }
  }
}

final appLockControllerProvider =
    AsyncNotifierProvider<AppLockController, AppLockState>(
      AppLockController.new,
    );
