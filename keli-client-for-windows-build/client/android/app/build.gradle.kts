plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.keli_client"
    compileSdk = flutter.compileSdkVersion
    // NDK: plugins (jni) require 28.2.13676358; Flutter recommends the highest required NDK and they are
    // backward compatible. Unity's prebuilt libil2cpp/libunity .so live in the separate (prebuilt)
    // unityLibrary module, so the app's NDK choice doesn't affect them.
    ndkVersion = "28.2.13676358"
    // Pin build-tools to what Unity 6 ships (36.0.0); else AGP tries to fetch 35.0.0 into the read-only SDK.
    buildToolsVersion = "36.0.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.keli_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Keli runs on old hardware (HUAWEI MediaPad M5 Lite, Android 8 / API 26). minSdk 24 already
        // covers it; EMUI's "App not installed" is a SIGNATURE issue, fixed by re-signing the built
        // APK with a v1 (JAR) signature — see tool/sign-keli-apk.sh (run after `flutter build apk`).
        // Unity 6000's unityLibrary requires minSdk 26; the target device (MediaPad M5 Lite) is API 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // Intent: v1 (JAR) + v2 signatures for EMUI/Android 8 compatibility. NOTE: AGP ignores
            // enableV1Signing here for minSdk>=24 and still emits v2-only — so the authoritative fix
            // is the post-build re-sign in tool/sign-keli-apk.sh (apksigner --min-sdk-version 21).
            enableV1Signing = true
            enableV2Signing = true
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
    // Unity-as-a-Library: the embedded Unity face (flutter_embed_unity).
    implementation(project(":unityLibrary"))
}
