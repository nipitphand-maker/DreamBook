# Plan C-1 hardening (per spec §6.1 item 2).
# Keep classes accessed via JNI / reflection so release R8 doesn't strip them.

# sqflite_sqlcipher
-keep class net.zetetic.database.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.davidmedenjak.sqfliteSqlcipher.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# purchases_flutter (Plan D dep; safe to keep now to avoid forgetting later)
-keep class com.revenuecat.** { *; }

# Cryptography (Dart) bridges
-keep class io.flutter.plugin.** { *; }

# Generic safety — don't obfuscate Flutter plugin glue layer
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * extends io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }
