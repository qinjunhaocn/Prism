plugins {
    id("com.android.application")
    // Flutter Gradle Plugin 必须在 Android / Kotlin 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.voxyn.prism"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.voxyn.prism"
        // 24 起步：与 Flutter 默认值及插件要求一致
        // （shared_preferences / permission_handler / dynamic_color 均声明 minSdk 24）。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: 上线前替换为正式签名配置。
            signingConfig = signingConfigs.getByName("debug")

            // 体积与性能：开启资源压缩与代码混淆。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // 调试包关闭混淆，方便定位问题。
            isMinifyEnabled = false
        }
    }

    // 大图解码等场景依赖稳定的 Java 17 API。
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
            )
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
