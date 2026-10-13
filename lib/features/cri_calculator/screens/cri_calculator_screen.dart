import 'package:app/data/models/dataset.dart';
import 'package:flutter/material.dart';

class CriCalculatorScreen extends StatefulWidget {
  final DrugDataset activeDataset;

  const CriCalculatorScreen({super.key, required this.activeDataset});

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

  void _calculate() {
    setState(() {
      _result = null;
      _error =
          'CRI calculation is currently unavailable.\n\n'
          'The required CRI drug information is not available '
          'for calculation in the currently loaded dataset. '
          'No calculation has been performed.';
    });
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
      appBar: AppBar(
        title: const Text('CRI Calculator'),
        backgroundColor: Color(0xFF11B35A),
      ),
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
              labelText: 'Dose rate (mcg/kg/min)',
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
