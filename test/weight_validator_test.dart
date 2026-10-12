import 'package:app/core/validation/weight_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeightValidator.parseNumber', () {
    test('accepts plain decimals and integers', () {
      expect(WeightValidator.parseNumber('4.5'), 4.5);
      expect(WeightValidator.parseNumber('12'), 12);
      expect(WeightValidator.parseNumber('  7.25  '), 7.25);
    });

    test('accepts comma as a decimal separator', () {
      expect(WeightValidator.parseNumber('4,5'), 4.5);
      expect(WeightValidator.parseNumber('0,25'), 0.25);
      expect(WeightValidator.parseNumber(',5'), 0.5);
    });

    test('resolves thousands separators when both separators are present', () {
      expect(WeightValidator.parseNumber('1.234,5'), 1234.5);
      expect(WeightValidator.parseNumber('1,234.5'), 1234.5);
    });

    test('treats a comma with exactly three trailing digits as thousands', () {
      expect(WeightValidator.parseNumber('1,234'), 1234);
    });

    test('tolerates a trailing unit typed into the field', () {
      expect(WeightValidator.parseNumber('4.5 kg'), 4.5);
      expect(WeightValidator.parseNumber('22lb'), 22);
    });

    test('rejects impossible, negative and non-numeric weights', () {
      expect(WeightValidator.parseNumber(''), isNull);
      expect(WeightValidator.parseNumber('   '), isNull);
      expect(WeightValidator.parseNumber('-4'), isNull);
      expect(WeightValidator.parseNumber('0'), isNull);
      expect(WeightValidator.parseNumber('abc'), isNull);
      expect(WeightValidator.parseNumber('NaN'), isNull);
      expect(WeightValidator.parseNumber('Infinity'), isNull);
      expect(WeightValidator.parseNumber('1e3'), isNull);
      expect(WeightValidator.parseNumber('1,2,3'), isNull);
    });
  });

  group('WeightValidator.toKg', () {
    test('passes kilograms through', () {
      expect(WeightValidator.toKg(10, 'kg'), 10);
      expect(WeightValidator.toKg(10, 'KG'), 10);
    });

    test('converts pounds and grams', () {
      expect(WeightValidator.toKg(22.046226218487757, 'lb'), closeTo(10, 1e-9));
      expect(WeightValidator.toKg(5000, 'g'), 5);
    });

    test('rejects unknown units', () {
      expect(WeightValidator.toKg(10, 'stone'), isNull);
    });
  });

  group('WeightValidator.parseToKg', () {
    test('parses a locale-formatted pound weight', () {
      final kg = WeightValidator.parseToKg(input: '22,05', unit: 'lb');
      expect(kg, closeTo(10.0017, 0.01));
    });

    test('throws a clinician-facing message for empty input', () {
      expect(
        () => WeightValidator.parseToKg(input: '', unit: 'kg'),
        throwsA(
          isA<WeightFormatException>().having(
            (error) => error.message,
            'message',
            contains('Enter the animal'),
          ),
        ),
      );
    });

    test('throws when the weight is out of the supported range', () {
      expect(
        () => WeightValidator.parseToKg(input: '900', unit: 'kg'),
        throwsA(
          isA<WeightFormatException>().having(
            (error) => error.message,
            'message',
            contains('maximum'),
          ),
        ),
      );
    });

    test('never returns a value the calculator would refuse', () {
      for (final input in ['0', '-1', 'abc', '0,001']) {
        expect(
          WeightValidator.tryParseToKg(input: input, unit: 'kg'),
          isNull,
          reason: 'input "$input" must not produce a usable weight',
        );
      }
    });
  });
}
