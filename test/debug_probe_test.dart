import 'package:app/data/services/drug_data_service.dart';
import 'package:app/data/models/drug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads the bundled v14 dataset without a network request', (
    tester,
  ) async {
    final dataset = await const DrugDataService().loadBundledDataset();

    expect(dataset.datasetVersion, 'v14');
    expect(dataset.schemaVersion, 2);
    expect(dataset.drugs, isNotEmpty);
    expect(dataset.drugs.any((drug) => drug.name == 'Veloxamine'), isTrue);

    final pirovane = dataset.drugs.singleWhere((drug) => drug.id == 'd003');
    final corvadil = dataset.drugs.singleWhere((drug) => drug.id == 'd006');
    final benzaprol = dataset.drugs.singleWhere((drug) => drug.id == 'd007');
    final quilomid = dataset.drugs.singleWhere((drug) => drug.id == 'd009');
    final dravexin = dataset.drugs.singleWhere((drug) => drug.id == 'd010');

    expect(pirovane.doseFor('cat')!.problem, DoseDataProblem.speciesNull);
    expect(corvadil.doseFor('dog')!.problem, DoseDataProblem.invertedRange);
    expect(benzaprol.concentration.problem, ConcentrationProblem.ambiguous);
    expect(quilomid.concentration.problem, ConcentrationProblem.zero);
    expect(dravexin.usableSpecies, containsAll(<String>['dog', 'cat']));
    expect(
      dataset.allIssues.map((issue) => issue.code),
      contains('ambiguous_name'),
    );
  });
}
