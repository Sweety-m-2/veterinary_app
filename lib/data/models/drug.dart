library;

// ---------------------------------------------------------------------------
// Normalisation primitives (shared, pure, unit-testable)
// ---------------------------------------------------------------------------
abstract final class DatasetNormalizer {
  static const Map<String, String> _speciesAliases = <String, String>{
    'dog': 'dog',
    'dogs': 'dog',
    'canine': 'dog',
    'canines': 'dog',
    'canis': 'dog',
    'cat': 'cat',
    'cats': 'cat',
    'feline': 'cat',
    'felines': 'cat',
    'felis': 'cat',
    'felidae': 'cat',
  };

  /// Human-readable label for a canonical species key.
  static const Map<String, String> speciesLabels = <String, String>{
    'dog': 'Dog',
    'cat': 'Cat',
  };

  /// Species keys the application understands, in display order.
  static List<String> get knownSpecies => speciesLabels.keys.toList();

  /// `"Dog "` / `"FELINE"` / `"canine."` → `"dog"` / `"cat"` / `"dog"`.
  /// Returns `null` for unknown keys so the caller can report them instead of
  /// silently dropping data.
  static String? normalizeSpeciesKey(Object? rawKey) {
    if (rawKey == null) return null;

    // Collapse whitespace, drop punctuation and case, then de-pluralise by
    // lookup (no stemming, so "felis" is not mangled).
    final cleaned = rawKey
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]+'), ' ')
        .replaceAll(RegExp(r'[^a-z ]'), '')
        .trim();

    if (cleaned.isEmpty) return null;

    return _speciesAliases[cleaned] ??
        _speciesAliases[cleaned.replaceAll(' ', '')];
  }

  static String normalizeText(Object? raw) {
    if (raw == null) return '';
    return raw
        .toString()
        .replaceAll(RegExp('[\u00A0\u200B\u200C\u200D\uFEFF]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String comparisonToken(Object? raw) =>
      normalizeText(raw).toLowerCase();

  static double? tryReadNumber(Object? raw) {
    if (raw == null) return null;

    // Unwrap `[value]` wrappers one level at a time.
    var value = raw;
    while (value is List) {
      if (value.isEmpty) return null;
      value = value.first;
    }

    if (value is num) {
      final asDouble = value.toDouble();
      return asDouble.isFinite && asDouble >= 0 ? asDouble : null;
    }

    if (value is bool) return null;

    final text = normalizeText(value);
    // Dataset numeric fields must be numeric values, not a number hidden in
    // arbitrary prose (for example, "about 5").  Otherwise we would be
    // guessing data rather than validating it.
    if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) return null;

    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

  /// First non-null value found under any of [keys] (alias-tolerant field read).
  static Object? readFirst(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) return json[key];
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Concentration
// ---------------------------------------------------------------------------

enum ConcentrationProblem { missing, ambiguous, unparsable, zero }

/// Supported source forms, all handled generically:
/// * `"50 mg/mL"`, `"1.5 mg/ml"`, `"50mg/mL"`, `"50 MG/ML"`
/// * `"1000 mcg/mL"` → `1 mg/mL` (an explicit metric conversion)
/// * `"1 g/mL"` → `1000 mg/mL`
/// A percentage (`"10%"`) or bare string number is deliberately *not*
/// converted. Those forms omit enough context that treating them as mg/mL
/// would be an unsafe assumption.
sealed class ParsedConcentration {
  const ParsedConcentration({required this.raw});

  /// The original string exactly as it appeared in the dataset.
  final String raw;

  /// `mg/mL`, or `null` when [problem] is set.
  double? get mgPerMl;

  /// `null` when parsing succeeded.
  ConcentrationProblem? get problem;

  bool get isUsable => mgPerMl != null && mgPerMl! > 0;

  /// Display form taken from the dataset, or a clear unusable-data label.
  String get display;

  /// A concentration that yielded a usable `mg/mL` value.
  const factory ParsedConcentration.valid({
    required String raw,
    required double mgPerMl,
    String? normalizedFrom,
  }) = _ValidConcentration;

  /// A concentration that could not be used, with the reason.
  const factory ParsedConcentration.invalid({
    required String raw,
    required ConcentrationProblem problem,
  }) = _InvalidConcentration;

  /// Parses any dataset concentration representation.
  ///
  /// Never throws: an unusable concentration is *data*, reported to the UI as a
  /// blocked drug/species combination rather than crashing dataset loading.
  static ParsedConcentration parse(
    Object? raw, {
    bool numericValueIsExplicitMgPerMl = false,
  }) {
    final text = DatasetNormalizer.normalizeText(raw);

    if (text.isEmpty) {
      return const ParsedConcentration.invalid(
        raw: '',
        problem: ConcentrationProblem.missing,
      );
    }

    if (RegExp(r'^\d+(?:[.,]\d+)?\s*%$').hasMatch(text)) {
      return ParsedConcentration.invalid(
        raw: text,
        problem: ConcentrationProblem.ambiguous,
      );
    }

    // `<value> <mass>/<volume>` with any of the supported mass units.
    final ratioMatch = RegExp(
      r'^([0-9]+(?:[.,][0-9]+)?)\s*([a-zµ]+)\s*/\s*([a-z]+)$',
      caseSensitive: false,
    ).firstMatch(text);

    if (ratioMatch != null) {
      final amount = DatasetNormalizer.tryReadNumber(ratioMatch.group(1));
      final massUnit = ratioMatch.group(2)!.toLowerCase();
      final volumeUnit = ratioMatch.group(3)!.toLowerCase();

      // The requested output is mL.  Other denominator units can be converted
      // mathematically, but are not part of this dataset schema; accepting
      // them would expand the interpretation beyond what the source states.
      if (amount == null || volumeUnit != 'ml') {
        return ParsedConcentration.invalid(
          raw: text,
          problem: ConcentrationProblem.unparsable,
        );
      }

      final factor = _massUnitToMg[massUnit];
      if (factor == null) {
        return ParsedConcentration.invalid(
          raw: text,
          problem: ConcentrationProblem.unparsable,
        );
      }

      final mgPerMl = amount * factor;
      if (mgPerMl <= 0) {
        return ParsedConcentration.invalid(
          raw: text,
          problem: ConcentrationProblem.zero,
        );
      }

      return ParsedConcentration.valid(
        raw: text,
        mgPerMl: mgPerMl,
        normalizedFrom: '$amount ${_displayMassUnit(massUnit)}/mL',
      );
    }

    // A numeric value is accepted only from a field whose name explicitly says
    // it is mg/mL (such as `concentration_mg_ml`). A bare string in the generic
    // `concentration` field has no unit and remains ambiguous.
    if (raw is num && numericValueIsExplicitMgPerMl) {
      final bare = raw.toDouble();
      if (bare <= 0) {
        return ParsedConcentration.invalid(
          raw: text,
          problem: ConcentrationProblem.zero,
        );
      }
      return ParsedConcentration.valid(
        raw: text,
        mgPerMl: bare,
        normalizedFrom: '$bare mg/mL',
      );
    }

    if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) {
      return ParsedConcentration.invalid(
        raw: text,
        problem: ConcentrationProblem.ambiguous,
      );
    }

    return ParsedConcentration.invalid(
      raw: text,
      problem: ConcentrationProblem.unparsable,
    );
  }

  /// Mass unit → multiplier to reach mg.
  static const Map<String, double> _massUnitToMg = <String, double>{
    'kg': 1000000,
    'g': 1000,
    'mg': 1,
    'mcg': 0.001,
    'ug': 0.001,
    '\u00b5g': 0.001,
    '\u03bcg': 0.001,
    'ng': 0.000001,
  };

  static String _displayMassUnit(String unit) => switch (unit) {
    '\u00b5g' || '\u03bcg' || 'ug' => 'mcg',
    _ => unit,
  };
}

final class _ValidConcentration extends ParsedConcentration {
  const _ValidConcentration({
    required super.raw,
    required this.mgPerMl,
    this.normalizedFrom,
  });

  @override
  final double mgPerMl;

  /// Canonical rendering, e.g. `"10% (100 mg/mL)"`; `null` when the dataset
  /// already stored a plain `mg/mL` value.
  final String? normalizedFrom;

  @override
  ConcentrationProblem? get problem => null;

  @override
  String get display => normalizedFrom == null || normalizedFrom == raw
      ? '$mgPerMl mg/mL'
      : '$raw → $mgPerMl mg/mL';
}

final class _InvalidConcentration extends ParsedConcentration {
  const _InvalidConcentration({required super.raw, required this.problem});

  @override
  final ConcentrationProblem problem;

  @override
  double? get mgPerMl => null;

  @override
  String get display => raw.isEmpty ? 'not specified' : raw;
}

// ---------------------------------------------------------------------------
// Dose range + species data
// ---------------------------------------------------------------------------

/// Why a species dose block cannot be used.
enum DoseDataProblem {
  /// The species key was absent from the drug entirely.
  speciesAbsent,

  /// The key was present but its value was `null` / empty.
  speciesNull,

  /// Present, but `min` or `max` was missing or unreadable.
  incompleteRange,

  /// `min > max` — logically corrupt.
  invertedRange,

  /// `min`/`max` parsed as zero or negative — no dose to give.
  nonPositiveRange,

  /// The dose unit is missing or not a mass-per-kg unit.
  unsupportedUnit,

  /// More than one raw key (for example, `dog` and `Dog`) normalised to this
  /// species. Choosing one would conceal potentially contradictory data.
  duplicateSpecies,
}

/// A dose range for one species, in the unit the dataset supplied.
class DoseRange {
  const DoseRange({required this.min, required this.max, required this.unit});

  final double min;
  final double max;

  /// Raw unit text, e.g. `"mg/kg"`.
  final String unit;

  /// Canonical unit token: `mg/kg`, `mcg/kg`, `g/kg`, …
  String get normalizedUnit => DoseUnit.normalize(unit);

  /// Multiplier that converts this range's values into `mg/kg`.
  double get mgPerKgFactor => DoseUnit.mgPerKgFactor(unit);

  bool get isInverted => min > max;

  @override
  String toString() => '$min–$max $unit';
}

/// Mass-per-bodyweight dose units, with their conversion into `mg/kg`.
///
/// The metric conversion guard (1000 mcg = 1 mg) lives here and nowhere else,
/// so the calculator multiplies by weight exactly once.
abstract final class DoseUnit {
  static const Map<String, double> _toMgPerKg = <String, double>{
    'kg/kg': 1000000,
    'g/kg': 1000,
    'mg/kg': 1,
    'mcg/kg': 0.001,
    'ng/kg': 0.000001,
  };

  /// Canonical spelling of a dose unit (`"MG/KG"` → `"mg/kg"`).
  static String normalize(Object? raw) {
    // `µ`/`μ` (micro sign and Greek mu) are spelled `u`, which makes the
    // `ug` → `mg` fold below idempotent: `µg` and `ug` both land on `mcg`.
    final text = DatasetNormalizer.normalizeText(raw)
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('\u00b5', 'u')
        .replaceAll('\u03bc', 'u')
        .replaceAll('ug/kg', 'mcg/kg');
    return text;
  }

  /// `true` when [raw] is a mass-per-kg unit this app can convert.
  static bool isSupported(Object? raw) =>
      _toMgPerKg.containsKey(normalize(raw));

  /// Factor converting values in [raw] to `mg/kg`; `1` for unknown units so the
  /// caller must check [isSupported] first.
  static double mgPerKgFactor(Object? raw) => _toMgPerKg[normalize(raw)] ?? 1;

  /// Human label for the canonical unit.
  static String label(Object? raw) => switch (normalize(raw)) {
    'mg/kg' => 'mg/kg',
    'g/kg' => 'g/kg',
    'ng/kg' => 'ng/kg',
    _ => DatasetNormalizer.normalizeText(raw),
  };
}

/// One species' entry in a drug: either a usable [range], or a [problem] that
/// blocks calculation, with the raw payload kept for diagnostics.
class SpeciesDose {
  const SpeciesDose._({
    required this.species,
    required this.range,
    required this.problem,
    required this.detail,
    required this.rawPresent,
    required this.rawNull,
  });

  /// Usable dose data.
  const SpeciesDose.available({
    required String species,
    required DoseRange range,
  }) : this._(
         species: species,
         range: range,
         problem: null,
         detail: null,
         rawPresent: true,
         rawNull: false,
       );

  /// Unusable dose data, with the machine-readable reason and a human detail.
  const SpeciesDose.unavailable({
    required String species,
    required DoseDataProblem problem,
    String? detail,
    bool rawPresent = true,
    bool rawNull = false,
  }) : this._(
         species: species,
         range: null,
         problem: problem,
         detail: detail,
         rawPresent: rawPresent,
         rawNull: rawNull,
       );

  /// Canonical species key (`dog`, `cat`, …).
  final String species;

  final DoseRange? range;
  final DoseDataProblem? problem;
  final String? detail;
  final bool rawPresent;
  final bool rawNull;

  bool get isAvailable => range != null && problem == null;

  /// Parses one species value. [rawValue] may be a `Map`, a `null`, or junk.
  static SpeciesDose fromJson(String species, Object? rawValue) {
    if (rawValue == null) {
      return SpeciesDose.unavailable(
        species: species,
        problem: DoseDataProblem.speciesNull,
        detail: 'The dataset lists this species as null.',
        rawNull: true,
      );
    }

    if (rawValue is! Map) {
      return SpeciesDose.unavailable(
        species: species,
        problem: DoseDataProblem.speciesNull,
        detail: 'The dataset entry for this species is not an object.',
      );
    }

    final json = <String, Object?>{
      for (final entry in rawValue.entries) entry.key.toString(): entry.value,
    };

    final min = DatasetNormalizer.tryReadNumber(
      DatasetNormalizer.readFirst(json, const ['min', 'dose_min', 'minimum']),
    );
    final max = DatasetNormalizer.tryReadNumber(
      DatasetNormalizer.readFirst(json, const ['max', 'dose_max', 'maximum']),
    );
    final unit = DatasetNormalizer.normalizeText(
      DatasetNormalizer.readFirst(json, const ['unit', 'dose_unit', 'units']),
    );

    if (min == null || max == null) {
      return SpeciesDose.unavailable(
        species: species,
        problem: DoseDataProblem.incompleteRange,
        detail: 'The dose range for this species is incomplete.',
      );
    }

    if (min <= 0 || max <= 0) {
      return SpeciesDose.unavailable(
        species: species,
        problem: DoseDataProblem.nonPositiveRange,
        detail: 'The dose range for this species is not a positive number.',
      );
    }

    if (min > max) {
      return SpeciesDose.unavailable(
        species: species,
        problem: DoseDataProblem.invertedRange,
        detail: 'The dose range is inverted (min $min exceeds max $max).',
      );
    }

    if (!DoseUnit.isSupported(unit)) {
      return SpeciesDose.unavailable(
        species: species,
        problem: DoseDataProblem.unsupportedUnit,
        detail: unit.isEmpty
            ? 'The dose unit is missing for this species.'
            : 'The dose unit "$unit" is not a mass-per-kg unit.',
      );
    }

    return SpeciesDose.available(
      species: species,
      range: DoseRange(min: min, max: max, unit: unit),
    );
  }
}

// ---------------------------------------------------------------------------
// Drug
// ---------------------------------------------------------------------------
class DrugIssue {
  const DrugIssue(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// One drug from the dataset, with all structural quirks already resolved.
class Drug {
  const Drug({
    required this.id,
    required this.name,
    required this.route,
    required this.concentration,
    required this.speciesDoses,
    this.maxTotalMg,
    this.hasInvalidMaxTotalMg = false,
    this.hasInvalidIdentity = false,
    this.withdrawn = false,
    this.withdrawalReason,
    this.issues = const <DrugIssue>[],
  });

  final String id;

  /// Trimmed, whitespace-collapsed name (`"Meloquin "` → `"Meloquin"`).
  final String name;

  /// Trimmed route (`"IV"`, `"PO"`, …).
  final String route;

  /// Concentration already resolved to `mg/mL`.
  final ParsedConcentration concentration;

  /// Species key (canonical, lower-case) → dose data.
  final Map<String, SpeciesDose> speciesDoses;

  /// Optional absolute ceiling on the total dose, in mg.
  final double? maxTotalMg;

  /// A cap field was supplied but was not a positive numeric mg value.
  /// It is a hard stop: silently ignoring a stated safety limit is unsafe.
  final bool hasInvalidMaxTotalMg;

  /// A required identity field (ID or name) was absent or empty.
  final bool hasInvalidIdentity;

  final bool withdrawn;
  final String? withdrawalReason;

  /// Dataset-quality notes for this entry (never fatal).
  final List<DrugIssue> issues;

  /// Case/whitespace-insensitive identity used to de-duplicate a catalogue.
  String get comparisonKey => DatasetNormalizer.comparisonToken(name);

  bool get hasAbsoluteCap => maxTotalMg != null && maxTotalMg! > 0;

  /// Species keys present in the raw entry, whether usable or not.
  Iterable<String> get declaredSpecies => speciesDoses.keys;

  /// Species keys that can actually be calculated.
  Iterable<String> get usableSpecies => speciesDoses.entries
      .where((entry) => entry.value.isAvailable)
      .map((entry) => entry.key);

  SpeciesDose? doseFor(Object? species) {
    final key = DatasetNormalizer.normalizeSpeciesKey(species);
    if (key == null) return null;
    return speciesDoses[key];
  }

  /// `"Dog, Cat"` — declared species, for list subtitles.
  String get speciesSummary {
    if (speciesDoses.isEmpty) return 'No species data';
    return speciesDoses.keys
        .map((key) => DatasetNormalizer.speciesLabels[key] ?? key)
        .join(', ');
  }
  factory Drug.fromJson(Map<String, Object?> json) {
    final issues = <DrugIssue>[];

    final id = DatasetNormalizer.normalizeText(json['id']);
    final rawName = json['name'];
    final name = DatasetNormalizer.normalizeText(rawName);
    if (id.isEmpty) {
      issues.add(const DrugIssue('missing_id', 'The drug ID is missing.'));
    }
    if (name.isEmpty) {
      issues.add(const DrugIssue('missing_name', 'The drug name is missing.'));
    }
    if (name != rawName?.toString()) {
      issues.add(
        const DrugIssue(
          'name_whitespace',
          'The drug name contained padding or irregular whitespace.',
        ),
      );
    }

    // `doses` is the v14 key; the aliases keep the parser forward-compatible.
    final rawDoses = DatasetNormalizer.readFirst(json, const [
      'doses',
      'species_doses',
      'species',
      'dose_table',
    ]);

    final speciesDoses = <String, SpeciesDose>{};

    if (rawDoses is Map) {
      for (final entry in rawDoses.entries) {
        final canonical = DatasetNormalizer.normalizeSpeciesKey(entry.key);
        if (canonical == null) {
          issues.add(
            DrugIssue(
              'unknown_species',
              'Unrecognised species key "${entry.key}" was skipped.',
            ),
          );
          continue;
        }

        final parsed = SpeciesDose.fromJson(canonical, entry.value);

        // Never choose a winner when two raw keys normalise to the same species
        // (`dog` + `Dog`).  They might contradict each other, so the affected
        // species is explicitly blocked while other species stay usable.
        final existing = speciesDoses[canonical];
        if (existing != null) {
          issues.add(
            DrugIssue(
              'duplicate_species',
              'Species "$canonical" was declared more than once.',
            ),
          );
          speciesDoses[canonical] = SpeciesDose.unavailable(
            species: canonical,
            problem: DoseDataProblem.duplicateSpecies,
            detail: 'More than one dataset key normalises to $canonical.',
          );
          continue;
        }

        speciesDoses[canonical] = parsed;
      }
    } else {
      issues.add(
        const DrugIssue('missing_doses', 'The drug has no species dose table.'),
      );
    }

    if (speciesDoses.isEmpty) {
      issues.add(
        const DrugIssue('empty_doses', 'The drug has no usable species keys.'),
      );
    }

    final concentration = _parseConcentration(json);

    if (!concentration.isUsable) {
      issues.add(
        DrugIssue(
          'concentration_${concentration.problem?.name ?? 'unknown'}',
          concentration.problem == ConcentrationProblem.ambiguous
              ? 'Concentration "${concentration.raw}" is ambiguous; an '
                  'explicit mass-per-mL value is required.'
              : 'Concentration "${concentration.raw}" could not be used.',
        ),
      );
    }

    final rawCap = DatasetNormalizer.readFirst(json, const [
      'max_total_mg',
      'maxTotalMg',
      'maximum_total_mg',
    ]);
    final cap = DatasetNormalizer.tryReadNumber(rawCap);
    if (rawCap != null && (cap == null || cap <= 0)) {
      issues.add(
        const DrugIssue(
          'invalid_max_total_mg',
          'The absolute dose cap was present but not a positive number '
              'and blocks calculation until corrected.',
        ),
      );
    }

    return Drug(
      id: id.isEmpty ? 'unknown' : id,
      name: name.isEmpty ? 'Unnamed drug' : name,
      route: DatasetNormalizer.normalizeText(json['route']).toUpperCase(),
      concentration: concentration,
      speciesDoses: Map<String, SpeciesDose>.unmodifiable(speciesDoses),
      maxTotalMg: (cap != null && cap > 0) ? cap : null,
      hasInvalidMaxTotalMg: rawCap != null && (cap == null || cap <= 0),
      hasInvalidIdentity: id.isEmpty || name.isEmpty,
      withdrawn: json['withdrawn'] == true,
      withdrawalReason:
          DatasetNormalizer.normalizeText(
            DatasetNormalizer.readFirst(json, const [
              'withdrawal_reason',
              'withdrawn_reason',
            ]),
          ).isEmpty
          ? null
          : DatasetNormalizer.normalizeText(
              DatasetNormalizer.readFirst(json, const [
                'withdrawal_reason',
                'withdrawn_reason',
              ]),
            ),
      issues: List<DrugIssue>.unmodifiable(issues),
    );
  }

  /// Reads known concentration fields without assuming that they all agree.
  /// Multiple usable but different values are an ambiguity, not a tie-breaker.
  static ParsedConcentration _parseConcentration(Map<String, Object?> json) {
    const keys = <String>['concentration', 'concentration_mg_ml', 'strength'];
    final values = <({String key, Object? value})>[
      for (final key in keys)
        if (json.containsKey(key) && json[key] != null)
          (key: key, value: json[key]),
    ];

    if (values.isEmpty) return ParsedConcentration.parse(null);

    final parsed = [
      for (final item in values)
        ParsedConcentration.parse(
          item.value,
          numericValueIsExplicitMgPerMl: item.key == 'concentration_mg_ml',
        ),
    ];

    if (parsed.length == 1) return parsed.single;

    final usable = parsed.where((value) => value.isUsable).toList();
    final allAgree = usable.length == parsed.length &&
        usable.map((value) => value.mgPerMl).toSet().length == 1;
    if (allAgree) return usable.first;

    return ParsedConcentration.invalid(
      raw: values
          .map((item) => '${item.key}=${DatasetNormalizer.normalizeText(item.value)}')
          .join(', '),
      problem: ConcentrationProblem.ambiguous,
    );
  }

  @override
  String toString() => 'Drug($id, $name)';
}
