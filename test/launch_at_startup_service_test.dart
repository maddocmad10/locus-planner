import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:locus_planner/core/services/launch_at_startup_service.dart';

class _FakeProcessRunner {
  _FakeProcessRunner({
    this.queryExit = 1,
    this.addExit = 0,
    this.deleteExit = 0,
  });

  int queryExit;
  int addExit;
  int deleteExit;
  final List<({String executable, List<String> arguments})> calls = [];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: arguments));
    final exitCode = switch (arguments.first) {
      'query' => queryExit,
      'add' => addExit,
      'delete' => deleteExit,
      _ => 1,
    };
    return ProcessResult(0, exitCode, '', '');
  }
}

void main() {
  group('LaunchAtStartupService', () {
    test(
      'reports unsupported platforms without touching the registry',
      () async {
        final runner = _FakeProcessRunner();
        final service = LaunchAtStartupService(
          run: runner.run,
          isWindows: false,
        );

        expect(service.isSupported, isFalse);
        expect(await service.isEnabled(), isFalse);
        expect(await service.setEnabled(true), isFalse);
        await service.refreshIfEnabled();
        expect(runner.calls, isEmpty);
      },
    );

    test('is enabled when the Run key contains the value', () async {
      final runner = _FakeProcessRunner(queryExit: 0);
      final service = LaunchAtStartupService(
        run: runner.run,
        executablePath: r'C:\Program Files\Locus\locus_planner.exe',
        isWindows: true,
      );

      expect(await service.isEnabled(), isTrue);

      final call = runner.calls.single;
      expect(call.executable, 'reg');
      expect(call.arguments, [
        'query',
        LaunchAtStartupService.runKey,
        '/v',
        LaunchAtStartupService.valueName,
      ]);
    });

    test('enabling writes a quoted executable path', () async {
      final runner = _FakeProcessRunner();
      final service = LaunchAtStartupService(
        run: runner.run,
        executablePath: r'C:\Program Files\Locus\locus_planner.exe',
        isWindows: true,
      );

      expect(await service.setEnabled(true), isTrue);

      final arguments = runner.calls.single.arguments;
      expect(arguments.take(4), [
        'add',
        LaunchAtStartupService.runKey,
        '/v',
        LaunchAtStartupService.valueName,
      ]);
      expect(arguments, contains('/f'));
      expect(
        arguments[arguments.indexOf('/d') + 1],
        r'"C:\Program Files\Locus\locus_planner.exe"',
      );
    });

    test('disabling deletes the Run value', () async {
      final runner = _FakeProcessRunner();
      final service = LaunchAtStartupService(
        run: runner.run,
        executablePath: r'C:\Locus\locus_planner.exe',
        isWindows: true,
      );

      expect(await service.setEnabled(false), isTrue);

      expect(runner.calls.single.arguments, [
        'delete',
        LaunchAtStartupService.runKey,
        '/v',
        LaunchAtStartupService.valueName,
        '/f',
      ]);
    });

    test('disabling an absent value still succeeds', () async {
      final runner = _FakeProcessRunner(queryExit: 1, deleteExit: 1);
      final service = LaunchAtStartupService(
        run: runner.run,
        executablePath: r'C:\Locus\locus_planner.exe',
        isWindows: true,
      );

      expect(await service.setEnabled(false), isTrue);
      expect(runner.calls.map((call) => call.arguments.first), [
        'delete',
        'query',
      ]);
    });

    test('reports a failed registry write', () async {
      final runner = _FakeProcessRunner(addExit: 5);
      final service = LaunchAtStartupService(
        run: runner.run,
        executablePath: r'C:\Locus\locus_planner.exe',
        isWindows: true,
      );

      expect(await service.setEnabled(true), isFalse);
    });

    test('refresh rewrites the command only when already enabled', () async {
      final enabledRunner = _FakeProcessRunner(queryExit: 0);
      final enabled = LaunchAtStartupService(
        run: enabledRunner.run,
        executablePath: r'C:\Locus\locus_planner.exe',
        isWindows: true,
      );

      await enabled.refreshIfEnabled();

      expect(enabledRunner.calls.map((call) => call.arguments.first), [
        'query',
        'add',
      ]);

      final disabledRunner = _FakeProcessRunner(queryExit: 1);
      final disabled = LaunchAtStartupService(
        run: disabledRunner.run,
        executablePath: r'C:\Locus\locus_planner.exe',
        isWindows: true,
      );

      await disabled.refreshIfEnabled();

      expect(disabledRunner.calls.map((call) => call.arguments.first), [
        'query',
      ]);
    });

    test('a process failure is reported as disabled', () async {
      final service = LaunchAtStartupService(
        run: (_, _) async => throw StateError('reg.exe missing'),
        executablePath: r'C:\Locus\locus_planner.exe',
        isWindows: true,
      );

      expect(await service.isEnabled(), isFalse);
      expect(await service.setEnabled(true), isFalse);
    });
  });
}
