import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locus_planner/core/services/quick_capture_service.dart';
import 'package:locus_planner/core/providers/quick_capture_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initializes enabled shortcut and registers once', () async {
    var registrations = 0;
    Future<void> Function()? trigger;
    final prefs = await SharedPreferences.getInstance();
    final service = QuickCaptureService(
      preferences: prefs,
      register: (callback) async {
        registrations++;
        trigger = callback;
      },
      unregister: () async {},
    );

    await service.init(onTriggered: () async {});

    expect(service.enabled, isTrue);
    expect(registrations, 1);
    expect(trigger, isNotNull);
    await service.dispose();
  });

  test('startup registration failure disables persisted shortcut', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = QuickCaptureService(
      preferences: prefs,
      register: (_) async => throw StateError('shortcut is occupied'),
      unregister: () async {},
    );

    await expectLater(service.init(onTriggered: () async {}), throwsStateError);
    expect(service.enabled, isFalse);
    expect(prefs.getBool(QuickCaptureService.preferenceKey), isFalse);
    await service.dispose();
  });

  test('failed enable leaves setting and state disabled', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(QuickCaptureService.preferenceKey, false);
    final service = QuickCaptureService(
      preferences: prefs,
      register: (_) async => throw StateError('shortcut is occupied'),
      unregister: () async {},
    );
    await service.init(onTriggered: () async {});

    await expectLater(service.setEnabled(true), throwsStateError);
    expect(service.enabled, isFalse);
    expect(prefs.getBool(QuickCaptureService.preferenceKey), isFalse);
    await service.dispose();
  });

  test('failed unregister preserves enabled state and preference', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(QuickCaptureService.preferenceKey, true);
    var failUnregister = true;
    final service = QuickCaptureService(
      preferences: prefs,
      register: (_) async {},
      unregister: () async {
        if (failUnregister) throw StateError('unregister failed');
      },
    );
    await service.init(onTriggered: () async {});

    await expectLater(service.setEnabled(false), throwsStateError);
    expect(service.enabled, isTrue);
    expect(prefs.getBool(QuickCaptureService.preferenceKey), isTrue);
    failUnregister = false;
    await service.dispose();
  });

  test('trigger callback exceptions are contained', () async {
    Future<void> Function()? trigger;
    final service = QuickCaptureService(
      register: (callback) async {
        trigger = callback;
      },
      unregister: () async {},
      preferences: await SharedPreferences.getInstance(),
    );
    await service.init(
      onTriggered: () async => throw StateError('window failed'),
    );

    await expectLater(trigger!(), completes);
    await service.dispose();
  });

  test('dispose is idempotent and unregisters once', () async {
    var unregisters = 0;
    final service = QuickCaptureService(
      register: (_) async {},
      unregister: () async {
        unregisters++;
      },
      preferences: await SharedPreferences.getInstance(),
    );
    await service.init(onTriggered: () async {});

    await service.dispose();
    await service.dispose();

    expect(unregisters, 1);
    expect(service.enabled, isFalse);
  });
  group('QuickCaptureDialogGate', () {
    test('allows only one pending/open dialog and can be reused', () {
      final gate = QuickCaptureDialogGate();
      expect(gate.tryAcquire(), isTrue);
      expect(gate.tryAcquire(), isFalse);
      gate.release();
      expect(gate.tryAcquire(), isTrue);
    });
  });
}
