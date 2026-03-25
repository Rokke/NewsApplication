import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "no.talgoe.news_client_application"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"
    // ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "no.talgoe.news_client_application"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Inne i android{
    signingConfigs {
        val hasSigningInfo = project.hasProperty("ReleaseStoreFile") &&
                             project.hasProperty("ReleaseStorePassword") &&
                             project.hasProperty("ReleaseKeyAlias") &&
                             project.hasProperty("ReleaseKeyPassword")

        if (hasSigningInfo) {
            create("release") {
                storeFile = file(project.property("ReleaseStoreFile") as String)
                storePassword = project.property("ReleaseStorePassword") as String
                keyAlias = project.property("ReleaseKeyAlias") as String
                keyPassword = project.property("ReleaseKeyPassword") as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Flutter bruker R8 som standard, så 'isMinifyEnabled = true' 
            // er ofte allerede satt eller håndtert av Flutter-verktøyene.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // Automatisk navngiving som henter info fra Flutter/pubspec.yaml
    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.ApkVariantOutputImpl
            
            // Henter navnet fra prosjektmappen (eller sett manuelt)
            val appName = rootProject.projectDir.parentFile.name
            val vName = variant.versionName // Fra pubspec.yaml
            val vCode = variant.versionCode // Fra pubspec.yaml
            val type = variant.buildType.name
            
            output.outputFileName = "$appName-$vName+$vCode-type.apk"
        }
    }
}

flutter {
    source = "../.."
}
