import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Neither the keystore nor its passwords are in the repo. key.properties is
// looked up in this order, first hit wins:
//   1. android/key.properties                      per-project override (gitignored)
//   2. %OneDriveConsumer%\Privat\key.properties    the shared copy, on Windows
//   3. ~/Library/CloudStorage/OneDrive-Personal/Privat/key.properties   the same, on macOS
// `OneDriveConsumer` is the *personal* OneDrive; `OneDrive` can be a work one.
// A relative storeFile resolves against the folder of the key.properties that names it.
// Nothing here throws at configuration time: without a keystore, or with a key.properties that
// can't be read (a cloud-only OneDrive file while offline, a `\u` in a Windows path), debug builds,
// `flutter run` and `flutter test` still work, and a release build is signed with the debug key,
// with a warning (see the end of this file).
val keystorePropertiesFile: File? = listOfNotNull(
    rootProject.file("key.properties"),
    System.getenv("OneDriveConsumer")?.let { File(it, "Privat/key.properties") },
    File(System.getProperty("user.home"), "Library/CloudStorage/OneDrive-Personal/Privat/key.properties"),
).firstOrNull { it.isFile }
val keystoreProperties = Properties()
val keystoreReadError: Exception? = keystorePropertiesFile?.let { f ->
    try {
        FileInputStream(f).use { keystoreProperties.load(it) }
        null
    } catch (e: Exception) {
        keystoreProperties.clear()
        e
    }
}
val releaseStoreFile: File? = keystoreProperties.getProperty("storeFile")
    ?.let { keystorePropertiesFile!!.absoluteFile.parentFile.resolve(it) }
    ?.takeIf { it.isFile }
logger.info("Release signing: key.properties = $keystorePropertiesFile, keystore = $releaseStoreFile")

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

    signingConfigs {
        // Only created when a keystore was found; without one, release falls back to the debug key.
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
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

// Without a keystore, release falls back to the debug key (see buildTypes). Such an APK can't update
// an installed release build or go to Play, so say so whenever a release build runs, and where we
// looked. QUIET level, because `flutter build` runs Gradle with -q, which hides warn().
if (releaseStoreFile == null) {
    val reason = when {
        keystorePropertiesFile == null ->
            "no key.properties in android/, in Privat under %OneDriveConsumer% " +
                "(OneDriveConsumer=${System.getenv("OneDriveConsumer")}) or in " +
                "~/Library/CloudStorage/OneDrive-Personal/Privat"
        keystoreReadError != null -> "$keystorePropertiesFile could not be read ($keystoreReadError)"
        else -> "$keystorePropertiesFile names storeFile=" +
            "${keystoreProperties.getProperty("storeFile")}, which is not on disk"
    }
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.project == project && it.name.startsWith("pre") && it.name.endsWith("ReleaseBuild") }) {
            logger.quiet("WARNING: Release signing: $reason. This release build is signed with the debug key.")
        }
    }
}
