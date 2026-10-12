import 'package:flutter/material.dart';

import '../../../data/models/drug.dart';
import '../../../data/services/dose_calculation_service.dart';

/// Species picker whose options are derived from the selected drug.
///
/// Instead of a hardcoded dog/cat list, the options are the union of the species
/// the app knows about and the species the *dataset* declares for this drug.
/// Species whose data is unusable stay visible but disabled, with the reason
/// shown — an explicitly `null` species block is information a clinician should
/// see, not something to hide.
class SpeciesSelector extends StatelessWidget {
  const SpeciesSelector({
    super.key,
    required this.drug,
    required this.selected,
    required this.onChanged,
    required this.service,
    this.enabled = true,
  });

  /// Currently selected drug, or `null` before a selection is made.
  final Drug? drug;

  /// Canonical species key.
  final String selected;
  final ValueChanged<String> onChanged;
  final DoseCalculationService service;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _buildOptions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.key == selected) ? selected : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Species',
            helperText: 'Only species with usable data can be selected',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.pets_outlined),
          ),
          hint: const Text('Choose a species'),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option.isUsable ? option.key : null,
                enabled: option.isUsable,
                child: _SpeciesRow(option: option, theme: theme),
              ),
          ],
          onChanged: enabled ? (value) {
            if (value == null) return;
            onChanged(value);
          } : null,
        ),
        if (drug != null && _blockedNotes().isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final note in _blockedNotes())
                Chip(
                  avatar: Icon(
                    Icons.block_outlined,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(note),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<_SpeciesOption> _buildOptions() {
    final current = drug;

    // Before a drug is chosen, offer the species the app understands.
    if (current == null) {
      return [
        for (final key in DatasetNormalizer.knownSpecies)
          _SpeciesOption(key: key, isUsable: true, note: null),
      ];
    }

    final keys = <String>{
      ...DatasetNormalizer.knownSpecies,
      ...current.declaredSpecies,
    };

    return [
      for (final key in keys)
        _SpeciesOption(
          key: key,
          isUsable: service.checkAvailability(drug: current, species: key).isUsable,
          note: _noteFor(current, key),
        ),
    ];
  }

  String? _noteFor(Drug drug, String species) {
    final dose = drug.speciesDoses[species];
    if (dose == null) return 'Not in dataset';
    if (dose.isAvailable) return null;
    return dose.detail ?? 'Unusable data';
  }

  List<String> _blockedNotes() {
    final current = drug;
    if (current == null) return const [];
    return [
      for (final entry in current.speciesDoses.entries)
        if (!entry.value.isAvailable)
          '${DatasetNormalizer.speciesLabels[entry.key] ?? entry.key}: '
              '${entry.value.detail ?? 'unusable data'}',
    ];
  }
}

class _SpeciesOption {
  const _SpeciesOption({
    required this.key,
    required this.isUsable,
    required this.note,
  });

  final String key;
  final bool isUsable;
  final String? note;

  String get label => DatasetNormalizer.speciesLabels[key] ?? key;
}

class _SpeciesRow extends StatelessWidget {
  const _SpeciesRow({required this.option, required this.theme});

  final _SpeciesOption option;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: option.isUsable
          ? option.label
          : '${option.label}, unavailable: ${option.note}',
      child: Row(
        children: [
          Expanded(
            child: Text(
              option.label,
              overflow: TextOverflow.ellipsis,
              style: option.isUsable
                  ? null
                  : TextStyle(color: theme.disabledColor),
            ),
          ),
          if (!option.isUsable)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                option.note ?? 'unavailable',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
