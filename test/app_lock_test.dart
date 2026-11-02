import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/providers/service_providers.dart';
import 'package:locus_planner/core/services/app_lock_service.dart';
import 'package:locus_planner/core/services/crypto/key_derivation.dart';
import 'package:locus_planner/core/services/privacy_screen_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/app_lock/presentation/app_lock_gate.dart';
import 'package:locus_planner/features/app_lock/providers/app_lock_controller.dart';

import 'helpers/memory_app_lock_store.dart';

AppLockService _service([MemoryAppLockStore? store]) =>
    testAppLockService(store);

void main() {
  group('AppLockService', () {
    test('validates 4 to 8 digit PINs', () {
      expect(AppLockService.validatePin('1234'), isNull);
      expect(AppLockService.validatePin('12345678'), isNull);
      expect(AppLockService.validatePin('123'), isNotNull);
      expect(AppLockService.validatePin('123456789'), isNotNull);
      expect(AppLockService.validatePin('abcd'), isNotNull);
      expect(AppLockService.validatePin('12 34'), isNotNull);
    });

    test('stores only a salted verifier, never the PIN itself', () async {
      final store = MemoryAppLockStore();
      final service = _service(store);

      await service.enable('2468');

      expect(await service.isEnabled(), isTrue);
      expect(store.value, isNot(contains('2468')));
      final envelope = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(envelope['iterations'], 1000);
      expect(envelope['version'], 2);
      expect(envelope['autoLockSeconds'], 60);
      expect(base64Decode(envelope['salt'] as String), hasLength(16));
      expect(base64Decode(envelope['hash'] as String), hasLength(32));

      expect(await service.verify('2468'), isA<PinAccepted>());
      expect(await service.verify('1357'), isA<PinWrong>());
      expect(await service.verify('24'), isA<PinWrong>());
    });

    test('uses a fresh salt for every enable', () async {
      final first = MemoryAppLockStore();
      final second = MemoryAppLockStore();
      final a = _service(first);
      final b = _service(second);

      await a.enable('1234');
      await b.enable('1234');

      final saltA = (jsonDecode(first.value!) as Map)['salt'];
      final saltB = (jsonDecode(second.value!) as Map)['salt'];
      expect(saltA, isNot(saltB));
    });

    test('disable refuses a wrong PIN and keeps the lock', () async {
      final service = _service();
      await service.enable('1234');

      await expectLater(
        service.disable('9999'),
        throwsA(isA<InvalidPinException>()),
      );
      expect(await service.isEnabled(), isTrue);

      await service.disable('1234');
      expect(await service.isEnabled(), isFalse);
    });

    test('changePin verifies the current PIN', () async {
      final service = _service();
      await service.enable('1234');

      await expectLater(
        service.changePin('0000', '5678'),
        throwsA(isA<InvalidPinException>()),
      );
      await service.changePin('1234', '5678');

      expect(await service.verify('1234'), isA<PinWrong>());
      expect(await service.verify('5678'), isA<PinAccepted>());
    });

    test(
      'a damaged verifier fails open instead of locking the owner out',
      () async {
        final store = MemoryAppLockStore('not json');
        final service = _service(store);

        expect(await service.isEnabled(), isFalse);
        expect(await service.verify('1234'), isA<PinWrong>());
      },
    );
  });

  group('AppLockController', () {
    late MemoryAppLockStore store;
    late ProviderContainer container;

    setUp(() {
      store = MemoryAppLockStore();
      container = ProviderContainer(
        overrides: [appLockServiceProvider.overrideWithValue(_service(store))],
      );
      addTearDown(container.dispose);
    });

    AppLockController controller() =>
        container.read(appLockControllerProvider.notifier);

    Future<void> ready() =>
        container.read(appLockControllerProvider.future).then((_) {});

    test('starts unlocked when no PIN is configured', () async {
      await ready();
      final state = container.read(appLockControllerProvider).requireValue;
      expect(state.enabled, isFalse);
      expect(state.locked, isFalse);
    });

    test('enable, lock and unlock drive the gate state', () async {
      await ready();
      expect(await controller().enable('1234'), isNull);

      var state = container.read(appLockControllerProvider).requireValue;
      expect(state.enabled, isTrue);
      expect(state.locked, isFalse);

      controller().lock();
      state = container.read(appLockControllerProvider).requireValue;
      expect(state.locked, isTrue);

      expect(await controller().unlock('0000'), isA<PinWrong>());
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isTrue,
      );

      expect(await controller().unlock('1234'), isA<PinAccepted>());
      state = container.read(appLockControllerProvider).requireValue;
      expect(state.locked, isFalse);
    });

    test('disable rejects the wrong PIN and reports a message', () async {
      await ready();
      await controller().enable('1234');

      expect(await controller().disable('9999'), isNotNull);
      expect(
        container.read(appLockControllerProvider).requireValue.enabled,
        isTrue,
      );

      expect(await controller().disable('1234'), isNull);
      expect(
        container.read(appLockControllerProvider).requireValue.enabled,
        isFalse,
      );
    });

    test('changePin switches which PIN unlocks', () async {
      await ready();
      await controller().enable('1234');
      expect(await controller().changePin('1234', '5678'), isNull);

      controller().lock();
      expect(await controller().unlock('1234'), isA<PinWrong>());
      expect(await controller().unlock('5678'), isA<PinAccepted>());
    });
  });

  group('AppLockGate', () {
    late MemoryAppLockStore store;
    late AppLockService service;

    setUp(() {
      store = MemoryAppLockStore();
      service = _service(store);
    });

    Future<void> pumpGate(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(
            home: AppLockGate(child: Text('private planner')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }

    testWidgets('a configured lock hides the app until the PIN is entered', (
      tester,
    ) async {
      await service.enable('1234');
      await pumpGate(tester);

      expect(find.text('Locus is locked'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '0000',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.textContaining('Wrong PIN.'), findsOneWidget);
      expect(find.text('Locus is locked'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Locus is locked'), findsNothing);
      expect(find.text('private planner'), findsOneWidget);
    });

    testWidgets('backgrounding the app re-locks it', (tester) async {
      await service.enable('1234', autoLockSeconds: 0);
      await pumpGate(tester);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('private planner'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // A paused app does not schedule frames in the test binding; returning to
      // the foreground is what actually paints the lock screen.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Locus is locked'), findsOneWidget);
    });

    testWidgets('losing focus alone does not interrupt the user', (
      tester,
    ) async {
      await service.enable('1234');
      await pumpGate(tester);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('private planner'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  group('PIN throttling', () {
    test('four misses are free, the fifth starts 30 seconds', () async {
      var now = DateTime(2026, 1, 1, 12);
      final store = MemoryAppLockStore();
      final service = testAppLockService(store, () => now);
      await service.enable('1234');

      for (var attempt = 1; attempt <= 4; attempt++) {
        final result = await service.verify('0000');
        expect(result, isA<PinWrong>());
        final wrong = result as PinWrong;
        expect(wrong.triesBeforeWait, 5 - attempt);
        expect(wrong.lockedUntil, isNull);
      }

      final fifth = await service.verify('0000') as PinWrong;
      expect(fifth.triesBeforeWait, isNull);
      expect(fifth.lockedUntil, now.add(const Duration(seconds: 30)));

      now = now.add(const Duration(seconds: 30));
      final sixth = await service.verify('0000') as PinWrong;
      expect(sixth.lockedUntil, now.add(const Duration(seconds: 60)));

      now = now.add(const Duration(seconds: 60));
      final seventh = await service.verify('0000') as PinWrong;
      expect(seventh.lockedUntil, now.add(const Duration(seconds: 120)));
    });

    test('the wait doubles and caps at 15 minutes', () async {
      var now = DateTime(2026, 1, 1, 12);
      final service = testAppLockService(MemoryAppLockStore(), () => now);
      await service.enable('1234');

      for (var attempt = 1; attempt <= 20; attempt++) {
        final wrong = await service.verify('0000') as PinWrong;
        if (wrong.lockedUntil != null) {
          final wait = wrong.lockedUntil!.difference(now);
          expect(wait.inSeconds, lessThanOrEqualTo(15 * 60));
          if (attempt > 11) expect(wait.inSeconds, 15 * 60);
          now = now.add(wait);
        }
      }
    });

    test(
      'a restart keeps the counter and refuses to derive while locked',
      () async {
        var now = DateTime(2026, 1, 1, 12);
        final store = MemoryAppLockStore();
        var derives = 0;

        final first = AppLockService(
          store: store,
          derive: (secret, salt, iterations) async {
            derives++;
            return KeyDerivation.deriveSync(secret, salt, iterations);
          },
          iterations: 1000,
          clock: () => now,
        );
        await first.enable('1234');
        for (var attempt = 0; attempt < 5; attempt++) {
          await first.verify('0000');
        }

        final before = derives;
        final restarted = AppLockService(
          store: store,
          derive: (secret, salt, iterations) async {
            derives++;
            return KeyDerivation.deriveSync(secret, salt, iterations);
          },
          iterations: 1000,
          clock: () => now,
        );
        expect(await restarted.verify('1234'), isA<PinLockedOut>());
        expect(derives, before);
      },
    );

    test('a correct PIN resets the failure count', () async {
      final service = testAppLockService();
      await service.enable('1234');
      for (var attempt = 0; attempt < 4; attempt++) {
        await service.verify('0000');
      }
      expect(await service.verify('1234'), isA<PinAccepted>());
      final wrong = await service.verify('0000') as PinWrong;
      expect(wrong.triesBeforeWait, 4);
    });

    test('a backwards clock does not shorten a lock-out', () async {
      var now = DateTime(2026, 1, 1, 12);
      final service = testAppLockService(MemoryAppLockStore(), () => now);
      await service.enable('1234');
      for (var attempt = 0; attempt < 5; attempt++) {
        await service.verify('0000');
      }
      now = now.subtract(const Duration(minutes: 10));
      expect(await service.verify('1234'), isA<PinLockedOut>());
    });

    test(
      'a version 1 record reads with defaults and upgrades on success',
      () async {
        final salt = KeyDerivation.randomBytes(16);
        final hash = KeyDerivation.deriveSync('1234', salt, 1000);
        final store = MemoryAppLockStore(
          jsonEncode({
            'version': 1,
            'iterations': 1000,
            'salt': base64Encode(salt),
            'hash': base64Encode(hash),
          }),
        );
        final service = testAppLockService(store);

        expect(await service.settings(), isA<AppLockSettings>());
        expect(await service.verify('1234'), isA<PinAccepted>());
        final rewritten = jsonDecode(store.value!) as Map<String, dynamic>;
        expect(rewritten['version'], 2);
        expect(rewritten['autoLockSeconds'], 60);
        expect(rewritten['failures'], 0);
      },
    );

    test('changePin derives exactly twice', () async {
      var calls = 0;
      final service = AppLockService(
        store: MemoryAppLockStore(),
        iterations: 1000,
        derive: (secret, salt, iterations) async {
          calls++;
          return KeyDerivation.deriveSync(secret, salt, iterations);
        },
      );
      await service.enable('1234');
      calls = 0;
      await service.changePin('1234', '5678');
      expect(calls, 2);
    });

    test('a damaged record fails open and is reported', () async {
      final service = testAppLockService(MemoryAppLockStore('not json'));
      final settings = await service.settings();
      expect(settings.enabled, isFalse);
      expect(settings.damaged, isTrue);
    });
  });

  group('AppLockController lifecycle', () {
    late MemoryAppLockStore store;
    late AppLockService service;
    late _FakePrivacyScreen privacy;
    late ProviderContainer container;
    var now = DateTime(2026, 1, 1, 12);

    setUp(() {
      store = MemoryAppLockStore();
      service = testAppLockService(store);
      privacy = _FakePrivacyScreen();
      container = ProviderContainer(
        overrides: [
          appLockServiceProvider.overrideWithValue(service),
          privacyScreenProvider.overrideWithValue(privacy),
        ],
      );
    });

    tearDown(() => container.dispose());

    AppLockController controller() =>
        container.read(appLockControllerProvider.notifier);

    Future<void> ready() =>
        container.read(appLockControllerProvider.future).then((_) {});

    test('privacy screen follows enable and disable', () async {
      await ready();
      expect(privacy.calls, [false]);

      await controller().enable('1234');
      expect(privacy.calls.last, isTrue);

      controller().lock();
      await controller().unlock('1234');
      expect(await controller().disable('1234'), isNull);
      expect(privacy.calls.last, isFalse);
    });

    test('a short absence keeps the app unlocked', () async {
      final original = AppClock.now;
      AppClock.now = () => now;
      addTearDown(() => AppClock.now = original);

      await ready();
      await controller().enable('1234', autoLockSeconds: 60);

      controller().noteLeftApp();
      now = now.add(const Duration(seconds: 10));
      controller().noteReturned();
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isFalse,
      );

      controller().noteLeftApp();
      now = now.add(const Duration(seconds: 90));
      controller().noteReturned();
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isTrue,
      );
    });

    test('immediate mode locks on every return', () async {
      await ready();
      await controller().enable('1234', autoLockSeconds: 0);
      controller().noteLeftApp();
      controller().noteReturned();
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isTrue,
      );
    });

    test('an external activity does not lock the app', () async {
      await ready();
      await controller().enable('1234', autoLockSeconds: 60);
      await controller().runExternal(() async {
        controller().noteLeftApp();
        controller().noteReturned();
      });
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isFalse,
      );
    });

    test('a backwards clock counts as away too long', () async {
      final original = AppClock.now;
      AppClock.now = () => now;
      addTearDown(() => AppClock.now = original);

      await ready();
      await controller().enable('1234', autoLockSeconds: 60);
      controller().noteLeftApp();
      now = now.subtract(const Duration(minutes: 1));
      controller().noteReturned();
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isTrue,
      );
    });
  });

  group('AppLockGate keeps the app mounted', () {
    late MemoryAppLockStore store;
    late AppLockService service;

    setUp(() {
      store = MemoryAppLockStore();
      service = testAppLockService(store);
    });

    Future<void> pumpGateWith(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            builder: (context, navigator) =>
                AppLockGate(child: navigator ?? const SizedBox.shrink()),
            home: child,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }

    Future<void> enterPin(WidgetTester tester, String pin) async {
      await tester.enterText(find.byKey(const ValueKey('app-lock-pin')), pin);
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }

    testWidgets('text survives locking and unlocking', (tester) async {
      await service.enable('1234', autoLockSeconds: 0);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpGateWith(
        tester,
        Scaffold(
          body: TextField(
            key: const ValueKey('draft-field'),
            controller: controller,
          ),
        ),
      );

      await enterPin(tester, '1234');
      await tester.enterText(
        find.byKey(const ValueKey('draft-field')),
        'draft',
      );
      expect(controller.text, 'draft');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Locus is locked'), findsOneWidget);

      await enterPin(tester, '1234');
      expect(controller.text, 'draft');
      expect(find.byKey(const ValueKey('draft-field')), findsOneWidget);
    });

    testWidgets('locking never disposes the child state', (tester) async {
      await service.enable('1234', autoLockSeconds: 0);
      var disposed = 0;
      await pumpGateWith(tester, _DisposalProbe(onDispose: () => disposed++));

      await enterPin(tester, '1234');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Locus is locked'), findsOneWidget);

      await enterPin(tester, '1234');
      expect(disposed, 0);
    });

    testWidgets(
      'the locked landing page is excluded from focus and semantics',
      (tester) async {
        await service.enable('1234');
        await pumpGateWith(tester, const Text('My Day landing page'));

        expect(
          tester
              .widget<ExcludeFocus>(find.byType(ExcludeFocus).first)
              .excluding,
          isTrue,
        );
        expect(
          tester
              .widget<ExcludeSemantics>(find.byType(ExcludeSemantics).first)
              .excluding,
          isTrue,
        );
        expect(find.text('Locus is locked'), findsOneWidget);

        await enterPin(tester, '1234');
        expect(
          tester
              .widget<ExcludeFocus>(find.byType(ExcludeFocus).first)
              .excluding,
          isFalse,
        );
        expect(
          tester
              .widget<ExcludeSemantics>(find.byType(ExcludeSemantics).first)
              .excluding,
          isFalse,
        );
      },
    );

    testWidgets('the lock-out countdown re-enables the field', (tester) async {
      var now = DateTime(2026, 1, 1, 12);
      final original = AppClock.now;
      AppClock.now = () => now;
      addTearDown(() => AppClock.now = original);
      service = testAppLockService(store, () => now);
      await service.enable('1234');

      await pumpGateWith(tester, const Text('private planner'));
      for (var attempt = 0; attempt < 5; attempt++) {
        await enterPin(tester, '0000');
      }

      expect(find.byKey(const ValueKey('app-lock-countdown')), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);

      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('app-lock-countdown')), findsNothing);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('app-lock-unlock')),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}

class _FakePrivacyScreen implements PrivacyScreen {
  final calls = <bool>[];

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

class _DisposalProbe extends StatefulWidget {
  const _DisposalProbe({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposalProbe> createState() => _DisposalProbeState();
}

class _DisposalProbeState extends State<_DisposalProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}
