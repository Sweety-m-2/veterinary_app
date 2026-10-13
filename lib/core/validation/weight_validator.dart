import '../../data/services/dose_calculation_service.dart'
    show DoseCalculationService;
abstract final class WeightValidator {
  /// Pounds in one kilogram.
  static const double lbPerKg = 2.2046226218487757;

  static double get minWeightKg => DoseCalculationService.minWeightKg;
  static double get maxWeightKg => DoseCalculationService.maxWeightKg;

  /// Parses [input] in [unit] (`kg`, `lb`, `lbs`, `pound`…) and returns kg.
  ///
  /// Throws [WeightFormatException] with a clinician-facing message.
  static double parseToKg({required String input, required String unit}) {
    final kg = tryParseToKg(input: input, unit: unit);
    if (kg == null) {
      throw WeightFormatException(
        _failureReason(input: input, unit: unit) ??
            'Enter the weight as a positive number.',
      );
    }
    return kg;
  }

  /// Same as [parseToKg] but returns `null` instead of throwing.
  static double? tryParseToKg({required String input, required String unit}) {
    final value = parseNumber(input);
    if (value == null) return null;

    final kg = toKg(value, unit);
    if (kg == null) return null;

    if (kg < minWeightKg || kg > maxWeightKg) return null;
    return kg;
  }

  /// Converts an already-parsed [value] in [unit] to kilograms.
  ///
  /// Returns `null` for an unknown unit.
  static double? toKg(double value, String unit) {
    final normalized = unit.trim().toLowerCase().replaceAll('.', '');
    final kg = switch (normalized) {
      'kg' || 'kgs' || 'kilogram' || 'kilograms' || 'kilo' || 'kilos' => value,
      'lb' || 'lbs' || 'pound' || 'pounds' => value / lbPerKg,
      'g' || 'gram' || 'grams' => value / 1000,
      _ => null,
    };

    if (kg == null || !kg.isFinite || kg <= 0) return null;
    return kg;
  }
  static double? parseNumber(String input) {
    var text = input
        .replaceAll(RegExp('[\u00A0\u200B\u200C\u200D\uFEFF]'), '')
        .trim()
        // A trailing unit typed into the field ("4.5 kg") is tolerated.
        .replaceAll(RegExp(r'[a-zA-Zµ%]+$'), '')
        .trim();

    if (text.isEmpty) return null;

    // A leading sign is only acceptable when it is not a minus sign; "+4.5" is
    // fine, "-4.5" is an impossible weight.
    if (text.startsWith('+')) text = text.substring(1);
    if (text.startsWith('-') || text.contains('-')) return null;

    final lastComma = text.lastIndexOf(',');
    final lastDot = text.lastIndexOf('.');

    if (lastComma >= 0 && lastDot >= 0) {
      // Both separators present: the right-most one is the decimal separator.
      if (lastComma > lastDot) {
        text = text.replaceAll('.', '').replaceAll(',', '.');
      } else {
        text = text.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final groups = text.split(',');
      // "4,5" is a decimal comma; "1,234" with exactly three trailing digits is
      // a thousands separator; anything else is ambiguous and rejected.
      // `0,001` is unambiguously a decimal comma, even though it has three
      // fractional digits. For other three-digit groups such as `1,234`, the
      // existing convention treats the comma as a thousands separator.
      if (groups.length == 2 &&
          (groups.last.length != 3 || groups.first == '0')) {
        text = '${groups.first}.${groups.last}';
      } else if (groups.length == 2 && groups.last.length == 3) {
        text = groups.join();
      } else {
        return null;
      }
    }

    if (!RegExp(r'^\d*\.?\d+$').hasMatch(text)) return null;

    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  /// Best-effort explanation for a rejected value, used for inline errors.
  static String? _failureReason({required String input, required String unit}) {
    if (input.trim().isEmpty) return 'Enter the animal\'s weight.';

    if (toKg(1, unit) == null) {
      return 'Select kg or lb as the weight unit.';
    }

    final value = parseNumber(input);
    if (value == null) {
      return 'Enter a valid weight, for example 4.5 or 4,5.';
    }

    final kg = toKg(value, unit)!;
    if (kg < minWeightKg) {
      return 'That weight is too small to dose safely '
          '(minimum ${_fmt(minWeightKg)} kg).';
    }
    if (kg > maxWeightKg) {
      return 'That weight is above the supported maximum of '
          '${_fmt(maxWeightKg)} kg.';
    }

    return null;
  }

  static String _fmt(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}

/// Thrown when a weight cannot be interpreted; [message] is safe to show.
class WeightFormatException implements Exception {
  const WeightFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
