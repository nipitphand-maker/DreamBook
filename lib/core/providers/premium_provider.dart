import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kForcePremium = bool.fromEnvironment('FORCE_PREMIUM');

/// SharedPreferences key for the last entitlement we observed online. If a
/// paying user opens the app offline (e.g. on a plane at 3 AM) and the RC
/// network call fails, we honour this cached truth rather than silently
/// locking them out of premium features they have already paid for.
const _kLastKnownPremiumKey = 'rc.last_known_premium';

/// True when the user holds an active `premium` RevenueCat entitlement.
///
/// Network errors do NOT silently downgrade a paying user to free. The
/// provider remembers the last successful entitlement state and returns it
/// when RC is unreachable. Pass `--dart-define=FORCE_PREMIUM=true` at build
/// time to unlock all premium features unconditionally (internal builds).
final isPremiumProvider = FutureProvider<bool>((_) async {
  if (_kForcePremium) return true;
  try {
    final info = await Purchases.getCustomerInfo();
    final isPremium = info.entitlements.active.containsKey('premium');
    unawaited(_persistLastKnown(isPremium));
    return isPremium;
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.networkError ||
        code == PurchasesErrorCode.offlineConnectionError) {
      // RC unreachable — honour the last entitlement we observed online.
      // Defaults to false if we have never reached RC successfully yet.
      return _loadLastKnown();
    }
    debugPrint('[premium] getCustomerInfo failed: code=$code message=${e.message}');
    return _loadLastKnown();
  } catch (e, st) {
    debugPrint('[premium] unexpected error: $e\n$st');
    return _loadLastKnown();
  }
});

Future<void> _persistLastKnown(bool isPremium) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLastKnownPremiumKey, isPremium);
  } catch (e) {
    debugPrint('[premium] failed to persist last-known state: $e');
  }
}

Future<bool> _loadLastKnown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLastKnownPremiumKey) ?? false;
  } catch (_) {
    return false;
  }
}
