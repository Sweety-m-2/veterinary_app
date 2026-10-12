import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/validation/dose_input_validator.dart';

/// Weight field with a kg/lb toggle.
///
/// Validation is live and unit-aware: switching from kg to lb re-validates the
/// same typed value against the kg limits, so the error state can never go stale
/// relative to the unit selector.
class WeightInputField extends StatefulWidget {
  const WeightInputField({
    super.key,
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
    this.errorText,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;

  /// `kg` or `lb`.
  final String unit;
  final ValueChanged<String> onUnitChanged;

  /// Server-side (calculation) error for this field, shown when the local
  /// validator has nothing to say.
  final String? errorText;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  State<WeightInputField> createState() => _WeightInputFieldState();
}

class _WeightInputFieldState extends State<WeightInputField> {
  String? _localError;

  @override
  void didUpdateWidget(covariant WeightInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-validate when the unit changes so a value valid in lb but out of range
    // in kg cannot keep a stale "valid" state.
    if (oldWidget.unit != widget.unit) _validate();
  }

  void _validate() {
    final error = DoseInputValidator.weight(
      widget.controller.text,
      unit: widget.unit,
    );
    if (error != _localError) setState(() => _localError = error);
  }

  @override
  Widget build(BuildContext context) {
    final showError = _localError ?? widget.errorText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: widget.controller,
            enabled: widget.enabled,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onChanged: (_) => _validate(),
            onFieldSubmitted: (_) => widget.onSubmitted?.call(),
            inputFormatters: [
              // Digits, one decimal separator (either style), optional leading
              // sign — everything else is blocked at the keyboard so the field
              // cannot accumulate junk.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-]')),
            ],
            decoration: InputDecoration(
              labelText: 'Weight',
              hintText: widget.unit == 'lb' ? 'e.g. 22 or 22,5' : 'e.g. 10 or 10,5',
              helperText: 'Comma decimals are accepted (4,5 = 4.5)',
              errorText: showError,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.monitor_weight_outlined),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: DropdownButtonFormField<String>(
            initialValue: widget.unit,
            decoration: const InputDecoration(
              labelText: 'Unit',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'kg', child: Text('kg')),
              DropdownMenuItem(value: 'lb', child: Text('lb')),
            ],
            onChanged: widget.enabled
                ? (value) {
                    if (value == null) return;
                    widget.onUnitChanged(value);
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
