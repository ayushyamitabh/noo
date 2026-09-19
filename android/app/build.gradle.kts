import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: prefer a local android/key.properties (gitignored, for
// a developer machine that has the release keystore), then CI env vars
// (set by .gitea/workflows/build.yml from repo secrets), then null - which
// falls back to debug signing below so an unconfigured checkout still
// builds/runs fine, same as before this existed.
val releaseKeystoreProperties = Properties().apply {
    val propsFile = rootProject.file("key.properties")
    if (propsFile.exists()) propsFile.inputStream().use { load(it) }
}

fun releaseSigningValue(propertyKey: String, envKey: String): String? =
    releaseKeystoreProperties.getProperty(propertyKey) ?: System.getenv(envKey)

val releaseStoreFile = releaseSigningValue("storeFile", "RELEASE_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "RELEASE_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "RELEASE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "dev.ayushya.noo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.ayushya.noo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // local_auth (app-lock/biometric) requires API 24+; Flutter's own
        // default may be lower, so floor it here rather than relying on
        // whatever flutter.minSdkVersion currently resolves to.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
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
            // Falls back to the debug keystore (so an unconfigured
            // checkout can still `flutter run --release`) when no release
            // signing config is available - see the comment above.
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

dependencies {
    // Device sync's periodic/one-off background jobs (SyncWorker,
    // ConflictResolveWorker) - see their doc comments for why this is
    // plain WorkManager rather than a Dart-side background-task plugin.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    // PROPFIND (WebDAV directory listing) - Android's HttpURLConnection
    // hard-rejects any method outside {OPTIONS,GET,HEAD,POST,PUT,DELETE,
    // TRACE,PATCH} (ProtocolException), unlike plain OpenJDK. OkHttp has
    // no such whitelist. See SyncEngine.kt.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}

flutter {
    source = "../.."
}
