import 'package:app/data/models/drug.dart';

/// Scratch probe used while developing the parsers. Not part of the app.
void main() {
  for (final unit in ['µg/kg', 'ug/kg', 'UG/KG', 'mcg/kg', 'µg/KG', 'μG/kg']) {
    print('$unit -> "${DoseUnit.normalize(unit)}" '
        'supported=${DoseUnit.isSupported(unit)}');
  }
  for (final raw in ['10%', '1000 mcg/mL', '500 µg/mL', '500 ug/ml', '2 g/mL']) {
    print('$raw -> ${ParsedConcentration.parse(raw).mgPerMl}');
  }
}
