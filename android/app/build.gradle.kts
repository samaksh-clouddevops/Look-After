import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    kotlin("plugin.serialization")
}

// Optional LLM keys from android/local.properties (never commit secrets).
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun localProp(key: String, default: String = ""): String =
    (localProps.getProperty(key) ?: default).replace("\"", "\\\"")

// Firebase only when google-services.json is committed/copied into app/.
val hasGoogleServices = file("google-services.json").exists()
if (hasGoogleServices) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

android {
    namespace = "com.lookafter.app"
    // androidx.core 1.15+ requires compileSdk 35+.
    compileSdk = 35

    defaultConfig {
        applicationId = "com.lookafter.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
        // OpenAI-compatible chat endpoint (empty key → offline coach only).
        buildConfigField("String", "LLM_API_KEY", "\"${localProp("LOOKAFTER_LLM_API_KEY")}\"")
        buildConfigField(
            "String",
            "LLM_BASE_URL",
            "\"${localProp("LOOKAFTER_LLM_BASE_URL", "https://api.openai.com/v1")}\"",
        )
        buildConfigField(
            "String",
            "LLM_MODEL",
            "\"${localProp("LOOKAFTER_LLM_MODEL", "gpt-4o-mini")}\"",
        )
        // Optional TURN relay for WebRTC body-double (STUN defaults always on).
        buildConfigField("String", "TURN_URL", "\"${localProp("LOOKAFTER_TURN_URL")}\"")
        buildConfigField("String", "TURN_USER", "\"${localProp("LOOKAFTER_TURN_USER")}\"")
        buildConfigField("String", "TURN_PASS", "\"${localProp("LOOKAFTER_TURN_PASS")}\"")
        buildConfigField(
            "boolean",
            "TURN_FORCE_RELAY",
            (localProps.getProperty("LOOKAFTER_TURN_FORCE_RELAY") ?: "false")
                .equals("true", ignoreCase = true)
                .toString(),
        )
    }

    signingConfigs {
        // Optional Play upload key via CI env (LOOKAFTER_STORE_*).
        val store = System.getenv("LOOKAFTER_STORE_FILE")
        if (store != null) {
            create("release") {
                storeFile = file(store)
                storePassword = System.getenv("LOOKAFTER_STORE_PASSWORD")
                keyAlias = System.getenv("LOOKAFTER_KEY_ALIAS")
                keyPassword = System.getenv("LOOKAFTER_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Unsigned release is fine for CI artifact; sign when config exists.
            signingConfigs.findByName("release")?.let { signingConfig = it }
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
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(project(":lookafter-core"))

    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-service:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // Persistence (DataStore + kotlinx.serialization JSON snapshots)
    implementation("androidx.datastore:datastore:1.1.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Health Connect SDK (real reads; demo fallback when unavailable)
    implementation("androidx.health.connect:connect-client:1.1.0-alpha11")

    // Glance home-screen widget
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")

    // CameraX front-camera body double
    val cameraX = "1.4.0"
    implementation("androidx.camera:camera-core:$cameraX")
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")

    // Native WebRTC (Stream build of Google WebRTC) for body-double peer media.
    // Demo/simulator path remains if init fails on a device.
    implementation("io.getstream:stream-webrtc-android:1.1.3")

    // Firebase BOM + SDKs only when google-services.json is present.
    // Bridges use reflection so the app still compiles/runs without Firebase.
    if (hasGoogleServices) {
        implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
        implementation("com.google.firebase:firebase-auth-ktx")
        implementation("com.google.firebase:firebase-firestore-ktx")
        implementation("com.google.firebase:firebase-crashlytics-ktx")
    }

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // Unit + Compose tests
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
}
