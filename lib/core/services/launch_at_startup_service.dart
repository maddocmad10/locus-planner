import 'dart:io';

/// Runs an external command. Injected by tests so registry changes are never
/// made on a real machine.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Registers Locus in the current user's Windows `Run` key.
///
/// Windows starts every value under
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` when the user signs in.
/// Only the signed-in user's registry hive is touched, so enabling this never
/// needs administrator rights and never changes another account.
///
/// `reg.exe` is used instead of a package or a startup shortcut: it is part of
/// Windows, it is atomic, and the same command works in debug and release.
class LaunchAtStartupService {
  LaunchAtStartupService({
    ProcessRunner? run,
    this.executablePath,
    bool? isWindows,
  }) : _run = run ?? Process.run,
       _isWindows = isWindows ?? Platform.isWindows;

  static const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const valueName = 'Locus Planner';

  final ProcessRunner _run;
  final String? executablePath;
  final bool _isWindows;

  bool get isSupported => _isWindows;

  /// The command Windows will run, quoted so a path with spaces stays one
  /// argument. When installed, this points at the installed `.exe`, not at a
  /// development runner.
  String get command => '"${executablePath ?? Platform.resolvedExecutable}"';

  /// Whether the current user's Run key already contains Locus.
  Future<bool> isEnabled() async {
    if (!_isWindows) return false;
    try {
      final result = await _run('reg', ['query', runKey, '/v', valueName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Enables or disables launch at sign-in. Returns whether the registry now
  /// reflects the requested state.
  Future<bool> setEnabled(bool enabled) async {
    if (!_isWindows) return false;
    try {
      if (enabled) {
        final result = await _run('reg', [
          'add',
          runKey,
          '/v',
          valueName,
          '/t',
          'REG_SZ',
          '/d',
          command,
          '/f',
        ]);
        return result.exitCode == 0;
      }
      final result = await _run('reg', [
        'delete',
        runKey,
        '/v',
        valueName,
        '/f',
      ]);
      // Deleting a value that was never there is not a failure.
      return result.exitCode == 0 || !await isEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Rewrites the registered command when the app was moved or upgraded.
  /// Best-effort: a missing entry is left alone and startup never depends on
  /// this succeeding.
  Future<void> refreshIfEnabled() async {
    if (!_isWindows) return;
    if (!await isEnabled()) return;
    await setEnabled(true);
  }
}
