/// Central wall-clock source for production code and deterministic tests.
///
/// Tests may temporarily replace [now] and must restore it in tearDown. App
/// code should use this instead of calling DateTime.now() throughout the tree.
class AppClock {
  AppClock._();

  static DateTime Function() now = DateTime.now;
}
