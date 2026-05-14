import 'dart:async';

import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // Time state
  bool _isPast = false;
  // Offset in minutes behind now (must be <= 240 and >= 0)
  int _pastOffsetMinutes = 0;

  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime? get _occurredAt {
    if (!_isPast || _pastOffsetMinutes == 0) return null;
    return DateTime.now().subtract(Duration(minutes: _pastOffsetMinutes));
  }

  String _formatOffset() {
    if (_pastOffsetMinutes == 0) return 'Now';
    final h = _pastOffsetMinutes ~/ 60;
    final m = _pastOffsetMinutes % 60;
    if (h == 0) return '${m}m ago';
    if (m == 0) return '${h}h ago';
    return '${h}h ${m}m ago';
  }

  Future<void> _save() async {
    if (_selectedType == null) return;

    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No baby selected')),
      );
      return;
    }

    final repo = ref.read(diaperRepositoryProvider);
    final note =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    await repo.insert(
      babyId: babyId,
      type: _selectedType!,
      occurredAt: _occurredAt,
      note: note,
    );

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedType != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Diaper')),
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
                      label: 'Pee',
                      color: Colors.blue.shade100,
                      selected: _selectedType == DiaperType.pee,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.pee),
                    ),
                    _TypeButton(
                      icon: Icons.circle,
                      label: 'Poop',
                      color: Colors.brown.shade100,
                      selected: _selectedType == DiaperType.poop,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.poop),
                    ),
                    _TypeButton(
                      icon: Icons.water_drop,
                      label: 'Mixed',
                      color: Colors.purple.shade100,
                      selected: _selectedType == DiaperType.mixed,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.mixed),
                    ),
                    _TypeButton(
                      icon: Icons.do_not_disturb_alt_outlined,
                      label: 'Dry',
                      color: Colors.grey.shade100,
                      selected: _selectedType == DiaperType.dry,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.dry),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Time stepper
              _TimeSection(
                isPast: _isPast,
                pastOffsetMinutes: _pastOffsetMinutes,
                formattedOffset: _formatOffset(),
                onShowPast: () => setState(() {
                  _isPast = true;
                  _pastOffsetMinutes = 15;
                }),
                onDecrease: () => setState(() {
                  _pastOffsetMinutes =
                      (_pastOffsetMinutes - 15).clamp(0, 240);
                  if (_pastOffsetMinutes == 0) _isPast = false;
                }),
                onIncrease: () => setState(() {
                  _pastOffsetMinutes =
                      (_pastOffsetMinutes + 15).clamp(0, 240);
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Save button
              FilledButton(
                onPressed: canSave ? _save : null,
                child: const Text('Save'),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeSection extends StatelessWidget {
  const _TimeSection({
    required this.isPast,
    required this.pastOffsetMinutes,
    required this.formattedOffset,
    required this.onShowPast,
    required this.onDecrease,
    required this.onIncrease,
  });

  final bool isPast;
  final int pastOffsetMinutes;
  final String formattedOffset;
  final VoidCallback onShowPast;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!isPast) {
      return Row(
        children: [
          Text(
            'Time: Now',
            style: AppTypography.bodyLarge(color: AppColors.inkPrimary),
          ),
          const Spacer(),
          TextButton(
            onPressed: onShowPast,
            child: const Text('Log as past'),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filled(
          onPressed: pastOffsetMinutes > 0 ? onDecrease : null,
          icon: const Icon(Icons.remove),
          style: IconButton.styleFrom(backgroundColor: scheme.primary),
        ),
        const SizedBox(width: AppSpacing.lg),
        Text(
          formattedOffset,
          style: AppTypography.numeric(
            size: 20,
            weight: FontWeight.w600,
            color: AppColors.inkPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        IconButton.filled(
          onPressed: pastOffsetMinutes < 240 ? onIncrease : null,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(backgroundColor: scheme.primary),
        ),
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
