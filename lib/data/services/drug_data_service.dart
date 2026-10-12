import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/dataset.dart';
import '../models/drug.dart';

/// Offline-first by contract: the only source is the packaged asset, so the
/// calculator behaves identically with no network. The loader is deliberately
/// *version-agnostic* — it validates that the payload is a well-formed dataset
/// and reports its own `dataset_version`, instead of pinning the app to `v14`.
/// That is what allows a future `v15.json` (or an update file pushed to the
/// device) to be parsed by the same code path.
class DrugDataService {
  const DrugDataService({this.assetPath = defaultAssetPath});

  /// Bundled dataset shipped with the build.
  static const String defaultAssetPath = 'assets/data/v14.json';

  final String assetPath;

  /// Reads and parses the bundled dataset.
  ///
  /// Throws [FormatException] only when the payload cannot be read at all; every
  /// per-drug defect is reported through [Drug.issues].
  Future<DrugDataset> loadBundledDataset() => loadFromAsset(assetPath);

  /// Parses a dataset from any asset path (used for update files in tests).
  Future<DrugDataset> loadFromAsset(String path) async {
    final String raw;
    try {
      raw = await rootBundle.loadString(path);
    } catch (error) {
      throw FormatException('Unable to read the offline dataset at $path: $error');
    }
    return parseDataset(raw);
  }

  /// Parses a raw JSON string. Pure and synchronous, so it is directly testable.
  static DrugDataset parseDataset(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw FormatException('The dataset is not valid JSON: ${error.message}');
    }

    if (decoded is! Map) {
      throw const FormatException('The dataset root must be a JSON object.');
    }

    return DrugDataset.fromJson(<String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    });
  }

  /// Compatibility check for a *newer* dataset arriving as an update.
  ///
  /// The app accepts any schema version it knows how to read, and refuses a
  /// future major schema loudly rather than guessing at unknown fields.
  static const int maxSupportedSchemaVersion = 2;

  static bool isSchemaSupported(DrugDataset dataset) =>
      dataset.schemaVersion <= maxSupportedSchemaVersion;
}
