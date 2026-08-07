plugins {
    // Keep versions aligned for AGP + Kotlin + Compose compiler.
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    kotlin("jvm") version "2.0.21" apply false
    kotlin("plugin.serialization") version "2.0.21" apply false
    // Optional Firebase (applied only when app/google-services.json exists).
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}

allprojects {
    group = "com.lookafter"
    version = "0.1.0"
}
