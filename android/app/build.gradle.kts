import java.util.Properties
import java.io.FileInputStream
import java.util.Base64
import java.nio.charset.StandardCharsets

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun isStudioRequested(): Boolean {
    if (project.hasProperty("studio") || project.hasProperty("isStudio")) {
        return true
    }
    val dartDefines = project.findProperty("dart-defines") as? String
    if (dartDefines != null) {
        try {
            val entries = dartDefines.split(",")
            for (entry in entries) {
                val decoded = String(
                    Base64.getDecoder().decode(entry),
                    StandardCharsets.UTF_8,
                )
                if (decoded.contains("STUDIO_MODE=true")) {
                    return true
                }
            }
        } catch (_: Exception) {
            if (dartDefines.contains("STUDIO_MODE")) {
                return true
            }
        }
    }
    return false
}

val isStudio = isStudioRequested()

android {
    namespace = "com.musicality"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = if (isStudio) "com.musicality.studio" else "com.musicality"
        manifestPlaceholders["appName"] = if (isStudio) "Musicality Studio" else "Musicality"
        resValue("string", "app_name", if (isStudio) "Musicality Studio" else "Musicality")
        minSdk = 32
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
    }

    packaging {
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
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
