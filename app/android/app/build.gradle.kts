import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

fun dartDefines(): Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        .orEmpty()
        .split(",")
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it)) }
        .mapNotNull { entry -> entry.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        .toMap()

android {
    namespace = "id.beokay.app"
    // Plugin notifikasi dan androidx terbaru membutuhkan compileSdk tinggi; ambil yang terbesar.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "id.beokay.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect (paket health) membutuhkan minSdk 26.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter {
        it.project == project && it.name.contains("Release") &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    if (releaseTasks.isNotEmpty()) {
        if (!hasReleaseKey) {
            throw GradleException(
                "Rilis butuh kunci penandatanganan: buat android/key.properties (storeFile, storePassword, keyAlias, keyPassword). Lihat docs/operations/runbook.md.",
            )
        }
        val api = dartDefines()["API_BASE_URL"]
        if (api == null || !api.startsWith("https://")) {
            throw GradleException(
                "Rilis butuh --dart-define=API_BASE_URL=https://... (sekarang: ${api ?: "tidak diisi"}).",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Konfigurasi Firebase milik aplikasi ini (didaftarkan di proyek Firebase untuk applicationId di atas).
// Tanpa berkas ini aplikasi tetap dibangun dan berjalan; push dilaporkan "tidak tersedia" dan pengingat memakai notifikasi lokal.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
