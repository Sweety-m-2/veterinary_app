import 'dart:math' as math;

import '../models/dose_result.dart';
import '../models/drug.dart';

/// Result of inspecting a drug/species pair before any maths happens.
///
/// Lets the UI grey out impossible combinations instead of only failing on tap.
class DoseAvailability {
  const DoseAvailability({required this.isUsable, this.blocker});

  final bool isUsable;

  /// Why the combination is unusable, when it is.
  final DoseCalculationException? blocker;

  static const DoseAvailability usable = DoseAvailability(isUsable: true);
}

/// Pure business logic for the offline dose calculator.
///
/// This class has no Flutter, I/O or platform dependency: it takes a [Drug]
/// (already normalised by the data layer), a species key and a weight in kg, and
/// returns a [DoseResult] or throws a typed [DoseCalculationException].
///
/// ## Safety layers, in evaluation order
///
/// 1. **Weight sanity** — finite, positive, within a physiological range.
/// 2. **Withdrawal gate** — a withdrawn drug never produces a number.
/// 3. **Concentration gate** — a concentration that resolves to `0 mg/mL` (or
///    cannot be resolved at all) is a hard stop, because every volume below it
///    would be a division by zero.
/// 4. **Species gate** — a species that is absent, or present but `null`, is a
///    hard stop. The two cases are reported distinctly.
/// 5. **Range integrity** — `min`/`max` must exist, be positive, and satisfy
///    `min <= max`. An inverted range (`min: 8, max: 4`) is corrupt data and is
///    refused rather than silently swapped.
/// 6. **Unit gate** — the dose unit must be mass-per-kg; the conversion table in
///    [DoseUnit] applies the metric guard (1000 mcg = 1 mg) exactly once.
/// 7. **Absolute cap** — `max_total_mg` clamps the mg range (and lifts the floor
///    with it when necessary) so the displayed range is never inverted and never
///    exceeds the ceiling.
/// 8. **Arithmetic validation** — every intermediate is checked for finiteness
///    and positivity before it reaches the UI.
class DoseCalculationService {
  const DoseCalculationService();

  /// Physiological guard rail. A dose calculator for a clinic is not a general
  /// purpose arithmetic tool; refusing absurd input is part of the safety case.
  static const double minWeightKg = 0.05;
  static const double maxWeightKg = 300;

  /// Pre-flight check used to disable unusable species options in the UI.
  ///
  /// Performs the same gates as [calculate] minus the weight-dependent ones, and
  /// never throws.
  DoseAvailability checkAvailability({
    required Drug drug,
    required String species,
  }) {
    try {
      _assertDrugUsable(drug);
      final dose = _resolveSpeciesDose(drug, species);
      _assertRangeUsable(dose);
      return DoseAvailability.usable;
    } on DoseCalculationException catch (error) {
      return DoseAvailability(isUsable: false, blocker: error);
    }
  }

  /// Computes the therapeutic mg range and the matching mL range.
  ///
  /// [weightKg] must already be in kilograms; unit conversion from lb and
  /// locale-aware parsing belong to the input layer
  /// (`WeightValidator.parseToKg`).
  DoseResult calculate({
    required Drug drug,
    required String species,
    required double weightKg,
    String datasetVersion = 'unknown',
    String weightInput = '',
    String weightInputUnit = 'kg',
  }) {
    _assertWeightUsable(weightKg);
    _assertDrugUsable(drug);

    final dose = _resolveSpeciesDose(drug, species);
    _assertRangeUsable(dose);

    final range = dose.range!;
    final concentration = drug.concentration.mgPerMl!;
    final factor = range.mgPerKgFactor;

    // Layer 6: normalise the dataset unit into mg/kg before multiplying by the
    // animal's weight, so the metric guard is applied to the *rate*, not the
    // final mass.
    final minPerKgMg = range.min * factor;
    final maxPerKgMg = range.max * factor;

    var uncappedMinMg = weightKg * minPerKgMg;
    var uncappedMaxMg = weightKg * maxPerKgMg;

    _assertFinitePositive(uncappedMinMg, 'minimum dose');
    _assertFinitePositive(uncappedMaxMg, 'maximum dose');

    // The cap is applied to the ordered pair: clamping only the ceiling would
    // leave the floor above it, producing an inverted display range.
    var cappedMinMg = uncappedMinMg;
    var cappedMaxMg = uncappedMaxMg;
    var capApplied = false;

    final cap = drug.maxTotalMg;
    if (cap != null && cap > 0 && uncappedMaxMg > cap) {
      // Layer 7a: the ceiling is below the therapeutic floor. Capping here would
      // advise a sub-therapeutic dose, so the combination is refused instead.
      if (cap < uncappedMinMg) {
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.absoluteCapBelowMinimum,
          field: 'drug',
          message:
              'This animal needs at least ${_fmt(uncappedMinMg)} mg, but the '
              'dataset caps ${drug.name} at ${_fmt(cap)} mg in total. The '
              'absolute limit is below the lowest dose in range, so no safe '
              'volume can be calculated. Choose a different drug.',
          detail: 'min=${uncappedMinMg}mg max=${uncappedMaxMg}mg cap=${cap}mg',
        );
      }

      cappedMaxMg = cap;
      if (cappedMinMg > cappedMaxMg) cappedMinMg = cappedMaxMg;
      capApplied = true;
    }

    _assertOrderedRange(cappedMinMg, cappedMaxMg, 'mg dose');

    // Layer 8: volume = mg ÷ mg/mL. The concentration gate above guarantees a
    // non-zero divisor.
    final volumeMinMl = cappedMinMg / concentration;
    final volumeMaxMl = cappedMaxMg / concentration;

    _assertFinitePositive(volumeMinMl, 'minimum volume');
    _assertFinitePositive(volumeMaxMl, 'maximum volume');
    _assertOrderedRange(volumeMinMl, volumeMaxMl, 'volume');

    return DoseResult(
      drugId: drug.id,
      drugName: drug.name,
      route: drug.route,
      species: dose.species,
      weightKg: weightKg,
      weightInput: weightInput,
      weightInputUnit: weightInputUnit,
      doseUnit: range.normalizedUnit,
      doseMinPerKg: range.min,
      doseMaxPerKg: range.max,
      concentrationMgPerMl: concentration,
      concentrationDisplay: drug.concentration.display,
      doseMinMg: cappedMinMg,
      doseMaxMg: cappedMaxMg,
      volumeMinMl: volumeMinMl,
      volumeMaxMl: volumeMaxMl,
      datasetVersion: datasetVersion,
      uncappedDoseMinMg: capApplied ? uncappedMinMg : null,
      uncappedDoseMaxMg: capApplied ? uncappedMaxMg : null,
      absoluteCapMg: drug.hasAbsoluteCap ? drug.maxTotalMg : null,
      capApplied: capApplied,
    );
  }

  // -------------------------------------------------------------------------
  // Gates
  // -------------------------------------------------------------------------

  void _assertWeightUsable(double weightKg) {
    if (!weightKg.isFinite || weightKg <= 0) {
      throw const DoseCalculationException(
        code: DoseCalculationErrorCode.weightInvalid,
        field: 'weight',
        message: 'Enter the animal\'s weight as a positive number.',
      );
    }

    if (weightKg < minWeightKg || weightKg > maxWeightKg) {
      throw DoseCalculationException(
        code: DoseCalculationErrorCode.weightOutOfRange,
        field: 'weight',
        message: 'Weight must be between ${_fmt(minWeightKg)} kg and '
            '${_fmt(maxWeightKg)} kg.',
        detail: 'received ${weightKg}kg',
      );
    }
  }

  void _assertDrugUsable(Drug drug) {
    if (drug.withdrawn) {
      throw DoseCalculationException(
        code: DoseCalculationErrorCode.drugWithdrawn,
        field: 'drug',
        message: drug.withdrawalReason?.isNotEmpty == true
            ? drug.withdrawalReason!
            : '${drug.name} has been withdrawn from the dataset.',
      );
    }

    // Layer 3: division-by-zero trap. A zero (or unreadable) concentration is
    // reported as unusable data, never as a divide-by-zero crash.
    final concentration = drug.concentration;
    if (!concentration.isUsable) {
      final isZero = concentration.problem == ConcentrationProblem.zero;
      throw DoseCalculationException(
        code: isZero
            ? DoseCalculationErrorCode.zeroConcentration
            : DoseCalculationErrorCode.unparsableConcentration,
        field: 'drug',
        message: isZero
            ? '${drug.name} has a concentration of 0 mg/mL in this dataset, so '
                'no volume can be calculated. The entry is unusable.'
            : '${drug.name} has a concentration this app cannot resolve '
                '("${concentration.display}"). A verified mg/mL or percentage '
                'value is required.',
        detail: 'problem=${concentration.problem?.name}',
      );
    }
  }

  SpeciesDose _resolveSpeciesDose(Drug drug, String species) {
    final key = DatasetNormalizer.normalizeSpeciesKey(species) ??
        DatasetNormalizer.comparisonToken(species);

    final dose = drug.speciesDoses[key];

    // Layer 4: absent key and explicit null are different data defects and are
    // reported differently, but both are hard stops.
    if (dose == null) {
      throw DoseCalculationException(
        code: DoseCalculationErrorCode.speciesMissing,
        field: 'species',
        message: '${drug.name} has no dose data for '
            '${_speciesLabel(key)} in this dataset.',
        detail: 'species key "$key" absent; declared ${drug.declaredSpecies}',
      );
    }

    return dose;
  }

  void _assertRangeUsable(SpeciesDose dose) {
    final label = _speciesLabel(dose.species);

    if (dose.isAvailable) return;

    switch (dose.problem!) {
      case DoseDataProblem.speciesNull:
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.speciesNull,
          field: 'species',
          message: 'The dataset lists this drug for $label as null, so no dose '
              'can be calculated for that species.',
          detail: dose.detail,
        );
      case DoseDataProblem.speciesAbsent:
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.speciesMissing,
          field: 'species',
          message: 'No dose data is available for $label.',
          detail: dose.detail,
        );
      case DoseDataProblem.incompleteRange:
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.speciesIncomplete,
          field: 'species',
          message: 'The dose range for $label is incomplete in this dataset.',
          detail: dose.detail,
        );
      case DoseDataProblem.nonPositiveRange:
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.doseRangeNonPositive,
          field: 'species',
          message: 'The dose range for $label is not a positive number, so it '
              'cannot be used.',
          detail: dose.detail,
        );
      case DoseDataProblem.invertedRange:
        // Layer 5: min > max is corrupt. Swapping the values would invent a
        // dose the dataset never stated, so the range is refused instead.
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.doseRangeInverted,
          field: 'species',
          message: 'The dose range for $label is corrupt: the minimum is '
              'greater than the maximum. The entry is unusable until the '
              'dataset is corrected.',
          detail: dose.detail,
        );
      case DoseDataProblem.unsupportedUnit:
        throw DoseCalculationException(
          code: DoseCalculationErrorCode.unsupportedDoseUnit,
          field: 'species',
          message: 'The dose unit for $label is missing or is not a '
              'mass-per-kilogram unit, so it cannot be converted safely.',
          detail: dose.detail,
        );
    }
  }

  void _assertOrderedRange(double min, double max, String label) {
    if (min > max) {
      throw DoseCalculationException(
        code: DoseCalculationErrorCode.arithmeticFailure,
        field: 'weight',
        message: 'The calculated $label range is not ordered; the calculation '
            'was refused.',
        detail: 'min=$min max=$max',
      );
    }
  }

  void _assertFinitePositive(double value, String label) {
    if (!value.isFinite || value <= 0) {
      throw DoseCalculationException(
        code: DoseCalculationErrorCode.arithmeticFailure,
        field: 'weight',
        message: 'The calculated $label is not a usable number; the '
            'calculation was refused.',
        detail: '$label=$value',
      );
    }
  }

  static String _speciesLabel(String key) =>
      DatasetNormalizer.speciesLabels[key] ?? key;

  /// Compact number formatting for messages: `2.5`, `0.02`, `400`.
  static String _fmt(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e9) {
      return value.toStringAsFixed(0);
    }

    final text = value
        .toStringAsFixed(math.min(4, math.max(0, _decimalsNeeded(value))))
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');

    return text.isEmpty ? '0' : text;
  }

  /// Digits needed to show [value] without losing its significant part.
  static int _decimalsNeeded(double value) {
    if (value == 0) return 0;
    final magnitude = value.abs();
    if (magnitude >= 1) return 4;
    if (magnitude >= 0.1) return 4;
    return 6;
  }
}
