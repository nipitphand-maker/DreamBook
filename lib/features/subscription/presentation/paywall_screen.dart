import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/premium_provider.dart';
import '../../../core/theme/design_tokens.dart';

/// Plan D paywall.
///
/// Pulls the `default` offering from RevenueCat and renders three package
/// cards (Yearly / Monthly / Lifetime). Yearly is the default selection
/// and is highlighted as "Best Value" with a saving badge.
///
/// On purchase or restore success we invalidate [isPremiumProvider] so
/// every premium gate re-evaluates with the fresh entitlement state, then
/// pop the screen.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Future<Offering?>? _offeringFuture;
  PackageType _selectedType = PackageType.annual;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _offeringFuture = _loadOffering();
  }

  Future<Offering?> _loadOffering() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.getOffering('default') ?? offerings.current;
    } catch (_) {
      return null;
    }
  }

  Package? _packageFor(Offering offering, PackageType type) {
    for (final pkg in offering.availablePackages) {
      if (pkg.packageType == type) return pkg;
    }
    return null;
  }

  Future<void> _purchase(Offering offering) async {
    final pkg = _packageFor(offering, _selectedType);
    if (pkg == null) return;
    setState(() => _isLoading = true);
    try {
      final info = await Purchases.purchasePackage(pkg);
      final isPremium = info.entitlements.active.containsKey('premium');
      // Invalidate so PremiumGate + features pick up the new entitlement.
      ref.invalidate(isPremiumProvider);
      if (!mounted) return;
      if (isPremium) {
        context.pop();
      } else {
        _showSnack(context.l10n.premiumPurchaseError);
      }
    } on PlatformException catch (e) {
      // User-cancelled is not an error worth surfacing.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code != PurchasesErrorCode.purchaseCancelledError && mounted) {
        _showSnack(context.l10n.premiumPurchaseError);
      }
    } catch (_) {
      if (mounted) _showSnack(context.l10n.premiumPurchaseError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _isLoading = true);
    try {
      final info = await Purchases.restorePurchases();
      final isPremium = info.entitlements.active.containsKey('premium');
      ref.invalidate(isPremiumProvider);
      if (!mounted) return;
      if (isPremium) {
        _showSnack(context.l10n.premiumRestoreSuccess);
        context.pop();
      } else {
        _showSnack(context.l10n.premiumRestoreNothing);
      }
    } catch (_) {
      if (mounted) _showSnack(context.l10n.premiumPurchaseError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
          tooltip: l10n.actionCancel,
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Offering?>(
          future: _offeringFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final offering = snapshot.data;
            if (offering == null || offering.availablePackages.isEmpty) {
              return _ErrorState(
                message: l10n.premiumLoadError,
                onRetry: () => setState(() {
                  _offeringFuture = _loadOffering();
                }),
              );
            }
            return _PaywallBody(
              offering: offering,
              selectedType: _selectedType,
              onSelectType: (t) => setState(() => _selectedType = t),
              isLoading: _isLoading,
              onPurchase: () => _purchase(offering),
              onRestore: _restore,
            );
          },
        ),
      ),
    );
  }
}

class _PaywallBody extends StatelessWidget {
  const _PaywallBody({
    required this.offering,
    required this.selectedType,
    required this.onSelectType,
    required this.isLoading,
    required this.onPurchase,
    required this.onRestore,
  });

  final Offering offering;
  final PackageType selectedType;
  final ValueChanged<PackageType> onSelectType;
  final bool isLoading;
  final VoidCallback onPurchase;
  final VoidCallback onRestore;

  Package? _findPackage(PackageType type) {
    for (final pkg in offering.availablePackages) {
      if (pkg.packageType == type) return pkg;
    }
    return null;
  }

  /// Compute "Save N%" by comparing the per-month cost of yearly vs monthly
  /// in their store currencies. Falls back to spec default 58% when one
  /// side is missing.
  int _yearlySavingsPercent() {
    final yearly = _findPackage(PackageType.annual);
    final monthly = _findPackage(PackageType.monthly);
    if (yearly == null || monthly == null) return 58;
    final monthlyPrice = monthly.storeProduct.price;
    final yearlyPerMonth = yearly.storeProduct.price / 12.0;
    if (monthlyPrice <= 0) return 58;
    final ratio = 1.0 - (yearlyPerMonth / monthlyPrice);
    final pct = (ratio * 100).round();
    return pct.clamp(0, 99);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final yearly = _findPackage(PackageType.annual);
    final monthly = _findPackage(PackageType.monthly);
    final lifetime = _findPackage(PackageType.lifetime);
    final selectedPkg = _findPackage(selectedType);
    final ctaLabel = selectedType == PackageType.annual
        ? l10n.premiumCtaTrial
        : l10n.premiumCtaBuy;
    final savingsPct = _yearlySavingsPercent();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            // --- Hero ---
            Text(
              l10n.premiumPaywallHeadline,
              style: AppTypography.displayLarge(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.premiumPaywallSubtitle,
              style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),

            // --- Feature bullets ---
            _FeatureRow(
              icon: Icons.family_restroom_outlined,
              label: l10n.premiumFeatureBabies,
            ),
            const SizedBox(height: AppSpacing.md),
            _FeatureRow(
              icon: Icons.picture_as_pdf_outlined,
              label: l10n.premiumFeaturePdf,
            ),
            const SizedBox(height: AppSpacing.md),
            _FeatureRow(
              icon: Icons.groups_outlined,
              label: l10n.premiumFeatureCaregivers,
            ),
            const SizedBox(height: AppSpacing.xl),

            // --- Package cards ---
            if (yearly != null)
              _PackageCard(
                title: l10n.premiumPriceYearly,
                priceLine: yearly.storeProduct.priceString,
                subtitle: _yearlyPerMonth(context, yearly),
                badge: l10n.premiumBestValue,
                savingsBadge: l10n.premiumSaveBadge(savingsPct),
                selected: selectedType == PackageType.annual,
                onTap: () => onSelectType(PackageType.annual),
              ),
            if (yearly != null) const SizedBox(height: AppSpacing.sm),
            if (monthly != null)
              _PackageCard(
                title: l10n.premiumPriceMonthly,
                priceLine: monthly.storeProduct.priceString,
                subtitle: null,
                selected: selectedType == PackageType.monthly,
                onTap: () => onSelectType(PackageType.monthly),
              ),
            if (monthly != null) const SizedBox(height: AppSpacing.sm),
            if (lifetime != null)
              _PackageCard(
                title: l10n.premiumPriceLifetime,
                priceLine: lifetime.storeProduct.priceString,
                subtitle: null,
                selected: selectedType == PackageType.lifetime,
                onTap: () => onSelectType(PackageType.lifetime),
              ),

            const SizedBox(height: AppSpacing.xl),

            // --- CTA ---
            SizedBox(
              height: AppSpacing.minTouchTarget,
              child: FilledButton(
                onPressed:
                    (isLoading || selectedPkg == null) ? null : onPurchase,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(ctaLabel),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // --- Restore ---
            TextButton(
              onPressed: isLoading ? null : onRestore,
              child: Text(l10n.premiumRestore),
            ),

            const SizedBox(height: AppSpacing.md),

            // --- Legal ---
            Text(
              l10n.premiumLegal,
              style: AppTypography.bodyMedium(
                color: AppColors.inkSecondary,
              ).copyWith(fontSize: 12, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }

  String? _yearlyPerMonth(BuildContext context, Package yearly) {
    final perMonth = yearly.storeProduct.price / 12.0;
    if (perMonth <= 0) return null;
    final currency = yearly.storeProduct.currencyCode;
    final formatted = _formatCurrency(perMonth, currency);
    return context.l10n.premiumYearlyPerMonth(formatted);
  }

  String _formatCurrency(double value, String currencyCode) {
    // Avoid bringing intl number-format setup into Plan D — RC already
    // returns a locale-correct `priceString` for the main price. For the
    // per-month derivative we use a simple symbol fallback that fits the
    // USD launch market (primary) and an explicit code suffix elsewhere.
    final fixed = value.toStringAsFixed(2);
    if (currencyCode.toUpperCase() == 'USD') return '\$$fixed';
    if (currencyCode.toUpperCase() == 'THB') return '฿$fixed';
    return '$fixed $currencyCode';
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.lightPrimary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: AppColors.lavender700),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              label,
              style: AppTypography.bodyLarge(color: AppColors.inkPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.title,
    required this.priceLine,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.savingsBadge,
  });

  final String title;
  final String priceLine;
  final String? subtitle;
  final String? badge;
  final String? savingsBadge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? AppColors.lavender700 : AppColors.neutralMuted;
    final borderWidth = selected ? 2.0 : 1.0;

    return Semantics(
      button: true,
      selected: selected,
      label: '$title $priceLine${subtitle == null ? '' : ', $subtitle'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.lightPrimary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              // Radio indicator.
              _RadioDot(selected: selected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTypography.titleLarge(
                              color: AppColors.inkPrimary,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _Pill(text: badge!, accent: true),
                        ],
                        if (savingsBadge != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _Pill(text: savingsBadge!, accent: false),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceLine,
                      style: AppTypography.bodyLarge(
                        color: AppColors.inkPrimary,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTypography.bodyMedium(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.lavender700 : AppColors.inkSecondary,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.lavender700,
              ),
            )
          : null,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.accent});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bg =
        accent ? AppColors.lavender700 : AppColors.lightAccent.withValues(alpha: 0.6);
    final fg = accent ? Colors.white : AppColors.peach700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppTypography.labelLarge(color: fg).copyWith(fontSize: 11),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 48, color: AppColors.inkSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge(color: AppColors.inkPrimary),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.actionRetry),
          ),
        ],
      ),
    );
  }
}
