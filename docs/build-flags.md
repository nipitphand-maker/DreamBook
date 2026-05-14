# DreamBook build flags

## Release-only mandatory flags (per spec §6.1 item 2)

When building APK / IPA for release:

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
flutter build ios --release --obfuscate --split-debug-info=build/symbols
```

`--obfuscate` and `--split-debug-info` together rewrite Dart symbol names
and emit a `.symbols` file in `build/symbols/` for later crash decoding.
Without these flags, function/class names are visible in `strings` / apktool
analysis of the binary.

## ProGuard

Android release builds use `android/app/proguard-rules.pro` (linked from
`android/app/build.gradle.kts` `release { proguardFiles(...) }`). Keep rules cover
sqflite_sqlcipher, flutter_secure_storage, purchases_flutter, and Flutter
plugin glue. Minification (`isMinifyEnabled = true`) is OFF until a real
release signing config replaces the debug-key fallback.

## Symbols storage

`build/symbols/` is gitignored. Upload to Crashlytics (Plan F) or archive
internally per release tag for crash decoding.
