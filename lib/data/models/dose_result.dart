import 'drug.dart';

/// human [DoseCalculationException.message] is what the clinician reads.
enum DoseCalculationErrorCode {
  /// Weight was missing, unreadable, negative, or outside the sane range.
  weightInvalid,

  /// Weight is beyond the supported maximum for the calculation.
  weightOutOfRange,

  /// The dataset marks this drug as withdrawn.
  drugWithdrawn,

  /// Concentration is zero — the division-by-zero trap.
  zeroConcentration,

  /// Concentration is missing or in a form the parser cannot resolve.
  unparsableConcentration,

  /// The species key is absent from the drug entirely.
  speciesMissing,

  /// The species key exists but its value is `null`.
  speciesNull,

  /// The species block has no usable min/max.
  speciesIncomplete,

  /// `min > max`: logically corrupt range.
  doseRangeInverted,

  /// `min`/`max` are zero or negative.
  doseRangeNonPositive,

  /// Dose unit is missing or not mass-per-kg.
  unsupportedDoseUnit,

  /// The drug's `max_total_mg` ceiling is below the calculated range floor, so
  /// even the lowest therapeutic dose cannot be given safely.
  absoluteCapBelowMinimum,

  /// A stated total-dose constraint was missing, non-numeric, zero, or negative.
  invalidMaximumTotalDose,

  /// Duplicate raw species keys became ambiguous after normalisation.
  duplicateSpeciesData,

  /// Arithmetic produced a non-finite or non-positive value.
  arithmeticFailure,
}

/// and [field] let it highlight the offending input.
class DoseCalculationException implements Exception {
  const DoseCalculationException({
    required this.code,
    required this.message,
    this.field,
    this.detail,
  });

  final DoseCalculationErrorCode code;

  /// Clinician-facing, complete sentence(s). Rendered verbatim in the UI.
  final String message;

  /// Which input to highlight: `weight`, `drug`, `species`.
  final String? field;

  /// Optional technical detail for logs / diagnostics.
  final String? detail;

  /// Short headline for the error card.
  String get title => switch (code) {
        DoseCalculationErrorCode.weightInvalid ||
        DoseCalculationErrorCode.weightOutOfRange =>
          'Check the weight',
        DoseCalculationErrorCode.drugWithdrawn => 'Drug unavailable',
        DoseCalculationErrorCode.zeroConcentration ||
        DoseCalculationErrorCode.unparsableConcentration =>
          'Concentration unusable',
        DoseCalculationErrorCode.speciesMissing ||
        DoseCalculationErrorCode.speciesNull =>
          'No data for this species',
        DoseCalculationErrorCode.speciesIncomplete ||
        DoseCalculationErrorCode.doseRangeInverted ||
        DoseCalculationErrorCode.doseRangeNonPositive ||
        DoseCalculationErrorCode.unsupportedDoseUnit =>
          'Dose data rejected',
        DoseCalculationErrorCode.absoluteCapBelowMinimum =>
          'Dose cannot be capped safely',
        DoseCalculationErrorCode.invalidMaximumTotalDose =>
          'Maximum-dose data rejected',
        DoseCalculationErrorCode.duplicateSpeciesData => 'Dose data rejected',
        DoseCalculationErrorCode.arithmeticFailure => 'Calculation failed',
      };

  @override
  String toString() => message;
}

class DoseResult {
  const DoseResult({
    required this.drugId,
    required this.drugName,
    required this.route,
    required this.species,
    required this.weightKg,
    required this.weightInput,
    required this.weightInputUnit,
    required this.doseUnit,
    required this.doseMinPerKg,
    required this.doseMaxPerKg,
    required this.concentrationMgPerMl,
    required this.concentrationDisplay,
    required this.doseMinMg,
    required this.doseMaxMg,
    required this.volumeMinMl,
    required this.volumeMaxMl,
    required this.datasetVersion,
    this.uncappedDoseMinMg,
    this.uncappedDoseMaxMg,
    this.absoluteCapMg,
    this.capApplied = false,
  });

  final String drugId;
  final String drugName;
  final String route;

  /// Canonical species key (`dog` / `cat`).
  final String species;

  final double weightKg;
  final String weightInput;
  final String weightInputUnit;

  /// Canonical dose unit as stored (`mg/kg`).
  final String doseUnit;
  final double doseMinPerKg;
  final double doseMaxPerKg;

  final double concentrationMgPerMl;
  final String concentrationDisplay;

  /// Final, possibly capped, dose range in mg.
  final double doseMinMg;
  final double doseMaxMg;

  /// Volume range in mL, derived from the capped mg range.
  final double volumeMinMl;
  final double volumeMaxMl;

  final String datasetVersion;

  /// The uncapped range, retained so the UI can explain what the cap removed.
  final double? uncappedDoseMinMg;
  final double? uncappedDoseMaxMg;

  /// The ceiling from `max_total_mg`, when the drug declares one.
  final double? absoluteCapMg;

  /// `true` when the absolute cap actually shortened the range.
  final bool capApplied;

  /// Dose per kg that the capped range corresponds to (useful for charting).
  double get doseMinPerKgEffective => doseMinMg / weightKg;
  double get doseMaxPerKgEffective => doseMaxMg / weightKg;

  String get speciesLabel =>
      DatasetNormalizer.speciesLabels[species] ?? species;

  /// `"5–10 mg/kg"` in the dataset's own unit.
  String get doseRangeLabel =>
      '${_trim(doseMinPerKg)}–${_trim(doseMaxPerKg)} $doseUnit';

  /// One-line summary used by the result card and by tests.
  String get summary => '${_trim(doseMinMg)}–${_trim(doseMaxMg)} mg '
      '(${_trim(volumeMinMl)}–${_trim(volumeMaxMl)} mL)';

  /// Drops trailing zeros so `2.500` reads as `2.5` and `10.0` as `10`.
  static String _trim(double value, {int decimals = 4}) {
    var text = value.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      text = text.replaceAll(RegExp(r'\.$'), '');
    }
    return text;
  }
}
