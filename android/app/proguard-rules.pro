# Flutter and plugin consumer rules are supplied by their dependencies.
# Keep this file for app-specific R8 rules when adding new native SDKs.

# google_mlkit_text_recognition references optional script-specific
# recognizers even when the app only uses TextRecognitionScript.latin.
# Those optional artifacts are intentionally not bundled, so suppress
# R8 missing-class warnings for them instead of increasing APK size.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
