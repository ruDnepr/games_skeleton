plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ru.dnepr.diana_games"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Уникальный applicationId. Прежние отдельные игры (Нарды, Го, Шашки
        // и т.д.) тоже собирались на скелете с applicationId ru.dnepr.games_for_diana,
        // и их debug-подпись не совпадает с CI-подписью этого APK. Уникальный id
        // исключает конфликт «signatures do not match previously installed version».
        applicationId = "ru.dnepr.diana_games"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // LAN access is implicit for target 36. Migrating to 37 requires
        // requesting Android ACCESS_LOCAL_NETWORK at runtime.
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 code shrinking and resource shrinking disabled: the CI
            // runner (7 GB RAM) consistently runs out of memory during the
            // R8 pass on the combined codebase of nine games. The app is
            // small enough without shrinking; the debug-signed release APK
            // is not intended for Google Play anyway.
            isMinifyEnabled = false
            isShrinkResources = false
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
