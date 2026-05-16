import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _initialKey(String babyId) => 'diaper.stock.$babyId.initial';
String _currentKey(String babyId) => 'diaper.stock.$babyId.current';

/// Tracks the user's per-baby diaper pack inventory.
///
/// Stored in SharedPreferences (privacy-first, no sync) — restock count is
/// just a UX nudge, not data the caregiver needs cross-device.
@immutable
class DiaperStock {
  const DiaperStock({required this.initial, required this.current});

  /// Pack size from the last "Restock" action.
  final int initial;

  /// Remaining count, decremented automatically on each diaper log.
  /// Clamped to >= 0; never goes negative.
  final int current;

  /// 0.0–1.0. Returns 0 if [initial] is 0 (defensive).
  double get fraction => initial == 0 ? 0.0 : current / initial;

  /// User is about to run out (≤ 10% OR 0 left).
  bool get isCritical => current == 0 || fraction <= 0.10;

  /// Running low (10–25% range).
  bool get isWarning => !isCritical && fraction <= 0.25;

  /// Banner should be visible (warning, critical, or empty).
  bool get shouldAlert => isCritical || isWarning;
}

/// Reads the current diaper stock for [babyId], or null if the user
/// hasn't enabled tracking yet (= no banner, no auto-decrement).
final diaperStockProvider =
    Provider.family<DiaperStock?, String>((ref, babyId) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final initial = prefs.getInt(_initialKey(babyId));
  final current = prefs.getInt(_currentKey(babyId));
  if (initial == null || current == null) return null;
  return DiaperStock(initial: initial, current: current);
});

/// Imperative helpers — call after writes invalidate the provider so the
/// banner re-renders.
class DiaperStockService {
  DiaperStockService._();

  /// Set both [initial] and [current] to [packSize] (a fresh restock).
  static Future<void> restock(
    SharedPreferences prefs,
    String babyId,
    int packSize,
  ) async {
    await prefs.setInt(_initialKey(babyId), packSize);
    await prefs.setInt(_currentKey(babyId), packSize);
  }

  /// Decrement current by 1, clamped at 0. No-op if tracking not enabled.
  /// Called from diaper_repository after a successful insert.
  static Future<void> decrement(
    SharedPreferences prefs,
    String babyId,
  ) async {
    final current = prefs.getInt(_currentKey(babyId));
    if (current == null) return;
    final next = current > 0 ? current - 1 : 0;
    await prefs.setInt(_currentKey(babyId), next);
  }

  /// Manually correct the current count (kept ≤ initial, ≥ 0).
  static Future<void> setCurrent(
    SharedPreferences prefs,
    String babyId,
    int next,
  ) async {
    final initial = prefs.getInt(_initialKey(babyId));
    if (initial == null) return;
    final clamped = next < 0 ? 0 : (next > initial ? initial : next);
    await prefs.setInt(_currentKey(babyId), clamped);
  }

  /// Disable tracking — banner hides, no auto-decrement.
  ///
  /// Also resets the hint-dismissed flag so the Home discovery hint can
  /// reappear (the user has actively chosen to stop tracking, so the hint
  /// is no longer noise — they may want to re-enable later).
  static Future<void> clear(SharedPreferences prefs, String babyId) async {
    await prefs.remove(_initialKey(babyId));
    await prefs.remove(_currentKey(babyId));
    await prefs.remove('diaper.stock.hint.dismissed');
  }
}
