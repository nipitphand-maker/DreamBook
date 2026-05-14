import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:go_router/go_router.dart';

/// Quick-log diaper — designed for one-handed 3 AM use.
/// Route: /diaper/new
class DiaperLogScreen extends ConsumerStatefulWidget {
  const DiaperLogScreen({super.key});

  @override
  ConsumerState<DiaperLogScreen> createState() => _DiaperLogScreenState();
}

class _DiaperLogScreenState extends ConsumerState<DiaperLogScreen> {
  DiaperType? _selectedType;

  // null = now; non-null = the specific past time the user picked
  DateTime? _loggedAt;

  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLoggedAt() async {
    final now = DateTime.now();
    final initial = _loggedAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!picked.isAfter(now)) {
      setState(() => _loggedAt = picked);
    }
  }

  String _fmtLoggedAt() {
    final t = _loggedAt;
    if (t == null) return context.l10n.loggedAtNow;
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m ago';
    return '${t.day}/${t.month}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_selectedType == null) return;

    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorNoBabyProfile)),
      );
      return;
    }

    final repo = ref.read(diaperRepositoryProvider);
    final note =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    await repo.insert(
      babyId: babyId,
      type: _selectedType!,
      occurredAt: _loggedAt,
      note: note,
    );

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedType != null;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.diaperAppBarTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              // Type selector — 2×2 grid of large tap targets
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _TypeButton(
                      icon: Icons.water_drop_outlined,
                      label: context.l10n.diaperPee,
                      color: AppColors.lightWarning.withValues(alpha: 0.22),
                      selected: _selectedType == DiaperType.pee,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.pee),
                    ),
                    _TypeButton(
                      icon: Icons.circle,
                      label: context.l10n.diaperPoop,
                      color: AppColors.lightAccent.withValues(alpha: 0.35),
                      selected: _selectedType == DiaperType.poop,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.poop),
                    ),
                    _TypeButton(
                      icon: Icons.water_drop,
                      label: context.l10n.diaperMixed,
                      color: AppColors.lightPrimary.withValues(alpha: 0.25),
                      selected: _selectedType == DiaperType.mixed,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.mixed),
                    ),
                    _TypeButton(
                      icon: Icons.do_not_disturb_alt_outlined,
                      label: context.l10n.diaperDry,
                      color: Colors.grey.shade100,
                      selected: _selectedType == DiaperType.dry,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.dry),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Time picker — tap to log as past
              _LoggedAtRow(
                label: _fmtLoggedAt(),
                onTap: _pickLoggedAt,
                onClear: _loggedAt != null
                    ? () => setState(() => _loggedAt = null)
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                maxLength: 240,
                decoration: InputDecoration(
                  labelText: context.l10n.diaperNotesOptional,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Save button
              FilledButton(
                onPressed: canSave ? _save : null,
                child: Text(context.l10n.actionSave),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable row showing when the event was logged.
/// Tap → date picker → time picker. "×" resets to now.
class _LoggedAtRow extends StatelessWidget {
  const _LoggedAtRow({
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.schedule, size: 18, color: AppColors.inkSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '${context.l10n.loggedAtLabel}: ',
          style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            label,
            style: AppTypography.bodyMedium(color: AppColors.lavender700)
                .copyWith(decoration: TextDecoration.underline),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: AppSpacing.xs),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 16, color: AppColors.inkSecondary),
          ),
        ],
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(
                    color: AppColors.lavender700,
                    width: 3,
                  ),
                )
              : null,
          constraints:
              const BoxConstraints(minHeight: AppSpacing.quickLogButton),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: AppColors.inkPrimary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.titleLarge(color: AppColors.inkPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
