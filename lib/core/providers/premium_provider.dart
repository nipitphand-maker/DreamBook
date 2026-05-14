import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the user holds an active 'premium' RevenueCat entitlement.
///
/// Stub — replaced by real RC implementation in Plan D (Lead team).
/// All premium gate widgets import this; the API surface must not change.
final isPremiumProvider = FutureProvider<bool>((_) async => false);
