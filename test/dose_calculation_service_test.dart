import 'package:app/data/models/dose_result.dart';
import 'package:app/data/models/drug.dart';
import 'package:app/data/services/dose_calculation_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a drug through the real JSON parser, so every test exercises the
/// normalisation layer as well as the calculator.
Drug drugFrom(Map<String, Object?> json) => Drug.fromJson(json);

const _service = DoseCalculationService();

void main() {
  group('Happy path — mg and mL ranges', () {
    test('computes a mg/kg drug for a dog', () {
      final drug = drugFrom({
        'id': 'd001',
        'name': 'Veloxamine',
        'concentration': '50 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 5, 'max': 10, 'unit': 'mg/kg'},
          'cat': {'min': 2, 'max': 4, 'unit': 'mg/kg'},
        },
      });

      final result = _service.calculate(
        drug: drug,
        species: 'dog',
        weightKg: 20,
        datasetVersion: 'v14',
      );

      expect(result.doseMinMg, 100);
      expect(result.doseMaxMg, 200);
      expect(result.volumeMinMl, 2);
      expect(result.volumeMaxMl, 4);
      expect(result.capApplied, isFalse);
    });

    test('accepts a species key in any casing at the call site', () {
      final drug = drugFrom({
        'id': 'd010',
        'name': 'Dravexin',
        'concentration': '20 mg/mL',
        'route': 'IM',
        'doses': {
          'Dog': {'min': 2, 'max': 4, 'unit': 'mg/kg'},
          'feline': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
        },
      });

      final result = _service.calculate(
        drug: drug,
        species: 'CAT',
        weightKg: 4,
        datasetVersion: 'v14',
      );

      expect(result.species, 'cat');
      expect(result.doseMinMg, 4);
      expect(result.doseMaxMg, 8);
      expect(result.volumeMinMl, closeTo(0.2, 1e-9));
    });
  });

  group('Metric conversion guard', () {
    test('converts mcg/kg to mg before multiplying by weight', () {
      final drug = drugFrom({
        'id': 'd002',
        'name': 'Tranzorel',
        'concentration': '1 mg/mL',
        'route': 'IM',
        'doses': {
          'dog': {'min': 10, 'max': 20, 'unit': 'mcg/kg'},
        },
      });

      // 10 mcg/kg × 20 kg = 200 mcg = 0.2 mg.
      final result = _service.calculate(
        drug: drug,
        species: 'dog',
        weightKg: 20,
        datasetVersion: 'v14',
      );

      expect(result.doseUnit, 'mcg/kg');
      expect(result.doseMinMg, closeTo(0.2, 1e-12));
      expect(result.doseMaxMg, closeTo(0.4, 1e-12));
      expect(result.volumeMinMl, closeTo(0.2, 1e-12));
      expect(result.volumeMaxMl, closeTo(0.4, 1e-12));
    });

    test('treats µg/kg and ug/kg as mcg/kg', () {
      for (final unit in ['µg/kg', 'ug/kg', 'UG/KG']) {
        final drug = drugFrom({
          'id': 'u',
          'name': 'Micro',
          'concentration': '1 mg/mL',
          'route': 'IV',
          'doses': {
            'dog': {'min': 1000, 'max': 2000, 'unit': unit},
          },
        });

        final result = _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 1,
          datasetVersion: 'v14',
        );

        expect(result.doseMinMg, closeTo(1, 1e-12), reason: unit);
        expect(result.doseMaxMg, closeTo(2, 1e-12), reason: unit);
      }
    });
  });

  group('Ambiguous concentration', () {
    test('10% is refused rather than guessed as mg/mL', () {
      final drug = drugFrom({
        'id': 'd007',
        'name': 'Benzaprol',
        'concentration': '10%',
        'route': 'IV',
        'doses': {
          'dog': {'min': 2, 'max': 5, 'unit': 'mg/kg'},
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 10,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.unparsableConcentration,
          ),
        ),
      );
    });
  });

  group('Absolute dose cap (max_total_mg)', () {
    final capped = drugFrom({
      'id': 'd008',
      'name': 'Zentrafen',
      'concentration': '100 mg/mL',
      'route': 'PO',
      'max_total_mg': 400,
      'doses': {
        'dog': {'min': 10, 'max': 15, 'unit': 'mg/kg'},
      },
    });

    test('clamps the ceiling at the cap and keeps the range ordered', () {
      // 40 kg → 400–600 mg, capped at 400 mg.
      final result = _service.calculate(
        drug: capped,
        species: 'dog',
        weightKg: 40,
        datasetVersion: 'v14',
      );

      expect(result.doseMaxMg, 400);
      expect(result.doseMinMg, 400);
      expect(result.doseMinMg <= result.doseMaxMg, isTrue);
      expect(result.volumeMaxMl, 4);
      expect(result.capApplied, isTrue);
      expect(result.uncappedDoseMaxMg, 600);
      expect(result.absoluteCapMg, 400);
    });

    test('does not touch a range that is already under the cap', () {
      final result = _service.calculate(
        drug: capped,
        species: 'dog',
        weightKg: 10,
        datasetVersion: 'v14',
      );

      expect(result.capApplied, isFalse);
      expect(result.doseMaxMg, 150);
      expect(result.uncappedDoseMaxMg, isNull);
    });

    test('refuses when the cap is below the therapeutic floor', () {
      // 50 kg → floor 500 mg, above the 400 mg ceiling: capping would advise a
      // sub-therapeutic dose.
      expect(
        () => _service.calculate(
          drug: capped,
          species: 'dog',
          weightKg: 50,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.absoluteCapBelowMinimum,
          ),
        ),
      );
    });

    test('refuses an invalid stated cap rather than ignoring it', () {
      final drug = drugFrom({
        'id': 'x',
        'name': 'Badcap',
        'concentration': '10 mg/mL',
        'route': 'IV',
        'max_total_mg': 'unknown',
        'doses': {
          'dog': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
        },
      });

      expect(drug.hasAbsoluteCap, isFalse);
      expect(drug.hasInvalidMaxTotalMg, isTrue);
      expect(
        () => _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 10,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.invalidMaximumTotalDose,
          ),
        ),
      );
    });
  });

  group('Kill-switches', () {
    test('(a) zero concentration is refused, not divided by', () {
      final drug = drugFrom({
        'id': 'd009',
        'name': 'Quilomid',
        'concentration': '0 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 1, 'max': 3, 'unit': 'mg/kg'},
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 10,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>()
              .having(
                (error) => error.code,
                'code',
                DoseCalculationErrorCode.zeroConcentration,
              )
              .having(
                (error) => error.message,
                'message',
                contains('0 mg/mL'),
              ),
        ),
      );
    });

    test('(b) an explicit null species is refused with its own message', () {
      final drug = drugFrom({
        'id': 'd003',
        'name': 'Pirovane',
        'concentration': '25 mg/mL',
        'route': 'PO',
        'doses': {
          'dog': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
          'cat': null,
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'cat',
          weightKg: 4,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.speciesNull,
          ),
        ),
      );
    });

    test('(b) a species missing from the keys is refused distinctly', () {
      final drug = drugFrom({
        'id': 'd004',
        'name': 'Meloquin',
        'concentration': '1.5 mg/mL',
        'route': 'PO',
        'doses': {
          'dog': {'min': 0.1, 'max': 0.2, 'unit': 'mg/kg'},
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'cat',
          weightKg: 4,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.speciesMissing,
          ),
        ),
      );
    });

    test('(c) an inverted range is refused rather than swapped', () {
      final drug = drugFrom({
        'id': 'd006',
        'name': 'Corvadil',
        'concentration': '10 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 8, 'max': 4, 'unit': 'mg/kg'},
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 10,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.doseRangeInverted,
          ),
        ),
      );
    });

    test('an unsupported dose unit is refused', () {
      final drug = drugFrom({
        'id': 'x',
        'name': 'Odd',
        'concentration': '10 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 1, 'max': 2, 'unit': 'mg/animal'},
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 10,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.unsupportedDoseUnit,
          ),
        ),
      );
    });

    test('an unreadable concentration is refused before any maths', () {
      final drug = drugFrom({
        'id': 'x',
        'name': 'Vague',
        'concentration': 'concentrated',
        'route': 'IV',
        'doses': {
          'dog': {'min': 1, 'max': 2, 'unit': 'mg/kg'},
        },
      });

      expect(
        () => _service.calculate(
          drug: drug,
          species: 'dog',
          weightKg: 10,
          datasetVersion: 'v14',
        ),
        throwsA(
          isA<DoseCalculationException>().having(
            (error) => error.code,
            'code',
            DoseCalculationErrorCode.unparsableConcentration,
          ),
        ),
      );
    });

    test('impossible weights are refused', () {
      final drug = drugFrom({
        'id': 'd001',
        'name': 'Veloxamine',
        'concentration': '50 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 5, 'max': 10, 'unit': 'mg/kg'},
        },
      });

      for (final weight in [0.0, -3.0, double.nan, double.infinity, 5000.0]) {
        expect(
          () => _service.calculate(
            drug: drug,
            species: 'dog',
            weightKg: weight,
            datasetVersion: 'v14',
          ),
          throwsA(isA<DoseCalculationException>()),
          reason: 'weight $weight must be refused',
        );
      }
    });
  });

  group('checkAvailability', () {
    test('reports unusable combinations without throwing', () {
      final drug = drugFrom({
        'id': 'd006',
        'name': 'Corvadil',
        'concentration': '10 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 8, 'max': 4, 'unit': 'mg/kg'},
        },
      });

      final dog = _service.checkAvailability(drug: drug, species: 'dog');
      final cat = _service.checkAvailability(drug: drug, species: 'cat');

      expect(dog.isUsable, isFalse);
      expect(dog.blocker!.code, DoseCalculationErrorCode.doseRangeInverted);
      expect(cat.isUsable, isFalse);
      expect(cat.blocker!.code, DoseCalculationErrorCode.speciesMissing);
    });

    test('agrees with calculate for a usable combination', () {
      final drug = drugFrom({
        'id': 'd001',
        'name': 'Veloxamine',
        'concentration': '50 mg/mL',
        'route': 'IV',
        'doses': {
          'dog': {'min': 5, 'max': 10, 'unit': 'mg/kg'},
        },
      });

      expect(
        _service.checkAvailability(drug: drug, species: 'dog').isUsable,
        isTrue,
      );
    });
  });

  group('Result formatting', () {
    test('summary is readable and free of trailing zeros', () {
      final drug = drugFrom({
        'id': 'd002',
        'name': 'Tranzorel',
        'concentration': '1 mg/mL',
        'route': 'IM',
        'doses': {
          'dog': {'min': 10, 'max': 20, 'unit': 'mcg/kg'},
        },
      });

      final result = _service.calculate(
        drug: drug,
        species: 'dog',
        weightKg: 20,
        datasetVersion: 'v14',
      );

      expect(result.summary, '0.2–0.4 mg (0.2–0.4 mL)');
      expect(result.doseRangeLabel, '10–20 mcg/kg');
      expect(result.speciesLabel, 'Dog');
    });
  });
}
