import 'dart:ui' as ui;

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/visit_report/data/visit_summary_service.dart';
import 'package:dreambook/features/visit_report/presentation/pdf_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class VisitReportScreen extends ConsumerStatefulWidget {
  const VisitReportScreen({super.key});

  @override
  ConsumerState<VisitReportScreen> createState() => _VisitReportScreenState();
}

class _VisitReportScreenState extends ConsumerState<VisitReportScreen> {
  int _rangeDays = 7;
  DateTimeRange? _customRange;
  final _concernsController = TextEditingController();
  bool _isGenerating = false;

  // Preview state
  Uint8List? _previewBytes;
  bool _previewLoading = false;
  bool _previewFailed = false;

  @override
  void dispose() {
    _concernsController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  DateTime get _effectiveStart {
    if (_customRange != null) return _customRange!.start;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: _rangeDays - 1));
  }

  DateTime get _effectiveEnd {
    if (_customRange != null) return _customRange!.end;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<pw.Font?> _loadFont(String asset) async {
    try {
      return pw.Font.ttf(await rootBundle.load(asset));
    } catch (_) {
      return null;
    }
  }

  // ── PDF generation (premium) ──────────────────────────────────────────────

  Future<void> _generate() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) return;
    setState(() => _isGenerating = true);
    try {
      final service = ref.read(visitSummaryServiceProvider);
      final data = await service.buildSummary(
        babyId: babyId,
        rangeStart: _effectiveStart,
        rangeEnd: _effectiveEnd,
      );
      final raw = _concernsController.text.trim();
      final pdf = buildVisitPdf(
        data,
        concerns: raw.isEmpty ? null : raw,
        regularFont: await _loadFont('assets/fonts/IBMPlexSansThai-Regular.ttf'),
        boldFont: await _loadFont('assets/fonts/IBMPlexSansThai-SemiBold.ttf'),
      );
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'dreambook-visit-${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.visitReportErrorGenerate)),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── PDF preview rasterisation (free) ─────────────────────────────────────

  Future<void> _loadPreview() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) return;
    if (_previewLoading) return;
    setState(() => _previewLoading = true);
    try {
      final service = ref.read(visitSummaryServiceProvider);
      final data = await service.buildSummary(
        babyId: babyId,
        rangeStart: _effectiveStart,
        rangeEnd: _effectiveEnd,
      );
      final pdf = buildVisitPdf(
        data,
        regularFont:
            await _loadFont('assets/fonts/IBMPlexSansThai-Regular.ttf'),
        boldFont:
            await _loadFont('assets/fonts/IBMPlexSansThai-SemiBold.ttf'),
      );
      final pdfBytes = await pdf.save();
      await for (final raster
          in Printing.raster(pdfBytes, pages: [0], dpi: 120)) {
        final png = await raster.toPng();
        if (mounted) setState(() => _previewBytes = png);
        break;
      }
    } catch (_) {
      if (mounted) setState(() => _previewFailed = true);
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  // ── Custom date picker ────────────────────────────────────────────────────

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 13)),
            end: now,
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _previewBytes = null;
      _previewFailed = false;
    });
  }

  void _selectPreset(int days) {
    setState(() {
      _rangeDays = days;
      _customRange = null;
      _previewBytes = null;
      _previewFailed = false;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isPremiumAsync = ref.watch(isPremiumProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.visitReportTitle)),
      body: isPremiumAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _LockedBody(onRangeChanged: _selectPreset, rangeDays: _rangeDays, customRange: _customRange, onPickCustom: _pickCustomRange),
        data: (isPremium) => isPremium
            ? _PremiumBody(
                rangeDays: _rangeDays,
                customRange: _customRange,
                concernsController: _concernsController,
                isGenerating: _isGenerating,
                onRangeChanged: _selectPreset,
                onPickCustom: _pickCustomRange,
                onGenerate: _generate,
              )
            : _FreeBody(
                rangeDays: _rangeDays,
                customRange: _customRange,
                previewBytes: _previewBytes,
                previewLoading: _previewLoading,
                previewFailed: _previewFailed,
                onRangeChanged: _selectPreset,
                onPickCustom: _pickCustomRange,
                onLoadPreview: _loadPreview,
              ),
      ),
    );
  }
}

// ── Date range selector (shared) ─────────────────────────────────────────────

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({
    required this.rangeDays,
    required this.customRange,
    required this.onRangeChanged,
    required this.onPickCustom,
  });

  final int rangeDays;
  final DateTimeRange? customRange;
  final ValueChanged<int> onRangeChanged;
  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasCustom = customRange != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visitReportDateRangeLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in [7, 14, 30, 90])
              ChoiceChip(
                label: Text(l10n.visitReportRangeDays(days.toString())),
                selected: !hasCustom && rangeDays == days,
                onSelected: (_) => onRangeChanged(days),
              ),
            ActionChip(
              avatar: Icon(
                Icons.calendar_month_outlined,
                size: 16,
                color: hasCustom
                    ? Theme.of(context).colorScheme.onPrimary
                    : null,
              ),
              label: Text(
                hasCustom
                    ? _fmt(customRange!.start, customRange!.end)
                    : l10n.visitReportRangeCustom,
              ),
              backgroundColor:
                  hasCustom ? Theme.of(context).colorScheme.primary : null,
              labelStyle: hasCustom
                  ? TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary)
                  : null,
              onPressed: onPickCustom,
            ),
          ],
        ),
      ],
    );
  }

  static String _fmt(DateTime s, DateTime e) {
    String d(DateTime dt) =>
        '${dt.day}/${dt.month}/${dt.year.toString().substring(2)}';
    return '${d(s)} – ${d(e)}';
  }
}

// ── Free user body ────────────────────────────────────────────────────────────

class _FreeBody extends ConsumerStatefulWidget {
  const _FreeBody({
    required this.rangeDays,
    required this.customRange,
    required this.previewBytes,
    required this.previewLoading,
    required this.previewFailed,
    required this.onRangeChanged,
    required this.onPickCustom,
    required this.onLoadPreview,
  });

  final int rangeDays;
  final DateTimeRange? customRange;
  final Uint8List? previewBytes;
  final bool previewLoading;
  final bool previewFailed;
  final ValueChanged<int> onRangeChanged;
  final VoidCallback onPickCustom;
  final Future<void> Function() onLoadPreview;

  @override
  ConsumerState<_FreeBody> createState() => _FreeBodyState();
}

class _FreeBodyState extends ConsumerState<_FreeBody> {
  @override
  void initState() {
    super.initState();
    // Kick off preview rasterisation after first frame.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onLoadPreview());
  }

  @override
  void didUpdateWidget(_FreeBody old) {
    super.didUpdateWidget(old);
    // Re-rasterise only when range changes and bytes were cleared (not on error).
    if (widget.previewBytes == null &&
        !widget.previewLoading &&
        !widget.previewFailed) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onLoadPreview());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RangeSelector(
            rangeDays: widget.rangeDays,
            customRange: widget.customRange,
            onRangeChanged: widget.onRangeChanged,
            onPickCustom: widget.onPickCustom,
          ),
          const SizedBox(height: AppSpacing.lg),

          // PDF preview card
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: SizedBox(
              height: 480,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── PDF page render ──────────────────────────────────
                  if (widget.previewLoading && widget.previewBytes == null)
                    Container(
                      color: AppColors.neutralMuted,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  else if (widget.previewBytes != null)
                    Image.memory(
                      widget.previewBytes!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    )
                  else
                    // Fallback: gradient placeholder
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer,
                            scheme.secondaryContainer,
                          ],
                        ),
                      ),
                    ),

                  // ── Frosted-glass blur on bottom 65% ────────────────
                  Positioned(
                    top: 480 * 0.35,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter:
                            ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),

                  // ── Paywall overlay ──────────────────────────────────
                  Positioned(
                    top: 480 * 0.28,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _PaywallOverlay(
                      onUpgrade: () => context.push(AppRoutes.premium),
                      onRestore: () => context.push(AppRoutes.premium),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.visitReportPreviewLabel,
            style: AppTypography.labelLarge(color: AppColors.inkSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PaywallOverlay extends StatelessWidget {
  const _PaywallOverlay({required this.onUpgrade, required this.onRestore});

  final VoidCallback onUpgrade;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 36, color: AppColors.inkSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.visitReportUnlockTitle,
            style: AppTypography.headlineMedium(color: AppColors.inkPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.visitReportUnlockSubtitle,
            style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.premiumTrialBadge,
            style: AppTypography.labelLarge(color: AppColors.lavender700),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onUpgrade,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(l10n.visitReportUpgradeCta),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: onRestore,
            child: Text(l10n.premiumRestore),
          ),
        ],
      ),
    );
  }
}

// ── Premium user body ─────────────────────────────────────────────────────────

class _PremiumBody extends StatelessWidget {
  const _PremiumBody({
    required this.rangeDays,
    required this.customRange,
    required this.concernsController,
    required this.isGenerating,
    required this.onRangeChanged,
    required this.onPickCustom,
    required this.onGenerate,
  });

  final int rangeDays;
  final DateTimeRange? customRange;
  final TextEditingController concernsController;
  final bool isGenerating;
  final ValueChanged<int> onRangeChanged;
  final VoidCallback onPickCustom;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RangeSelector(
            rangeDays: rangeDays,
            customRange: customRange,
            onRangeChanged: onRangeChanged,
            onPickCustom: onPickCustom,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: concernsController,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: l10n.visitReportConcernsLabel,
              hintText: l10n.visitReportConcernsHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            icon: isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(isGenerating
                ? l10n.visitReportSharing
                : l10n.visitReportGenerateCta),
            onPressed: isGenerating ? null : onGenerate,
          ),
        ],
      ),
    );
  }
}

// ── Error/locked body ─────────────────────────────────────────────────────────

class _LockedBody extends StatelessWidget {
  const _LockedBody({
    required this.onRangeChanged,
    required this.rangeDays,
    required this.customRange,
    required this.onPickCustom,
  });

  final ValueChanged<int> onRangeChanged;
  final int rangeDays;
  final DateTimeRange? customRange;
  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RangeSelector(
            rangeDays: rangeDays,
            customRange: customRange,
            onRangeChanged: onRangeChanged,
            onPickCustom: onPickCustom,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => context.push(AppRoutes.premium),
            child: Text(context.l10n.visitReportUpgradeCta),
          ),
        ],
      ),
    );
  }
}
