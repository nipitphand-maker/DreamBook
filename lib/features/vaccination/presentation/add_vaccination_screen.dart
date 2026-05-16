import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/vaccination/data/vaccination_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Add a new vaccination record for [babyId]. Pops with the inserted
/// [VaccinationRecord] on success.
class AddVaccinationScreen extends ConsumerStatefulWidget {
  const AddVaccinationScreen({super.key, required this.babyId});

  final String babyId;

  /// CDC + WHO common pediatric vaccines. Used as autocomplete hints —
  /// users can still type a free-form name (e.g. regional schedules).
  static const _suggestions = <String>[
    'Hepatitis B (Hep B)',
    'Rotavirus (RV)',
    'DTaP',
    'Hib',
    'PCV (Pneumococcal)',
    'IPV (Polio)',
    'Flu (Influenza)',
    'MMR',
    'Varicella (Chickenpox)',
    'Hepatitis A (Hep A)',
    'Tdap',
    'HPV',
    'MenACWY (Meningococcal)',
    'COVID-19',
    'BCG',
  ];

  @override
  ConsumerState<AddVaccinationScreen> createState() =>
      _AddVaccinationScreenState();
}

class _AddVaccinationScreenState
    extends ConsumerState<AddVaccinationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vaccineCtrl = TextEditingController();
  final _clinicCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late DateTime _givenOn;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _givenOn = DateTime.now();
  }

  @override
  void dispose() {
    _vaccineCtrl.dispose();
    _clinicCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _givenOn,
      // Babies vaccinate within ~2 years of birth — allow up to 5 years
      // back for late entry, no future dates (you can't log a future shot).
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _givenOn = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final record =
          await ref.read(vaccinationRepositoryProvider).insert(
                babyId: widget.babyId,
                vaccineName: _vaccineCtrl.text.trim(),
                givenOn: _givenOn,
                clinic: _clinicCtrl.text.trim().isEmpty
                    ? null
                    : _clinicCtrl.text.trim(),
                note: _notesCtrl.text.trim().isEmpty
                    ? null
                    : _notesCtrl.text.trim(),
              );
      if (!mounted) return;
      Navigator.of(context).pop(record);
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
    final dateLabel = DateFormat.yMMMd().format(_givenOn);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(l10n.vaccinationAddVaccine)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // --- Vaccine name (autocomplete) ---
              Autocomplete<String>(
                optionsBuilder: (textValue) {
                  final input = textValue.text.trim().toLowerCase();
                  if (input.isEmpty) {
                    return AddVaccinationScreen._suggestions;
                  }
                  return AddVaccinationScreen._suggestions
                      .where((s) => s.toLowerCase().contains(input));
                },
                onSelected: (selection) {
                  _vaccineCtrl.text = selection;
                },
                fieldViewBuilder: (
                  context,
                  fieldController,
                  fieldFocus,
                  onSubmit,
                ) {
                  // Wire the autocomplete's own controller to ours, since
                  // _vaccineCtrl is what we read at save-time. Listen so any
                  // free-form typing also updates _vaccineCtrl.
                  fieldController.addListener(() {
                    if (_vaccineCtrl.text != fieldController.text) {
                      _vaccineCtrl.text = fieldController.text;
                    }
                  });
                  return TextFormField(
                    controller: fieldController,
                    focusNode: fieldFocus,
                    decoration: InputDecoration(
                      labelText: l10n.vaccinationVaccineName,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return l10n.vaccinationVaccineNameRequired;
                      }
                      return null;
                    },
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // --- Given on (date picker row) ---
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(AppRadii.xs),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.vaccinationDateLabel,
                    border: const OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateLabel,
                          style: AppTypography.bodyLarge(
                            color: AppColors.inkPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: AppColors.inkSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // --- Clinic (optional) ---
              TextFormField(
                controller: _clinicCtrl,
                decoration: InputDecoration(
                  labelText: l10n.vaccinationClinicLabel,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),

              // --- Notes (optional, multi-line) ---
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText: l10n.vaccinationNotesLabel,
                  border: const OutlineInputBorder(),
                ),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Save CTA ---
              SizedBox(
                height: AppSpacing.minTouchTarget,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.vaccinationSaveCta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
