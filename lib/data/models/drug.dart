/// Domain models for the offline veterinary drug dataset.
///
/// The bundled dataset (`assets/data/v14.json`) is treated as *untrusted input*:
/// it is versioned, updated over time, and is known to contain structural
/// inconsistencies (mixed-case species keys, trailing whitespace, `null` species
/// blocks, percentage concentrations, string numbers, corrupt ranges).
///
/// Nothing in this file is written against a specific drug id or drug name.
/// Every quirk is resolved by a general rule, so a future `v15`/`v16` payload is
/// parsed with the same code path.
library;

// ---------------------------------------------------------------------------
// Normalisation primitives (shared, pure, unit-testable)
// ---------------------------------------------------------------------------

/// Key/value normalisation rules used by the whole data layer.
///
/// Kept as a small `abstract final class` so the rules are testable in isolation
/// and cannot be re-implemented slightly differently in a second parser.
abstract final class DatasetNormalizer {
  /// Canonical species key for a raw dataset key, or `null` when the key is not
  /// a recognised species.
  ///
  /// A single alias table is the *only* place a species name appears, so adding
  /// a species later is one line, not a patch in the calculator or the UI.
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
  };

  /// Human-readable label for a canonical species key.
  static const Map<String, String> speciesLabels = <String, String>{
    'dog': 'Dog',
    'cat': 'Cat',
  };

  /// Species keys the application understands, in display order.
  static List<String> get knownSpecies => speciesLabels.keys.toList();

  /// `"Dog "` / `"FELINE"` / `"canine."` → `"dog"` / `"cat"` / `"dog"`.
  ///
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

  /// Trims and collapses internal whitespace: `"Meloquin "` → `"Meloquin"`.
  ///
  /// Also strips zero-width and non-breaking spaces, which survive `.trim()`
  /// but break equality, search and de-duplication.
  static String normalizeText(Object? raw) {
    if (raw == null) return '';
    return raw
        .toString()
        .replaceAll(RegExp('[\u00A0\u200B\u200C\u200D\uFEFF]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Uppercase, punctuation-free token used for de-duplication and lookup:
  /// `"Meloquin "` and `"meloquin"` collapse to the same token.
  static String comparisonToken(Object? raw) =>
      normalizeText(raw).toLowerCase();

  /// Lenient number reader: accepts `num`, numeric strings, comma decimal
  /// separators (`"4,5"` → `4.5`), and single-element lists produced by a
  /// sloppy generator (`[5]` → `5`).
  ///
  /// Returns `null` for anything that is not a finite, non-negative number, so
  /// the caller decides whether that is fatal or merely "no data".
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

    final text = normalizeText(value)
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9.\-]'), '');

    if (text.isEmpty) return null;

    final parsed = double.tryParse(text);
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

/// Why a concentration could not be turned into a usable `mg/mL` number.
enum ConcentrationProblem {
  /// The field was absent or empty.
  missing,

  /// Present but not a recognised unit form.
  unparsable,

  /// Parsed, but zero (the division-by-zero trap).
  zero,
}

/// A concentration string resolved to a `mg/mL` value.
///
/// Supported source forms, all handled generically:
/// * `"50 mg/mL"`, `"1.5 mg/ml"`, `"50mg/mL"`, `"50 MG/ML"`
/// * `"10%"` → percentage, `mg/mL = value × 10`
/// * `"1000 mcg/mL"` → `1 mg/mL` (metric conversion, not a special case)
/// * `"1 g/mL"` → `1000 mg/mL`
/// * a bare number is read as `mg/mL` only when the field itself is numeric
sealed class ParsedConcentration {
  const ParsedConcentration({required this.raw});

  /// The original string exactly as it appeared in the dataset.
  final String raw;

  /// `mg/mL`, or `null` when [problem] is set.
  double? get mgPerMl;

  /// `null` when parsing succeeded.
  ConcentrationProblem? get problem;

  bool get isUsable => mgPerMl != null && mgPerMl! > 0;

  /// Display form, e.g. `"10% (100 mg/mL)"`.
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
  static ParsedConcentration parse(Object? raw) {
    final text = DatasetNormalizer.normalizeText(raw);

    if (text.isEmpty) {
      return const ParsedConcentration.invalid(
        raw: '',
        problem: ConcentrationProblem.missing,
      );
    }

    // `10%` → 100 mg/mL. Percent means g/100 mL, i.e. mg/mL = percent × 10.
    final percentMatch =
        RegExp(r'^([0-9]+(?:[.,][0-9]+)?)\s*%$').firstMatch(text);
    if (percentMatch != null) {
      final percent = DatasetNormalizer.tryReadNumber(percentMatch.group(1));
      if (percent == null) {
        return ParsedConcentration.invalid(
          raw: text,
          problem: ConcentrationProblem.unparsable,
        );
      }

      final mgPerMl = percent * 10;
      if (mgPerMl <= 0) {
        return ParsedConcentration.invalid(
          raw: text,
          problem: ConcentrationProblem.zero,
        );
      }

      return ParsedConcentration.valid(
        raw: text,
        mgPerMl: mgPerMl,
        normalizedFrom: '$percent%',
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

      if (amount == null || !_volumeUnits.contains(volumeUnit)) {
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

    // A bare number is accepted as mg/mL — some datasets store the numeric
    // value and the unit in separate fields.
    final bare = DatasetNormalizer.tryReadNumber(text);
    if (bare != null) {
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

  static const Set<String> _volumeUnits = <String>{
    'ml',
    'l',
    'cc',
    'dl',
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

  /// Canonical spelling of a dose unit (`"MCG/KG"` → `"mcg/kg"`).
  static String normalize(Object? raw) {
    // `µ`/`μ` (micro sign and Greek mu) are spelled `u`, which makes the
    // `ug` → `mcg` fold below idempotent: `µg` and `ug` both land on `mcg`.
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
  static double mgPerKgFactor(Object? raw) =>
      _toMgPerKg[normalize(raw)] ?? 1;

  /// Human label for the canonical unit.
  static String label(Object? raw) => switch (normalize(raw)) {
        'mg/kg' => 'mg/kg',
        'mcg/kg' => 'mcg/kg',
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

/// A non-fatal problem noticed while reading one drug entry.
///
/// Used to surface dataset quality in the UI without ever blocking the whole
/// dataset from loading.
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

  /// Parses one drug entry, tolerating every known structural inconsistency.
  ///
  /// Throws only when the entry is not an object at all; anything else is
  /// degraded into [issues] and an unusable species/field, so one corrupt drug
  /// can never invalidate an entire dataset update.
  factory Drug.fromJson(Map<String, Object?> json) {
    final issues = <DrugIssue>[];

    final id = DatasetNormalizer.normalizeText(json['id']);
    final rawName = json['name'];
    final name = DatasetNormalizer.normalizeText(rawName);
    if (name != rawName?.toString()) {
      issues.add(
        const DrugIssue(
          'name_whitespace',
          'The drug name contained padding or irregular whitespace.',
        ),
      );
    }

    // `doses` is the v14 key; the aliases keep the parser forward-compatible.
    final rawDoses = DatasetNormalizer.readFirst(
      json,
      const ['doses', 'species_doses', 'species', 'dose_table'],
    );

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

        // Duplicate keys after normalisation (`dog` + `Dog`): keep the usable
        // one, otherwise the first, and record the collision.
        final existing = speciesDoses[canonical];
        if (existing != null) {
          issues.add(
            DrugIssue(
              'duplicate_species',
              'Species "$canonical" was declared more than once.',
            ),
          );
          if (existing.isAvailable && !parsed.isAvailable) continue;
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

    final concentration = ParsedConcentration.parse(
      DatasetNormalizer.readFirst(
        json,
        const ['concentration', 'concentration_mg_ml', 'strength'],
      ),
    );

    if (!concentration.isUsable) {
      issues.add(
        DrugIssue(
          'concentration_${concentration.problem?.name ?? 'unknown'}',
          'Concentration "${concentration.raw}" could not be used.',
        ),
      );
    }

    final rawCap = DatasetNormalizer.readFirst(
      json,
      const ['max_total_mg', 'maxTotalMg', 'maximum_total_mg'],
    );
    final cap = DatasetNormalizer.tryReadNumber(rawCap);
    if (rawCap != null && (cap == null || cap <= 0)) {
      issues.add(
        const DrugIssue(
          'invalid_max_total_mg',
          'The absolute dose cap was present but not a positive number '
              'and has been ignored.',
        ),
      );
    }

    return Drug(
      id: id.isEmpty ? 'unknown' : id,
      name: name.isEmpty ? 'Unnamed drug' : name,
      route: DatasetNormalizer.normalizeText(json['route']).toUpperCase(),
      concentration: concentration,
      speciesDoses: speciesDoses,
      maxTotalMg: (cap != null && cap > 0) ? cap : null,
      withdrawn: json['withdrawn'] == true,
      withdrawalReason: DatasetNormalizer.normalizeText(
        DatasetNormalizer.readFirst(
          json,
          const ['withdrawal_reason', 'withdrawn_reason'],
        ),
      ).isEmpty
          ? null
          : DatasetNormalizer.normalizeText(
              DatasetNormalizer.readFirst(
                json,
                const ['withdrawal_reason', 'withdrawn_reason'],
              ),
            ),
      issues: List<DrugIssue>.unmodifiable(issues),
    );
  }

  @override
  String toString() => 'Drug($id, $name)';
}
