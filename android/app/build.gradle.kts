plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.chaquo.python") version "15.0.1"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -----------------------------------------------------------
// Chaquopy configuration (new Kotlin DSL)
// -----------------------------------------------------------
chaquopy {
    defaultConfig {
        // Choose the Python runtime version you want bundled.
    // No version line – use default Python 3.8
    version = "3.8"

        // Optional: point to a local Python interpreter on the build machine.
        // buildPython("C:/Python312/python.exe")

        // Pip dependencies – installed into the APK.
        pip {
                            install("opencv-python-headless==4.5.1.48")
            install("numpy")
            // add more packages as needed
        }
    }

    // (Optional) productFlavors – different Python versions per flavor.
    // productFlavors {
    //     getByName("py311") { version = "3.11" }
    //     getByName("py312") { version = "3.8" }
    // }

    // (Optional) additional source directories.
    // sourceSets {
    //     getByName("main") { srcDir("more/python") }
    // }
}

android {
    namespace = "com.example.n_queens_solver"
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
        applicationId = "com.example.n_queens_solver"
        minSdk = flutter.minSdkVersion
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
