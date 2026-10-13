import 'package:app/data/models/dataset.dart';
import 'package:app/data/models/drug.dart';
import 'package:app/data/services/drug_data_service.dart';
import 'package:app/features/dose_calculator/screens/dose_calculator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the real bundled asset path from an in-memory payload, so widget tests
/// exercise the production loader instead of a stubbed model.
class _FakeDataService extends DrugDataService {
  const _FakeDataService();

  @override
  Future<DrugDataset> loadBundledDataset() async =>
      DrugDataService.parseDataset(_payload);
}

const _payload = '''
{
  "schema_version": 2,
  "dataset_version": "v14",
  "drugs": [
    {"id": "d001", "name": "Veloxamine", "concentration": "50 mg/mL", "route": "IV",
     "doses": {"dog": {"min": 5, "max": 10, "unit": "mg/kg"},
               "cat": {"min": 2, "max": 4, "unit": "mg/kg"}}},
    {"id": "d002", "name": "Tranzorel", "concentration": "1 mg/mL", "route": "IM",
     "doses": {"dog": {"min": 10, "max": 20, "unit": "mcg/kg"},
               "cat": {"min": 5, "max": 10, "unit": "mcg/kg"}}},
    {"id": "d003", "name": "Pirovane", "concentration": "25 mg/mL", "route": "PO",
     "doses": {"dog": {"min": 1, "max": 2, "unit": "mg/kg"}, "cat": null}},
    {"id": "d006", "name": "Corvadil", "concentration": "10 mg/mL", "route": "IV",
     "doses": {"dog": {"min": 8, "max": 4, "unit": "mg/kg"}}},
    {"id": "d007", "name": "Benzaprol", "concentration": "10%", "route": "IV",
     "doses": {"dog": {"min": 2, "max": 5, "unit": "mg/kg"},
               "cat": {"min": 2, "max": 5, "unit": "mg/kg"}}},
    {"id": "d008", "name": "Zentrafen", "concentration": "100 mg/mL", "route": "PO",
     "max_total_mg": 400,
     "doses": {"dog": {"min": 10, "max": 15, "unit": "mg/kg"}}},
    {"id": "d009", "name": "Quilomid", "concentration": "0 mg/mL", "route": "IV",
     "doses": {"dog": {"min": 1, "max": 3, "unit": "mg/kg"}}}
  ]
}
''';

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: DoseCalculatorScreen(dataService: _FakeDataService()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The drug picker is the first dropdown on the screen.
///
/// Typed finders cannot see a `DropdownButtonFormField<Drug>` (it is generic
/// over the app's own type), so the untyped inner dropdown is used instead.
Finder get _drugField => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButton &&
      (widget.items?.any((item) => item.value is Drug) ?? false),
);

/// The species picker.
Finder get _speciesField => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButton &&
      (widget.items?.any(
            (item) => item.value == 'dog' || item.value == 'cat',
          ) ??
          false),
);

/// The weight unit picker (`kg` / `lb`).
Finder get _unitField => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButton &&
      (widget.items?.any((item) => item.value == 'kg' || item.value == 'lb') ??
          false),
);

Future<void> _selectDrug(WidgetTester tester, String name) async {
  await tester.tap(_drugField);
  await tester.pumpAndSettle();
  // The closed field shows the current selection, so the menu entry for the
  // same drug is the *last* match — unless it is already selected, in which
  // case the menu entry is the only new match.
  final candidates = find.text(name);
  await tester.tap(candidates.last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _enterWeight(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextFormField).first, value);
  await tester.pumpAndSettle();
}

Future<void> _tapCalculate(WidgetTester tester) async {
  final button = find.text('Calculate dose');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads the dataset and pre-selects a usable combination', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Dose Calculator'), findsOneWidget);
    expect(find.textContaining('Dataset v14'), findsOneWidget);
    expect(find.text('Veloxamine'), findsWidgets);
  });

  testWidgets('calculates and shows the mg and mL ranges', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Veloxamine');
    await _enterWeight(tester, '20');
    await _tapCalculate(tester);

    expect(find.textContaining('100 – 200 mg'), findsOneWidget);
    expect(find.textContaining('2 – 4 mL'), findsOneWidget);
  });

  testWidgets('accepts a comma decimal weight', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Veloxamine');
    await _enterWeight(tester, '4,5');
    await _tapCalculate(tester);

    // 4.5 kg × 5–10 mg/kg = 22.5–45 mg at 50 mg/mL → 0.45–0.9 mL.
    expect(find.textContaining('22.5 – 45 mg'), findsOneWidget);
    expect(find.textContaining('0.45 – 0.9 mL'), findsOneWidget);
  });

  testWidgets('shows an inline error for an impossible weight', (tester) async {
    await _pumpScreen(tester);

    await _enterWeight(tester, '-5');
    await _tapCalculate(tester);

    expect(find.textContaining('valid weight'), findsWidgets);
    expect(find.textContaining('mL'), findsNothing);
  });

  testWidgets('surfaces the zero-concentration kill-switch', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Quilomid');
    await _enterWeight(tester, '10');
    await _tapCalculate(tester);

    expect(find.text('Concentration unusable'), findsOneWidget);
    expect(find.textContaining('0 mg/mL'), findsOneWidget);
  });

  testWidgets('surfaces the inverted-range kill-switch', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Corvadil');
    await _enterWeight(tester, '10');
    await _tapCalculate(tester);
    expect(find.text('Dose data rejected'), findsOneWidget);
    expect(find.textContaining('corrupt'), findsOneWidget);
  });

  testWidgets('disables the null species but keeps it visible', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Pirovane');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Cat: The dataset lists this species as null'),
      findsOneWidget,
    );

    // The species dropdown no longer offers a selectable Cat entry.
    await tester.tap(_speciesField);
    await tester.pumpAndSettle();
    final catItem = tester.widget<DropdownMenuItem<String>>(
      find
          .ancestor(
            of: find.text('Cat'),
            matching: find.byType(DropdownMenuItem<String>),
          )
          .first,
    );
    expect(catItem.enabled, isFalse);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('flags the absolute cap and shows the uncapped range', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Zentrafen');
    await _enterWeight(tester, '40');
    await _tapCalculate(tester);

    expect(find.textContaining('400 – 400 mg'), findsOneWidget);
    expect(
      find.textContaining('Capped at the dataset maximum'),
      findsOneWidget,
    );
    expect(find.textContaining('400 – 600 mg'), findsOneWidget);
  });

  testWidgets('refuses an ambiguous percentage concentration', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Benzaprol');
    await _enterWeight(tester, '10');
    await _tapCalculate(tester);

    expect(find.text('Concentration unusable'), findsOneWidget);
    expect(find.textContaining('explicit mass-per-mL'), findsOneWidget);
    expect(find.textContaining('Volume to draw up'), findsNothing);
  });

  testWidgets('converts a pound weight before calculating', (tester) async {
    await _pumpScreen(tester);

    await _selectDrug(tester, 'Veloxamine');
    await _enterWeight(tester, '22.0462');

    await tester.tap(_unitField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lb').last);
    await tester.pumpAndSettle();

    await _tapCalculate(tester);

    expect(find.textContaining('(from 22.0462 lb)'), findsOneWidget);
  });
}
