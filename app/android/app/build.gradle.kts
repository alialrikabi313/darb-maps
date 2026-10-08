plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.darb.darb"
    // صريح لا flutter.compileSdkVersion: permission_handler_android يطلب
    // 37 أو أعلى، وافتراضي Flutter (36) يسقط البناء
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    // Java 21 لا 17: بعض الاعتمادات مترجَمة لـ21، و17 يسقط البناء
    // بـ«invalid source release: 21» بعد عشر دقائق بلا سبب واضح.
    // يلزم أيضاً: flutter config --jdk-dir="C:\Program Files\Java\jdk-21"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.darb.darb"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}
