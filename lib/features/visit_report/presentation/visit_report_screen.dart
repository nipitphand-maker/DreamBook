import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/premium_gate.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/visit_report/data/visit_summary_service.dart';
import 'package:dreambook/features/visit_report/presentation/pdf_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

/// Visit Report builder screen — premium feature.
///
/// Self-gated via [PremiumGate] so direct deep-links to `/visit-report`
/// cannot bypass the paywall even if the caller skips the upstream gate
/// in [_VisitPdfButton].
class VisitReportScreen extends ConsumerStatefulWidget {
  const VisitReportScreen({super.key});

  @override
  ConsumerState<VisitReportScreen> createState() => _VisitReportScreenState();
}

class _VisitReportScreenState extends ConsumerState<VisitReportScreen> {
  int _rangeDays = 7;
  final _concernsController = TextEditingController();
  bool _isGenerating = false;

  @override
  void dispose() {
    _concernsController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) return;
    setState(() => _isGenerating = true);
    try {
      final service = ref.read(visitSummaryServiceProvider);
      final data =
          await service.buildSummary(babyId: babyId, rangeDays: _rangeDays);
      final raw = _concernsController.text.trim();
      final pdf = buildVisitPdf(data, concerns: raw.isEmpty ? null : raw);
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'dreambook-visit-${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.visitReportErrorGenerate),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.visitReportTitle)),
      body: PremiumGate(
        lockedChild: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  size: 48,
                  color: AppColors.inkSecondary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.visitReportLockedMessage,
                  style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.premium),
                  child: Text(l10n.premiumCtaBuy),
                ),
              ],
            ),
          ),
        ),
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.visitReportDateRangeLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Center(
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 7, label: Text(l10n.visitReportRangeDays('7'))),
                  ButtonSegment(value: 14, label: Text(l10n.visitReportRangeDays('14'))),
                  ButtonSegment(value: 30, label: Text(l10n.visitReportRangeDays('30'))),
                ],
                selected: {_rangeDays},
                onSelectionChanged: (s) =>
                    setState(() => _rangeDays = s.first),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _concernsController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: l10n.visitReportConcernsLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_isGenerating ? l10n.visitReportSharing : l10n.visitReportGenerateCta),
              onPressed: _isGenerating ? null : _generate,
            ),
          ],
        ),
      ),
    ),
    );
  }
}
