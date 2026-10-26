import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (never committed) or, in
// CI, from LOCUS_* environment variables. Without either, release builds are
// signed with the debug key so `flutter build apk --release` still works for
// local testing; an APK built that way must not be distributed.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingSetting(property: String, environment: String): String? =
    (keystoreProperties.getProperty(property) ?: System.getenv(environment))
        ?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingSetting("storeFile", "LOCUS_KEYSTORE_FILE")
val releaseStorePassword = signingSetting("storePassword", "LOCUS_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingSetting("keyAlias", "LOCUS_KEY_ALIAS")
val releaseKeyPassword = signingSetting("keyPassword", "LOCUS_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it != null }

if (!hasReleaseSigning && System.getenv("LOCUS_REQUIRE_RELEASE_SIGNING") == "true") {
    throw GradleException(
        "Release signing is required but not configured. " +
            "See docs/ANDROID_RELEASE.md."
    )
}

android {
    namespace = "com.example.locusplanner.locus_planner"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The installed app's identity. Changing it later makes Android treat
        // the app as a different one (no in-place update, separate data), so
        // set it to an ID you own before the first real install. The code
        // namespace above is separate and does not need to match.
        applicationId = "com.locusplanner.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
