import 'package:flutter/material.dart';

import '../../../data/models/drug.dart';
class DrugSelector extends StatelessWidget {
  const DrugSelector({
    super.key,
    required this.drugs,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Drug> drugs;
  final Drug? selected;
  final ValueChanged<Drug?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButtonFormField<Drug>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Drug',
        helperText: 'Select the prescribed product',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.medication_outlined),
      ),
      hint: const Text('Choose a drug'),
      items: [
        for (final drug in drugs)
          DropdownMenuItem<Drug>(
            value: drug,
            child: Semantics(
              label: _semanticLabel(drug),
              child: Row(
                children: [
                  Expanded(
                    child: Text(drug.name, overflow: TextOverflow.ellipsis),
                  ),
                  if (drug.issues.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Tooltip(
                        message: drug.issues
                            .map((issue) => issue.message)
                            .join('\n'),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      // The dropdown menu itself is widened so long names are never clipped.
      menuMaxHeight: 360,
    );
  }

  String _semanticLabel(Drug drug) {
    final buffer = StringBuffer(drug.name);
    if (drug.route.isNotEmpty) buffer.write(', route ${drug.route}');
    buffer.write(', ${drug.speciesSummary}');
    if (drug.hasAbsoluteCap) {
      buffer.write(', capped at ${drug.maxTotalMg} milligrams');
    }
    if (drug.issues.isNotEmpty) buffer.write(', dataset warning');
    return buffer.toString();
  }
}
