import 'package:flutter/material.dart';

import '../../../data/models/dose_result.dart';

/// Presents a completed calculation.
///
/// The volume range is the headline (it is what is drawn into a syringe), the
/// mg range is the working, and the provenance block records the exact dataset
/// version, concentration and rate used. When the absolute cap shortened the
/// range, the original values are shown alongside so the clinician can see that
/// the ceiling — not the weight — set the upper bound.
class DoseResultCard extends StatelessWidget {
  const DoseResultCard({super.key, required this.result});

  final DoseResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: 'Calculated dose: '
          '${result.summary}. Route ${result.route}. '
          '${result.capApplied ? 'Absolute dose cap applied. ' : ''}'
          'Reference only, verify before administration.',
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calculate_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Calculated reference range',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _ValueRow(
                label: 'Volume to draw up',
                value: '${_fmt(result.volumeMinMl)} – '
                    '${_fmt(result.volumeMaxMl)} mL',
                emphasized: true,
              ),
              const SizedBox(height: 8),
              _ValueRow(
                label: 'Total dose',
                value: '${_fmt(result.doseMinMg)} – '
                    '${_fmt(result.doseMaxMg)} mg',
                emphasized: true,
              ),

              if (result.capApplied) ...[
                const SizedBox(height: 12),
                _CapNotice(result: result),
              ],

              const Divider(height: 32),

              _ValueRow(label: 'Drug', value: result.drugName),
              _ValueRow(label: 'Route', value: result.route),
              _ValueRow(label: 'Species', value: result.speciesLabel),
              _ValueRow(
                label: 'Weight',
                value: '${_fmt(result.weightKg, 3)} kg'
                    '${result.weightInputUnit == 'lb' && result.weightInput.isNotEmpty ? ' (from ${result.weightInput} lb)' : ''}',
              ),
              _ValueRow(
                label: 'Dataset rate',
                value: result.doseRangeLabel,
              ),
              _ValueRow(
                label: 'Concentration',
                value: result.concentrationDisplay,
              ),
              _ValueRow(label: 'Dataset', value: result.datasetVersion),

              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.errorContainer,
                ),
                child: Text(
                  'Reference calculation only. Confirm the dose against your '
                  'practice protocol and the product label before '
                  'administration.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double value, [int decimals = 4]) {
    var text = value.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return text.isEmpty ? '0' : text;
  }
}

class _CapNotice extends StatelessWidget {
  const _CapNotice({required this.result});

  final DoseResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.tertiaryContainer,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vertical_align_top,
              size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Capped at the dataset maximum of '
              '${DoseResultCard._fmt(result.absoluteCapMg ?? 0)} mg. '
              'Uncapped, this weight would give '
              '${DoseResultCard._fmt(result.uncappedDoseMinMg ?? 0)} – '
              '${DoseResultCard._fmt(result.uncappedDoseMaxMg ?? 0)} mg.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasized
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: style),
          ),
        ],
      ),
    );
  }
}
