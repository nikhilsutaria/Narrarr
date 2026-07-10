plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.narrarr.narrarr"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Required by the Readium Kotlin toolkit (flutter_readium).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        }
    }

    defaultConfig {
        applicationId = "dev.narrarr.narrarr"
        // minSdk 24 / compileSdk 36 / NDK 27 required by sherpa_onnx + flutter_readium.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Build flavors (pass --flavor qa|prod to flutter run/build):
    //  - qa:   bundles the sample book + default Amy voice (big APK, works
    //          fully offline out of the box). Installs side-by-side as
    //          "Narrarr QA" (…​.qa application id).
    //  - prod: the store build — no sample book, no bundled voice (all voices
    //          download on demand), much smaller APK.
    // Flutter's flavor-conditional assets in pubspec.yaml key off these names.
    flavorDimensions += "env"
    productFlavors {
        create("qa") {
            dimension = "env"
            applicationIdSuffix = ".qa"
            versionNameSuffix = "-qa"
            resValue("string", "app_name", "Narrarr QA")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Narrarr")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring runtime, required by the Readium Kotlin toolkit.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
