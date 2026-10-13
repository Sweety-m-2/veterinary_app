import 'drug.dart';

/// A parsed catalogue. Individual unsafe entries are removed from [drugs] and
/// explained by [datasetIssues]; an unreadable or incompatible whole file throws.
class DrugDataset {
  const DrugDataset({
    required this.schemaVersion,
    required this.datasetVersion,
    required this.drugs,
    this.duplicateNames = const <String>[],
    this.datasetIssues = const <DrugIssue>[],
  });

  final int schemaVersion;
  final String datasetVersion;
  final List<Drug> drugs;
  final List<String> duplicateNames;
  final List<DrugIssue> datasetIssues;

  bool get hasQualityIssues =>
      datasetIssues.isNotEmpty || drugs.any((drug) => drug.issues.isNotEmpty);

  /// Every drug-level problem, flattened, for a diagnostics view.
  List<DrugIssue> get allIssues => <DrugIssue>[
        ...datasetIssues,
        for (final drug in drugs)
          for (final issue in drug.issues)
            DrugIssue(issue.code, '${drug.name}: ${issue.message}'),
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

    if (parsed.isEmpty) {
      throw const FormatException('Dataset must contain at least one drug entry.');
    }

    final schemaVersion = DatasetNormalizer.tryReadNumber(json['schema_version']);
    final datasetVersion = DatasetNormalizer.normalizeText(json['dataset_version']);

    if (schemaVersion == null) {
      throw const FormatException('Dataset schema_version is missing or invalid.');
    }
    if (schemaVersion <= 0 || schemaVersion != schemaVersion.roundToDouble()) {
      throw const FormatException('Dataset schema_version must be a positive integer.');
    }
    if (datasetVersion.isEmpty) {
      throw const FormatException('Dataset dataset_version is missing.');
    }

    final validated = _validateCatalogue(parsed);

    if (validated.drugs.isEmpty) {
      throw const FormatException(
        'Dataset contains no safely identifiable, non-ambiguous drug entries.',
      );
    }

    return DrugDataset(
      schemaVersion: schemaVersion.toInt(),
      datasetVersion: datasetVersion,
      drugs: List<Drug>.unmodifiable(validated.drugs),
      duplicateNames: List<String>.unmodifiable(validated.duplicateNames),
      datasetIssues: List<DrugIssue>.unmodifiable(validated.issues),
    );
  }

  static ({
    List<Drug> drugs,
    List<String> duplicateNames,
    List<DrugIssue> issues,
  }) _validateCatalogue(
    List<Drug> drugs,
  ) {
    final ids = <String, List<Drug>>{};
    final names = <String, List<Drug>>{};
    for (final drug in drugs) {
      if (!drug.hasInvalidIdentity) {
        ids.putIfAbsent(drug.id.toLowerCase(), () => []).add(drug);
        names.putIfAbsent(drug.comparisonKey, () => []).add(drug);
      }
    }

    final blocked = <Drug>{
      for (final drug in drugs) if (drug.hasInvalidIdentity) drug,
      for (final group in ids.values)
        if (group.length > 1) ...group,
      // Names that normalise together but have different IDs are ambiguous in
      // a picker. Keep neither rather than silently choosing a concentration.
      for (final group in names.values)
        if (group.map((drug) => drug.id.toLowerCase()).toSet().length > 1)
          ...group,
    };

    final issues = <DrugIssue>[
      for (final drug in drugs)
        if (drug.hasInvalidIdentity)
          DrugIssue(
            'invalid_identity',
            'Entry "${drug.name}" was excluded because its ID or name is missing.',
          ),
      for (final group in ids.entries)
        if (group.value.length > 1)
          DrugIssue(
            'duplicate_id',
            'Entries with duplicate ID "${group.key}" were excluded.',
          ),
      for (final group in names.entries)
        if (group.value.map((drug) => drug.id.toLowerCase()).toSet().length > 1)
          DrugIssue(
            'ambiguous_name',
            'Entries named "${group.value.first.name}" conflict after whitespace '
                'and case normalisation and were excluded.',
          ),
    ];

    final duplicateNames = <String>[
      for (final group in names.values)
        if (group.map((drug) => drug.id.toLowerCase()).toSet().length > 1)
          group.first.name,
    ];

    return (
      drugs: drugs.where((drug) => !blocked.contains(drug)).toList(growable: false),
      duplicateNames: duplicateNames,
      issues: issues,
    );
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
