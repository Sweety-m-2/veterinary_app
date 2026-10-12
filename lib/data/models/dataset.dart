import 'drug.dart';

/// The parsed offline dataset: metadata plus the drug catalogue.
///
/// Parsing is deliberately *forgiving*: a structurally valid payload always
/// produces a dataset, and per-drug problems are attached to the [Drug] as
/// [DrugIssue]s. Only a payload that cannot be read at all (wrong root type,
/// missing version metadata) throws, because at that point there is nothing to
/// show the clinician.
class DrugDataset {
  const DrugDataset({
    required this.schemaVersion,
    required this.datasetVersion,
    required this.drugs,
    this.duplicateNames = const <String>[],
  });

  final int schemaVersion;
  final String datasetVersion;
  final List<Drug> drugs;

  /// Display names that appeared more than once (after normalisation).
  ///
  /// The catalogue keeps the richest entry for each name so the drug picker
  /// cannot show two indistinguishable rows; the collision is reported here and
  /// in the UI rather than silently merged.
  final List<String> duplicateNames;

  bool get hasQualityIssues =>
      duplicateNames.isNotEmpty || drugs.any((drug) => drug.issues.isNotEmpty);

  /// Every drug-level problem, flattened, for a diagnostics view.
  List<DrugIssue> get allIssues => <DrugIssue>[
        for (final drug in drugs)
          for (final issue in drug.issues) DrugIssue(issue.code, '${drug.name}: ${issue.message}'),
      ];

  factory DrugDataset.fromJson(Map<String, Object?> json) {
    final rawDrugs = json['drugs'];

    if (rawDrugs is! List) {
      throw const FormatException('Dataset must contain a "drugs" list.');
    }

    final parsed = <Drug>[];
    for (final item in rawDrugs) {
      if (item is! Map) {
        throw const FormatException('Every drug entry must be a JSON object.');
      }
      parsed.add(
        Drug.fromJson(<String, Object?>{
          for (final entry in item.entries) entry.key.toString(): entry.value,
        }),
      );
    }

    final schemaVersion = DatasetNormalizer.tryReadNumber(json['schema_version']);
    final datasetVersion = DatasetNormalizer.normalizeText(json['dataset_version']);

    if (schemaVersion == null) {
      throw const FormatException('Dataset schema_version is missing or invalid.');
    }
    if (datasetVersion.isEmpty) {
      throw const FormatException('Dataset dataset_version is missing.');
    }

    final deduplicated = _deduplicateByName(parsed);

    return DrugDataset(
      schemaVersion: schemaVersion.toInt(),
      datasetVersion: datasetVersion,
      drugs: List<Drug>.unmodifiable(deduplicated.drugs),
      duplicateNames: List<String>.unmodifiable(deduplicated.collisions),
    );
  }

  /// Keeps one entry per normalised name — the one with the most usable species
  /// data, then the one with the fewest reported issues.
  ///
  /// This is what stops `"Meloquin"` and `"Meloquin "` from becoming two rows
  /// in the picker, without special-casing either entry.
  static ({List<Drug> drugs, List<String> collisions}) _deduplicateByName(
    List<Drug> drugs,
  ) {
    final byKey = <String, Drug>{};
    final collisions = <String>[];

    for (final drug in drugs) {
      final key = drug.comparisonKey;
      final existing = byKey[key];

      if (existing == null) {
        byKey[key] = drug;
        continue;
      }

      if (!collisions.contains(drug.name)) collisions.add(drug.name);
      if (_richness(drug) > _richness(existing)) byKey[key] = drug;
    }

    return (drugs: byKey.values.toList(growable: false), collisions: collisions);
  }

  /// Higher is better: usable species first, then fewer issues, then an
  /// explicit absolute cap (more safety information, not less).
  static int _richness(Drug drug) {
    final usable = drug.usableSpecies.length;
    final issuePenalty = drug.issues.length;
    final capBonus = drug.hasAbsoluteCap ? 1 : 0;
    return usable * 100 - issuePenalty * 10 + capBonus;
  }

  /// Name search that survives the dataset's whitespace and case quirks.
  List<Drug> search(String query) {
    final needle = DatasetNormalizer.comparisonToken(query);
    if (needle.isEmpty) return drugs;
    return drugs
        .where((drug) =>
            drug.comparisonKey.contains(needle) ||
            DatasetNormalizer.comparisonToken(drug.route).contains(needle))
        .toList(growable: false);
  }
}
