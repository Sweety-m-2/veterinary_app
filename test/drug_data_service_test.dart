import 'dart:convert';

import 'package:app/data/models/dataset.dart';
import 'package:app/data/models/drug.dart';
import 'package:app/data/services/drug_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for a future dataset file: same schema, different content, and
/// deliberately full of the same structural traps as v14.
Map<String, Object?> futureDataset({Object? drugs}) => <String, Object?>{
      'schema_version': 2,
      'dataset_version': 'v99',
      'drugs': drugs ??
          [
            {
              'id': 'n001',
              'name': '  Neodrine  ',
              'concentration': '2.5 %',
              'route': 'im',
              'doses': {
                'CANINE': {'min': '3', 'max': '6', 'unit': 'MG/KG'},
                'Felidae': {'min': 1, 'max': 2, 'unit': 'µg/kg'},
              },
            },
          ],
    };

void main() {
  group('Drug — name and key normalisation', () {
    test('trims padding and collapses irregular whitespace', () {
      final drug = Drug.fromJson(<String, Object?>{
        'id': 'd005',
        'name': 'Meloquin ',
        'concentration': '5 mg/mL',
        'route': ' SC ',
        'doses': {
          'dog': {'min': 0.1, 'max': 0.2, 'unit': 'mg/kg'},
        },
      });

      expect(drug.name, 'Meloquin');
      expect(drug.route, 'SC');
      expect(
        drug.issues.map((issue) => issue.code),
        contains('name_whitespace'),
      );
    });

    test('resolves mixed-case and alias species keys to one canonical key', () {
      final drug = Drug.fromJson(<String, Object?>{
        'id': 'd010',
        'name': 'Dravexin',
        'concentration': '20 mg/mL',
        'route': 'IM',
        'doses': {
          'Dog': {'min': 2, 'max': 4, 'unit': 'mg/kg'},
          'feline': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
        },
      });

      expect(drug.speciesDoses.keys, containsAll(<String>['dog', 'cat']));
      expect(drug.doseFor('DOG')!.range!.min, 2);
      expect(drug.doseFor('cat')!.range!.max, 2);
      expect(drug.usableSpecies, containsAll(<String>['dog', 'cat']));
    });

    test('distinguishes an absent species from an explicit null', () {
      final drug = Drug.fromJson(<String, Object?>{
        'id': 'd003',
        'name': 'Pirovane',
        'concentration': '25 mg/mL',
        'route': 'PO',
        'doses': {
          'dog': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
          'cat': null,
        },
      });

      expect(drug.speciesDoses['cat']!.problem, DoseDataProblem.speciesNull);
      expect(drug.speciesDoses['cat']!.rawNull, isTrue);
      expect(drug.speciesDoses.containsKey('horse'), isFalse);
      expect(drug.usableSpecies, <String>['dog']);
    });

    test('records an inverted range without repairing it', () {
      final drug = Drug.fromJson(<String, Object?>{
        'id': 'd006',
        'name': 'Corvadil',
        'concentration': '10 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 8, 'max': 4, 'unit': 'mg/kg'},
        },
      });

      final dose = drug.speciesDoses['dog']!;
      expect(dose.isAvailable, isFalse);
      expect(dose.problem, DoseDataProblem.invertedRange);
      expect(dose.range, isNull, reason: 'corrupt data must not be repaired');
    });

    test('flags a non-mass-per-kg unit instead of guessing', () {
      final drug = Drug.fromJson(<String, Object?>{
        'id': 'x',
        'name': 'Oddunit',
        'concentration': '10 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 1, 'max': 2, 'unit': 'tablets'},
        },
      });

      expect(
        drug.speciesDoses['dog']!.problem,
        DoseDataProblem.unsupportedUnit,
      );
    });
  });

  group('Concentration parsing', () {
    test('parses a percentage as mg/mL (10% = 100 mg/mL)', () {
      final concentration = ParsedConcentration.parse('10%');
      expect(concentration.mgPerMl, 100);
      expect(concentration.isUsable, isTrue);
      expect(concentration.display, contains('100'));
    });

    test('parses mg/mL variants regardless of spacing and case', () {
      expect(ParsedConcentration.parse('50 mg/mL').mgPerMl, 50);
      expect(ParsedConcentration.parse('1.5mg/ml').mgPerMl, 1.5);
      expect(ParsedConcentration.parse('50 MG/ML').mgPerMl, 50);
    });

    test('converts other mass units into mg/mL', () {
      expect(ParsedConcentration.parse('1000 mcg/mL').mgPerMl, 1);
      expect(ParsedConcentration.parse('2 g/mL').mgPerMl, 2000);
      expect(ParsedConcentration.parse('500 µg/mL').mgPerMl, 0.5);
    });

    test('flags a zero concentration as the division-by-zero trap', () {
      final concentration = ParsedConcentration.parse('0 mg/mL');
      expect(concentration.problem, ConcentrationProblem.zero);
      expect(concentration.mgPerMl, isNull);
      expect(concentration.isUsable, isFalse);
    });

    test('flags missing and unparsable concentrations distinctly', () {
      expect(
        ParsedConcentration.parse(null).problem,
        ConcentrationProblem.missing,
      );
      expect(
        ParsedConcentration.parse('a pinch').problem,
        ConcentrationProblem.unparsable,
      );
    });
  });

  group('DrugDataset.fromJson', () {
    test('parses the shipped v14 dataset without throwing', () {
      final dataset = DrugDataset.fromJson(<String, Object?>{
        'schema_version': 2,
        'dataset_version': 'v14',
        'drugs': <Object?>[],
      });
      expect(dataset.schemaVersion, 2);
      expect(dataset.datasetVersion, 'v14');
    });

    test('de-duplicates names that differ only by whitespace', () {
      final dataset = DrugDataset.fromJson(<String, Object?>{
        'schema_version': 2,
        'dataset_version': 'v14',
        'drugs': [
          {
            'id': 'd004',
            'name': 'Meloquin',
            'concentration': '1.5 mg/mL',
            'route': 'PO',
            'doses': {
              'dog': {'min': 0.1, 'max': 0.2, 'unit': 'mg/kg'},
            },
          },
          {
            'id': 'd005',
            'name': 'Meloquin ',
            'concentration': '5 mg/mL',
            'route': 'SC',
            'doses': {
              'dog': {'min': 0.1, 'max': 0.2, 'unit': 'mg/kg'},
              'cat': {'min': 0.05, 'max': 0.1, 'unit': 'mg/kg'},
            },
          },
        ],
      });

      expect(dataset.drugs, hasLength(1));
      expect(dataset.duplicateNames, <String>['Meloquin']);
      // The richer entry (two usable species) wins.
      expect(dataset.drugs.single.usableSpecies, hasLength(2));
    });

    test('keeps parsing when one entry is structurally broken', () {
      final dataset = DrugDataset.fromJson(<String, Object?>{
        'schema_version': 2,
        'dataset_version': 'v14',
        'drugs': [
          {'id': 'broken', 'name': 'No doses'},
          {
            'id': 'fine',
            'name': 'Fine',
            'concentration': '10 mg/mL',
            'route': 'IV',
            'doses': {
              'dog': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
            },
          },
        ],
      });

      expect(dataset.drugs, hasLength(2));
      expect(dataset.drugs.first.usableSpecies, isEmpty);
      expect(dataset.drugs.first.issues.map((i) => i.code),
          contains('missing_doses'));
      expect(dataset.drugs.last.usableSpecies, contains('dog'));
    });

    test('throws only when the payload is unreadable', () {
      expect(
        () => DrugDataset.fromJson(<String, Object?>{'drugs': 'nope'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DrugDataset.fromJson(<String, Object?>{'drugs': <Object?>[]}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DrugDataService.parseDataset — future datasets', () {
    test('reads a v99 payload with aliases, strings and percent strength', () {
      final dataset = DrugDataService.parseDataset(jsonEncode(futureDataset()));

      expect(dataset.datasetVersion, 'v99');
      expect(DrugDataService.isSchemaSupported(dataset), isTrue);

      final drug = dataset.drugs.single;
      expect(drug.name, 'Neodrine');
      expect(drug.concentration.mgPerMl, 25); // 2.5% → 25 mg/mL
      expect(drug.route, 'IM');
      expect(drug.doseFor('dog')!.range!.min, 3); // "3" → 3
      expect(drug.doseFor('canine')!.range!.unit, 'MG/KG');
      expect(drug.doseFor('cat')!.range!.unit, 'µg/kg');
      expect(drug.doseFor('feline')!.range!.normalizedUnit, 'mcg/kg');
    });

    test('reports an unusable schema version without throwing', () {
      final payload = futureDataset()..['schema_version'] = 99;
      final dataset = DrugDataService.parseDataset(jsonEncode(payload));
      expect(DrugDataService.isSchemaSupported(dataset), isFalse);
    });

    test('rejects malformed JSON with a clear message', () {
      expect(
        () => DrugDataService.parseDataset('{not json'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('skips unknown species keys but keeps the rest of the drug', () {
      final payload = futureDataset(
        drugs: [
          {
            'id': 'n002',
            'name': 'Mixed',
            'concentration': '5 mg/mL',
            'route': 'IV',
            'doses': {
              'dog': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
              'hamster': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
            },
          },
        ],
      );

      final drug = DrugDataService.parseDataset(jsonEncode(payload)).drugs.single;
      expect(drug.usableSpecies, contains('dog'));
      expect(drug.speciesDoses.containsKey('hamster'), isFalse);
      expect(drug.issues.map((issue) => issue.code), contains('unknown_species'));
    });
  });
}
