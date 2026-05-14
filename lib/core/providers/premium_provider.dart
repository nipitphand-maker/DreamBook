import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// True when the user holds an active `premium` RevenueCat entitlement.
///
/// Wrapped in try/catch so that an uninitialised RC SDK (e.g. emulator
/// without Play Services, or `Purchases.configure` failed during boot)
/// resolves to `false` rather than crashing the gate / Home screen.
///
/// PremiumGate + every feature team imports this — the public API
/// (`FutureProvider<bool>`) must remain stable across plans.
final isPremiumProvider = FutureProvider<bool>((_) async {
  try {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey('premium');
  } catch (_) {
    return false;
  }
});
