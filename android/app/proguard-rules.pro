# Look After release R8 rules
-keep class com.lookafter.core.** { *; }
-keepclassmembers class com.lookafter.core.** { *; }

# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class com.lookafter.**$$serializer { *; }
-keepclassmembers class com.lookafter.** {
    *** Companion;
}
-keepclasseswithmembers class com.lookafter.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Health Connect / Glance
-dontwarn androidx.health.**
-dontwarn androidx.glance.**

# Keep BuildConfig
-keep class com.lookafter.app.BuildConfig { *; }
