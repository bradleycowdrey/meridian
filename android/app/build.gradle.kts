plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing with the upload key (Google Play), from Gradle properties or the environment, never from a file
// in the repository: androidKeystoreFile / ANDROID_KEYSTORE_FILE (the .jks), androidKeystorePassword /
// ANDROID_KEYSTORE_PASSWORD, androidKeyAlias / ANDROID_KEY_ALIAS and androidKeyPassword / ANDROID_KEY_PASSWORD
// (the keystore's password when not set). CI decodes the keystore from its secret (.github/workflows/android.yml).
// Without a keystore the release build is unsigned; the debug build never changes.
fun signingValue(property: String, env: String): String? =
    ((project.findProperty(property) as String?) ?: System.getenv(env))?.takeIf { it.isNotBlank() }
val uploadKeystore = signingValue("androidKeystoreFile", "ANDROID_KEYSTORE_FILE")?.let { file(it) }?.takeIf { it.exists() }

android {
    namespace = "com.bradcowdrey.meridian"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.bradcowdrey.meridian"
        minSdk = 26
        targetSdk = 36
        versionCode = (project.findProperty("versionCode") as String?)?.toInt() ?: 1
        versionName = (project.findProperty("versionName") as String?) ?: "2.0"
    }

    signingConfigs {
        if (uploadKeystore != null) {
            create("release") {
                storeFile = uploadKeystore
                storePassword = signingValue("androidKeystorePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("androidKeyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("androidKeyPassword", "ANDROID_KEY_PASSWORD") ?: storePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    // The city list and public holidays, shared with the Mac and iPhone apps (not copied).
    sourceSets {
        getByName("main") {
            assets.srcDirs("../../Resources/Data")
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
}
