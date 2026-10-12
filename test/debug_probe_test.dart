import 'package:app/data/models/dataset.dart';
import 'package:app/data/services/drug_data_service.dart';
import 'package:app/features/dose_calculator/screens/dose_calculator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataService extends DrugDataService {
  const _FakeDataService();

  @override
  Future<DrugDataset> loadBundledDataset() async =>
      DrugDataService.parseDataset('''
{"schema_version": 2, "dataset_version": "v14", "drugs": [
 {"id":"d001","name":"Veloxamine","concentration":"50 mg/mL","route":"IV",
  "doses":{"dog":{"min":5,"max":10,"unit":"mg/kg"}}},
 {"id":"d002","name":"Tranzorel","concentration":"1 mg/mL","route":"IM",
  "doses":{"dog":{"min":10,"max":20,"unit":"mcg/kg"}}}]}
''');
}

void main() {
  testWidgets('debug tree', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DoseCalculatorScreen(dataService: _FakeDataService()),
    ));
    await tester.pumpAndSettle();

    final field = find.byType(DropdownButton<Object?>);
    debugPrint('all matches: ${field.evaluate().length}');
    for (final element in field.evaluate().toList()) {
      debugPrint('  -> ${element.widget.runtimeType} '
          '${element.widget is DropdownButton<Object?> ? (element.widget as DropdownButton<Object?>).value : ''}');
    }
    // Inspect the View ancestry of each individual match.
    for (final element in field.evaluate().toList()) {
      final ancestors = find
          .ancestor(of: find.byWidget(element.widget), matching: find.byType(View))
          .evaluate()
          .length;
      debugPrint('element ${element.widget.runtimeType} viewAncestors=$ancestors');
    }

    await tester.tap(field.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    debugPrint('after open, Veloxamine=${find.text('Veloxamine').evaluate().length} '
        'Tranzorel=${find.text('Tranzorel').evaluate().length}');

    final candidate = find.text('Tranzorel');
    debugPrint('candidate all=${candidate.evaluate().length} '
        'first=${candidate.first.evaluate().length} '
        'last=${candidate.last.evaluate().length}');
    debugPrint('last viewAncestors='
        '${find.ancestor(of: candidate.last, matching: find.byType(View)).evaluate().length}');
  });
}
