# Flutter-specific ProGuard rules

# Keep Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep annotations
-keepattributes *Annotation*

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }
