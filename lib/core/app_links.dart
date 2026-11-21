/// Public release identities.
///
/// CI supplies these with `--dart-define` from the release configuration. The
/// defaults are deliberately non-deliverable so a misconfigured build fails
/// review instead of silently publishing a placeholder address.
abstract final class AppLinks {
  static const supportEmail = String.fromEnvironment(
    'LOCUS_SUPPORT_EMAIL',
    defaultValue: 'support@example.invalid',
  );

  static const privacyUrl = String.fromEnvironment(
    'LOCUS_PRIVACY_URL',
    defaultValue: 'https://example.invalid/privacy',
  );

  static bool get hasPublicSupport =>
      !supportEmail.endsWith('.invalid') &&
      !privacyUrl.contains('example.invalid');
}
