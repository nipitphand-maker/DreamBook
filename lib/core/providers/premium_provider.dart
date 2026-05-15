import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const _kForcePremium = bool.fromEnvironment('FORCE_PREMIUM');

/// True when the user holds an active `premium` RevenueCat entitlement.
/// Pass `--dart-define=FORCE_PREMIUM=true` at build time to unlock all
/// premium features unconditionally (for internal testing builds).
final isPremiumProvider = FutureProvider<bool>((_) async {
  if (_kForcePremium) return true;
  try {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey('premium');
  } catch (_) {
    return false;
  }
});
