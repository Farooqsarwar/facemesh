plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.facemeshcamer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.facemeshcamer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
            getByName("release") {
                // 👇 Keep R8 enabled for shrinking and optimization, but with our safety rules
                isMinifyEnabled = true
                isShrinkResources = false

                // ✅ Use your ProGuard rules safely
                proguardFiles(
                    getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro"
                )

                // ⚠️ Use a real signing key before Play Store release
                signingConfig = signingConfigs.getByName("debug")
            }

            getByName("debug") {
                isMinifyEnabled = false
            }
        }
}

flutter {
    source = "../.."
}
