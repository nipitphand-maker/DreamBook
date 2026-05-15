import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/design_tokens.dart';
import '../data/baby_repository.dart';
import '../data/current_baby_provider.dart';

/// Form screen for adding a new baby, or editing an existing one.
///
/// Pass [baby] to enter edit mode — fields are pre-populated and Save calls
/// [BabyRepository.update] instead of [BabyRepository.insert].
class AddBabyScreen extends ConsumerStatefulWidget {
  const AddBabyScreen({super.key, this.baby});

  final Baby? baby;

  @override
  ConsumerState<AddBabyScreen> createState() => _AddBabyScreenState();
}

class _AddBabyScreenState extends ConsumerState<AddBabyScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.baby?.name ?? '');
  late final _nicknameCtrl = TextEditingController(text: widget.baby?.nickname ?? '');

  late DateTime? _dob = widget.baby?.dob;
  late BabySex _sex = widget.baby?.sex ?? BabySex.unspecified;
  late PreferredUnit _unit = widget.baby?.preferredUnit ?? PreferredUnit.oz;
  bool _saving = false;

  bool get _isEdit => widget.baby != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) return;
    setState(() => _saving = true);

    final repo = ref.read(babyRepositoryProvider);
    final nickname = _nicknameCtrl.text.trim();

    try {
      if (_isEdit) {
        await repo.update(
          id: widget.baby!.id,
          name: _nameCtrl.text.trim(),
          dob: _dob!,
          sex: _sex,
          preferredUnit: _unit,
          nickname: nickname.isEmpty ? null : nickname,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final baby = await repo.insert(
          name: _nameCtrl.text.trim(),
          dob: _dob!,
          sex: _sex,
          preferredUnit: _unit,
          nickname: nickname.isEmpty ? null : nickname,
        );
        await ref.read(currentBabyIdProvider.notifier).select(baby.id);
        if (!mounted) return;
        Navigator.of(context).pop(baby);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorGeneric)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat.yMMMd(Localizations.localeOf(context).toString());

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.babiesEditBaby : l10n.babiesAddBaby),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextFormField(
                controller: _nameCtrl,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.babiesNameLabel,
                ),
                textInputAction: TextInputAction.next,
                autofocus: true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return l10n.babiesNameLabel;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _nicknameCtrl,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: l10n.babiesNicknameLabel,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.babiesDobLabel,
                style: AppTypography.labelLarge(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.xs),
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _dob == null
                        ? l10n.babiesDobLabel
                        : dateFmt.format(_dob!),
                    style: AppTypography.bodyLarge(
                      color: _dob == null
                          ? AppColors.inkSecondary
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.babiesSexLabel,
                style: AppTypography.labelLarge(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<BabySex>(
                segments: [
                  ButtonSegment(
                    value: BabySex.male,
                    label: Text(l10n.babiesSexBoy),
                  ),
                  ButtonSegment(
                    value: BabySex.female,
                    label: Text(l10n.babiesSexGirl),
                  ),
                  ButtonSegment(
                    value: BabySex.unspecified,
                    label: Text(l10n.babiesSexOther),
                  ),
                ],
                selected: <BabySex>{_sex},
                onSelectionChanged: (sel) {
                  setState(() => _sex = sel.first);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.babiesUnitLabel,
                style: AppTypography.labelLarge(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<PreferredUnit>(
                segments: [
                  ButtonSegment(
                    value: PreferredUnit.oz,
                    label: Text(l10n.unitOz),
                  ),
                  ButtonSegment(
                    value: PreferredUnit.ml,
                    label: Text(l10n.unitMl),
                  ),
                ],
                selected: <PreferredUnit>{_unit},
                onSelectionChanged: (sel) {
                  setState(() => _unit = sel.first);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: (_saving || _dob == null) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? l10n.babiesUpdateCta : l10n.babiesSaveCta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
