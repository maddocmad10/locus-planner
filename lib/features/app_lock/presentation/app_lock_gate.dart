import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_lock_service.dart';
import '../../../core/utils/app_clock.dart';
import '../providers/app_lock_controller.dart';

/// Wraps the whole app and shows the PIN screen above it whenever the lock is
/// engaged.
///
/// This is installed through `MaterialApp.builder`, above the Navigator, so the
/// shell, every route and every dialog stay mounted underneath the overlay.
/// While blocked, focus, semantics and tickers are disabled so the user cannot
/// interact with hidden content.
///
/// The app locks when Android backgrounds it, or when the desktop window is
/// hidden/minimized for longer than the configured grace period. Losing
/// keyboard focus alone (`inactive`) must not lock a desktop app: menus, file
/// pickers and the tray would otherwise interrupt the user with a PIN prompt.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appLockControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.inactive:
        // Windows focus loss and Android permission dialogs land here. They
        // are not a reason to lock.
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.noteLeftApp();
        break;
      case AppLifecycleState.resumed:
        controller.noteReturned();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockControllerProvider).valueOrNull;
    final blocked = lock == null || lock.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: TickerMode(enabled: !blocked, child: widget.child),
          ),
        ),
        if (blocked)
          Positioned.fill(
            child: lock == null
                ? const _LockCover()
                : _LockOverlayHost(lockedOutUntil: lock.lockedOutUntil),
          ),
      ],
    );
  }
}

/// Neutral surface shown while the secure-storage read is in flight, so no
/// private content flashes before the gate decides.
class _LockCover extends StatelessWidget {
  const _LockCover();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(color: Theme.of(context).colorScheme.surface),
    );
  }
}

/// The gate sits above the Navigator, so there is no Overlay ancestor for the
/// PIN field's selection handles and context menu. This host supplies one.
class _LockOverlayHost extends StatefulWidget {
  const _LockOverlayHost({this.lockedOutUntil});

  final DateTime? lockedOutUntil;

  @override
  State<_LockOverlayHost> createState() => _LockOverlayHostState();
}

class _LockOverlayHostState extends State<_LockOverlayHost> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => AppLockScreen(lockedOutUntil: widget.lockedOutUntil),
  );

  @override
  void didUpdateWidget(covariant _LockOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockedOutUntil != widget.lockedOutUntil) {
      _entry.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }
}

/// Full-screen PIN prompt. It owns only presentation; verification lives in
/// [AppLockController] so the same rules apply on desktop and Android.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({this.lockedOutUntil, super.key});

  final DateTime? lockedOutUntil;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;
  DateTime? _lockedUntil;
  Duration _remaining = Duration.zero;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _setLockedUntil(widget.lockedOutUntil, notify: false);
  }

  @override
  void didUpdateWidget(covariant AppLockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockedOutUntil != widget.lockedOutUntil) {
      _setLockedUntil(widget.lockedOutUntil);
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _setLockedUntil(DateTime? until, {bool notify = true}) {
    _countdown?.cancel();
    _countdown = null;
    _lockedUntil = until;
    if (until == null) {
      _remaining = Duration.zero;
      if (notify && mounted) setState(() {});
      return;
    }
    _updateRemaining(notify: false);
    if (notify && mounted) setState(() {});
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final expired = _updateRemaining(notify: false);
      if (expired) {
        _countdown?.cancel();
        setState(() {
          _lockedUntil = null;
          _remaining = Duration.zero;
          _error = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  bool _updateRemaining({bool notify = true}) {
    final until = _lockedUntil;
    if (until == null) {
      _remaining = Duration.zero;
      return true;
    }
    final remaining = until.difference(AppClock.now());
    _remaining = remaining.isNegative ? Duration.zero : remaining;
    if (notify && mounted) setState(() {});
    return remaining <= Duration.zero;
  }

  Future<void> _unlock() async {
    final pin = _controller.text;
    if (pin.isEmpty || _checking || _lockedUntil != null) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .unlock(pin);
    if (!mounted) return;
    setState(() => _checking = false);
    switch (result) {
      case PinAccepted():
        break;
      case PinLockedOut(:final until):
        _controller.clear();
        _setLockedUntil(until);
      case PinWrong(:final triesBeforeWait, :final lockedUntil):
        _controller.clear();
        if (lockedUntil != null) {
          _error = null;
          _setLockedUntil(lockedUntil);
        } else {
          setState(() {
            _error = triesBeforeWait == null
                ? 'That PIN is not correct.'
                : 'Wrong PIN. $triesBeforeWait '
                      '${triesBeforeWait == 1 ? 'try' : 'tries'} left before '
                      'a wait.';
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _lockedUntil != null;
    final seconds = (_remaining.inMilliseconds / 1000).ceil();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Locus is locked',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your PIN to see your planner.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const ValueKey('app-lock-pin'),
                    controller: _controller,
                    autofocus: true,
                    enabled: !_checking && !waiting,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    onSubmitted: (_) => _unlock(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                  ),
                  if (waiting) ...[
                    Text(
                      'Try again in ${seconds}s',
                      key: const ValueKey('app-lock-countdown'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    key: const ValueKey('app-lock-unlock'),
                    onPressed: _checking || waiting ? null : _unlock,
                    child: Text(
                      _checking
                          ? 'Checking…'
                          : waiting
                          ? 'Locked'
                          : 'Unlock',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
