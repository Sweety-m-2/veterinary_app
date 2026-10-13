import 'weight_validator.dart';

abstract final class DoseInputValidator {
  /// [unit] is the currently selected unit (`kg` / `lb`).
  static String? weight(String? raw, {required String unit}) {
    final text = (raw ?? '').trim();

    if (text.isEmpty) return 'Enter the animal\'s weight.';

    final value = WeightValidator.parseNumber(text);
    if (value == null) {
      return 'Enter a valid weight, for example 4.5 or 4,5.';
    }

    final kg = WeightValidator.toKg(value, unit);
    if (kg == null) return 'Select kg or lb as the weight unit.';

    if (kg < WeightValidator.minWeightKg) {
      return 'Minimum supported weight is '
          '${_fmt(WeightValidator.minWeightKg)} kg.';
    }
    if (kg > WeightValidator.maxWeightKg) {
      return 'Maximum supported weight is '
          '${_fmt(WeightValidator.maxWeightKg)} kg.';
    }

    return null;
  }

  /// Requires a selection (used by the drug and species dropdowns).
  static String? requiredSelection(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? 'Select a $label.' : null;

  /// Enforces the lower bound of a numeric field.
  static String? positiveNumber(String? raw, String label) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 'Enter the $label.';
    final value = WeightValidator.parseNumber(text);
    if (value == null) return 'Enter a valid $label.';
    return null;
  }

  static String _fmt(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}
