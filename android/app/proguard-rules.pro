#######################
# Flutter & Dart rules
#######################
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class io.flutter.plugins.** { *; }

#######################
# MediaPipe core rules
#######################
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep native methods (critical for MediaPipe JNI)
-keepclasseswithmembers class * {
    native <methods>;
}

# Keep Google / Camera dependencies
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class androidx.** { *; }
-dontwarn androidx.**

#######################
# Fix for "no caller found on stack"
#######################
-keep class com.google.mediapipe.framework.Graph { *; }
-keep class com.google.mediapipe.components.FrameProcessor { *; }

#######################
# Optional performance optimization
#######################
-dontoptimize
-dontpreverify
