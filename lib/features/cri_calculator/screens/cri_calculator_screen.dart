import 'package:flutter/material.dart';

import '../../../core/validation/weight_validator.dart';

class CriCalculatorScreen extends StatefulWidget {
  const CriCalculatorScreen({super.key});

  @override
  State<CriCalculatorScreen> createState() => _CriCalculatorScreenState();
}

class _CriCalculatorScreenState extends State<CriCalculatorScreen> {
  final _weightController = TextEditingController();
  final _doseController = TextEditingController();
  final _fluidRateController = TextEditingController();
  final _bagSizeController = TextEditingController();

  String _species = 'dog';
  String _weightUnit = 'kg';
  String? _error;
  _CriResult? _result;

  // Fictional assignment data; requires the v15 dataset.
  static const double _concentrationMgPerMl = 40;
  static const double _dogMinDoseMcgKgMin = 5;
  static const double _dogMaxDoseMcgKgMin = 10;

  double _parsePositive(String input, String label) {
    final value = double.tryParse(input.trim().replaceAll(',', '.'));

    if (value == null || !value.isFinite || value <= 0) {
      throw FormatException('$label must be a valid positive number.');
    }

    return value;
  }

  void _calculate() {
    setState(() {
      _error = null;
      _result = null;
    });

    try {
      if (_species != 'dog') {
        throw StateError(
          'No CRI dose is provided for cats in this dataset. '
          'Calculation refused.',
        );
      }

      final weightKg = WeightValidator.parseToKg(
        input: _weightController.text,
        unit: _weightUnit,
      );

      final doseMcgKgMin = _parsePositive(_doseController.text, 'Dose rate');
      final fluidRateMlHr = _parsePositive(
        _fluidRateController.text,
        'Fluid rate',
      );
      final finalBagVolumeMl = _parsePositive(
        _bagSizeController.text,
        'Final bag volume',
      );

      if (doseMcgKgMin < _dogMinDoseMcgKgMin ||
          doseMcgKgMin > _dogMaxDoseMcgKgMin) {
        throw StateError(
          'For this fictional dataset, the entered dose '
          'must be between 5 and 10 mcg/kg/min.',
        );
      }

      // Duration is based on final mixture volume.
      final durationHours = finalBagVolumeMl / fluidRateMlHr;

      // mcg/kg/min × kg × minutes gives mcg.
      // Divide by 1,000,000 to convert mcg to mg.
      final totalDrugMg =
          doseMcgKgMin * weightKg * durationHours * 60 / 1000000;

      final drugVolumeMl = totalDrugMg / _concentrationMgPerMl;

      // Assumes equal volume of fluid is withdrawn first.
      final fluidToWithdrawMl = drugVolumeMl;

      if (!drugVolumeMl.isFinite ||
          drugVolumeMl <= 0 ||
          drugVolumeMl >= finalBagVolumeMl) {
        throw StateError(
          'The calculated drug volume is invalid '
          'for the entered final bag volume.',
        );
      }

      setState(() {
        _result = _CriResult(
          durationHours: durationHours,
          totalDrugMg: totalDrugMg,
          drugVolumeMl: drugVolumeMl,
          fluidToWithdrawMl: fluidToWithdrawMl,
          finalBagVolumeMl: finalBagVolumeMl,
        );
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _doseController.dispose();
    _fluidRateController.dispose();
    _bagSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CRI Calculator')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Continuous Rate Infusion (CRI)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text('Fictional assignment data · Dopraxine'),
          const Text('Dataset requirement: v15'),
          const Text('Concentration: 40 mg/mL'),
          const SizedBox(height: 20),

          DropdownButtonFormField<String>(
            value: _species,
            decoration: const InputDecoration(
              labelText: 'Species',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'dog', child: Text('Dog')),
              DropdownMenuItem(value: 'cat', child: Text('Cat')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _species = value;
                _result = null;
                _error = null;
              });
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Weight',
              hintText: 'e.g. 12.5',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _weightUnit,
            decoration: const InputDecoration(
              labelText: 'Weight unit',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'kg', child: Text('kg')),
              DropdownMenuItem(value: 'lb', child: Text('lb')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _weightUnit = value;
                _result = null;
              });
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _doseController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Dose rate (mg/kg/min)',
              helperText: 'Dog dataset range: 5–10',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _fluidRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fluid rate (mL/hr)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bagSizeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Final bag volume (mL)',
              helperText: 'Volume after adding the drug',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          FilledButton(
            onPressed: _calculate,
            child: const Text('Calculate CRI'),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),

          if (_result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calculated reference',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Duration: '
                      '${_result!.durationHours.toStringAsFixed(3)} hours',
                    ),
                    Text(
                      'Drug required: '
                      '${_result!.totalDrugMg.toStringAsFixed(6)} mg',
                    ),
                    Text(
                      'Drug volume: '
                      '${_result!.drugVolumeMl.toStringAsFixed(6)} mL',
                    ),
                    Text(
                      'Fluid to withdraw: '
                      '${_result!.fluidToWithdrawMl.toStringAsFixed(6)} mL',
                    ),
                    Text(
                      'Final mixture volume: '
                      '${_result!.finalBagVolumeMl.toStringAsFixed(3)} mL',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Fictional assignment data only. '
                      'Not for clinical use.',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CriResult {
  final double durationHours;
  final double totalDrugMg;
  final double drugVolumeMl;
  final double fluidToWithdrawMl;
  final double finalBagVolumeMl;

  const _CriResult({
    required this.durationHours,
    required this.totalDrugMg,
    required this.drugVolumeMl,
    required this.fluidToWithdrawMl,
    required this.finalBagVolumeMl,
  });
}
