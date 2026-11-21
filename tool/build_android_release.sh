#!/usr/bin/env bash
# Canonical Android release build. CI and the Play upload instructions both
# call this script so signing, encryption, obfuscation and symbols cannot drift.
set -euo pipefail

if [[ -z "${LOCUS_KEYSTORE_BASE64:-}" || -z "${LOCUS_KEYSTORE_PASSWORD:-}" || -z "${LOCUS_KEY_ALIAS:-}" || -z "${LOCUS_KEY_PASSWORD:-}" ]]; then
  echo "Release signing secrets are required for a public Android build." >&2
  exit 1
fi

SUPPORT_EMAIL="${LOCUS_SUPPORT_EMAIL:-}"
PRIVACY_URL="${LOCUS_PRIVACY_URL:-}"
if [[ -z "$SUPPORT_EMAIL" || "$SUPPORT_EMAIL" == *"example.invalid"* ]]; then
  echo "LOCUS_SUPPORT_EMAIL must be a real, monitored support address." >&2
  exit 1
fi
if [[ "$PRIVACY_URL" != https://* || "$PRIVACY_URL" == *"example.invalid"* ]]; then
  echo "LOCUS_PRIVACY_URL must be a published HTTPS policy URL." >&2
  exit 1
fi

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
flutter test

flutter build appbundle --release \
  --dart-define=LOCUS_DB_ENCRYPTION=true \
  --dart-define=LOCUS_SUPPORT_EMAIL="$SUPPORT_EMAIL" \
  --dart-define=LOCUS_PRIVACY_URL="$PRIVACY_URL" \
  --obfuscate --split-debug-info=build/symbols/android

dart tool/verify_release_bundle.dart \
  --platform=android \
  --path=build/app/outputs/bundle/release/app-release.aab \
  --support-email="$SUPPORT_EMAIL" \
  --privacy-url="$PRIVACY_URL"

echo "Android AAB: build/app/outputs/bundle/release/app-release.aab"
