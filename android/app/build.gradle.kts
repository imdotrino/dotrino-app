import java.io.File
import java.util.Base64

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services") // push nativo (FCM): necesita app/google-services.json (gitignoreado)
}

// FIRMA DE RELEASE (la llave de SUBIDA a Google Play): viene de la bóveda, nunca de un archivo
// del repo ni de un `.env`.
//
//   dotrino-env run --ns claude -- ./gradlew --no-daemon :app:bundleRelease
//
// `dotrino-env` pone en el entorno ANDROID_UPLOAD_KEYSTORE_B64 / _STORE_PASSWORD / _KEY_ALIAS /
// _KEY_PASSWORD (cajón `claude`, con aprobación en el teléfono). El .jks se escribe en
// $XDG_RUNTIME_DIR —memoria, no disco— y se borra al salir la JVM; `--no-daemon` hace que esa
// JVM sea la de ESTA compilación y no un daemon que se queda vivo con la ruta apuntada.
//
// Sin esas variables el release sale SIN firmar (y así lo dice Gradle): no hay otra llave de
// repuesto a la que caer.
val uploadKey: Map<String, String>? = run {
    val b64 = System.getenv("ANDROID_UPLOAD_KEYSTORE_B64") ?: return@run null
    val dir = System.getenv("XDG_RUNTIME_DIR") ?: error("XDG_RUNTIME_DIR is not set: refusing to write the upload key to disk")
    val f = File(dir, "dotrino-upload-${ProcessHandle.current().pid()}.jks")
    f.writeBytes(Base64.getDecoder().decode(b64))
    f.setReadable(false, false); f.setReadable(true, true)
    f.deleteOnExit()
    mapOf(
        "storeFile" to f.absolutePath,
        "storePassword" to (System.getenv("ANDROID_UPLOAD_STORE_PASSWORD") ?: error("ANDROID_UPLOAD_STORE_PASSWORD missing")),
        "keyAlias" to (System.getenv("ANDROID_UPLOAD_KEY_ALIAS") ?: error("ANDROID_UPLOAD_KEY_ALIAS missing")),
        "keyPassword" to (System.getenv("ANDROID_UPLOAD_KEY_PASSWORD") ?: error("ANDROID_UPLOAD_KEY_PASSWORD missing")),
    )
}

android {
    namespace = "com.dotrino.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.dotrino.app"
        minSdk = 31
        targetSdk = 36
        versionCode = 8
        versionName = "0.2.2"
    }

    signingConfigs {
        if (uploadKey != null) {
            create("release") {
                storeFile = file(uploadKey.getValue("storeFile"))
                storePassword = uploadKey.getValue("storePassword")
                keyAlias = uploadKey.getValue("keyAlias")
                keyPassword = uploadKey.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (uploadKey != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { buildConfig = true }
}

dependencies {
    implementation(project(":dotrino-native"))
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
}
