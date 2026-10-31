import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/providers/service_providers.dart';
import 'package:locus_planner/core/services/app_lock_service.dart';
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
      expect(base64Decode(envelope['salt'] as String), hasLength(16));
      expect(base64Decode(envelope['hash'] as String), hasLength(32));

      expect(await service.verify('2468'), isTrue);
      expect(await service.verify('1357'), isFalse);
      expect(await service.verify('24'), isFalse);
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

      expect(await service.verify('1234'), isFalse);
      expect(await service.verify('5678'), isTrue);
    });

    test(
      'a damaged verifier fails open instead of locking the owner out',
      () async {
        final store = MemoryAppLockStore('not json');
        final service = _service(store);

        expect(await service.isEnabled(), isFalse);
        expect(await service.verify('1234'), isFalse);
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

      expect(await controller().unlock('0000'), isFalse);
      expect(
        container.read(appLockControllerProvider).requireValue.locked,
        isTrue,
      );

      expect(await controller().unlock('1234'), isTrue);
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
      expect(await controller().unlock('1234'), isFalse);
      expect(await controller().unlock('5678'), isTrue);
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

      expect(find.text('private planner'), findsNothing);
      expect(find.text('Locus is locked'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '0000',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('That PIN is not correct.'), findsOneWidget);
      expect(find.text('private planner'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('private planner'), findsOneWidget);
    });

    testWidgets('backgrounding the app re-locks it', (tester) async {
      await service.enable('1234');
      await pumpGate(tester);

      await tester.enterText(
        find.byKey(const ValueKey('app-lock-pin')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('private planner'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // A paused app does not schedule frames in the test binding; returning to
      // the foreground is what actually paints the lock screen.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('private planner'), findsNothing);
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
}
