import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Throws if not overridden — main.dart must override this with the
/// loaded SharedPreferences instance before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('Must be overridden in main()'),
);
