import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is wired from android/key.properties, which is gitignored —
// each release builder generates and owns their keystore (see README,
// "Generating your release keystore"). When the file is absent (CI,
// contributors), release builds fall back to debug signing so
// `flutter build apk --release` keeps working.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.kashu.kashu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kashu.kashu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // An .aab exists only to be uploaded, so refuse to build one that Play
    // would reject. Checked against the requested tasks rather than the task
    // graph so the failure happens at configuration time, before any work.
    if (!keystorePropertiesFile.exists() &&
        gradle.startParameter.taskNames.any { it.contains("bundleRelease", ignoreCase = true) }) {
        throw GradleException(
            "Cannot build a release App Bundle without android/key.properties - " +
            "it would be debug-signed and rejected by Google Play. " +
            "See README > Generating your release keystore (Android)."
        )
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Debug-signed release APKs stay buildable so CI's smoke build
                // and local testing keep working without secrets...
                // The "WARNING:" prefix matters: `flutter build` filters Gradle
                // output and only surfaces lines matching known patterns.
                logger.warn(
                    "\nWARNING: KashU - android/key.properties not found, so this " +
                    "release build is DEBUG-SIGNED and cannot be uploaded to " +
                    "Google Play. See README > Generating your release keystore.\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LaunchTheme/NormalTheme (res/values*/styles.xml) extend Theme.AppCompat,
    // which local_auth requires alongside FlutterFragmentActivity. Declared
    // here rather than relying on a plugin to pull AppCompat in transitively.
    implementation("androidx.appcompat:appcompat:1.7.1")
}
