# Distribution, signing and updates

## Windows installer

The tagged Windows release workflow builds:

- a ZIP of `build/windows/x64/runner/Release`;
- an Inno Setup installer from `installer/LocusPlanner.iss`;
- SHA-256 checksums for both.

The executable and installer are currently **unsigned**. Windows SmartScreen
therefore shows "Windows protected your PC" on first launch until the publisher
builds reputation. That warning is expected, but it is also why a signing
certificate is the next distribution improvement.

### Signing options

| Option | Effect | Use when |
| --- | --- | --- |
| Self-signed certificate | Removes the "unknown publisher" text only after each user installs the certificate into Trusted Publishers. Still not trusted by default. | Internal testing or a small group that can follow instructions. |
| OV code-signing certificate | SmartScreen reputation accumulates with downloads; hardware token or cloud HSM is normally required. | Public releases. |
| EV code-signing certificate | Immediate SmartScreen reputation in most cases; higher cost and stricter identity checks. | Public releases where first-run trust matters. |

Sign both the installer and the inner executable, and timestamp the signature so
it stays valid after the certificate expires. A typical `signtool` invocation
with a certificate in the Windows certificate store is:

```powershell
signtool sign /a /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  dist\LocusPlanner-Setup.exe
```

Keep the certificate private key out of the repository and CI logs. If signing is
added to CI, store the certificate and password as protected secrets and sign
only tagged release artifacts.

## Updates

There is **no automatic updater** yet. The supported update path is:

1. Download the newer installer (or ZIP) and its SHA-256 checksum.
2. Verify the checksum.
3. Run the installer over the existing installation.
4. The SQLite database in the application-support folder, settings and backups
   are kept; the installer does not remove user data.

`package_info_plus` exposes the running version, which is shown in the app's
about/settings area. A manual "check for updates" would compare that with the
latest release tag; a future automatic updater should verify a signed manifest
and the installer signature before running it.

## Android APK

Release signing is configured in `android/key.properties` or with the
`LOCUS_KEYSTORE_FILE`, `LOCUS_KEYSTORE_PASSWORD`, `LOCUS_KEY_ALIAS` and
`LOCUS_KEY_PASSWORD` environment variables. Set
`LOCUS_REQUIRE_RELEASE_SIGNING=true` in CI so a release build fails instead of
silently falling back to the debug key. See
[ANDROID_RELEASE.md](ANDROID_RELEASE.md) for the full procedure.

Never commit a keystore or `key.properties`. Distributing the APK directly means
users install updates themselves; the database survives an in-place update
because the application ID does not change. Switching application ID later makes
Android treat the app as a different installation with separate data.

## What goes into a shared archive

Create source archives with `git archive` (or GitHub's "Download source"), not by
ZIPping the working folder. `.gitattributes` marks `android/local.properties`,
`android/build/`, `build/` and similar paths as `export-ignore`, so SDK paths,
Gradle reports and compiled output are not handed out. Release binaries belong in
the release assets, not in the source archive.
