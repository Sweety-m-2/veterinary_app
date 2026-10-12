import 'package:flutter/material.dart';

import '../../../core/validation/weight_validator.dart';
import '../../../data/models/dataset.dart';
import '../../../data/models/dose_result.dart';
import '../../../data/models/drug.dart';
import '../../../data/services/dose_calculation_service.dart';
import '../../../data/services/drug_data_service.dart';
import '../widgets/dose_result_card.dart';
import '../widgets/drug_selector.dart';
import '../widgets/species_selector.dart';
import '../widgets/weight_input_field.dart';

/// Part A — offline dose calculator.
///
/// Flow: pick a drug from the bundled dataset, pick a species that has usable
/// data for it, enter a weight in kg or lb, calculate. Every failure mode of the
/// dataset surfaces as a readable, actionable message instead of a stack trace,
/// and unusable combinations are disabled before the user can select them.
class DoseCalculatorScreen extends StatefulWidget {
  const DoseCalculatorScreen({super.key, this.dataService, this.service});

  /// Injectable for tests; defaults to the bundled asset loader.
  final DrugDataService? dataService;

  /// Injectable for tests; the service is stateless and pure.
  final DoseCalculationService? service;

  @override
  State<DoseCalculatorScreen> createState() => _DoseCalculatorScreenState();
}

class _DoseCalculatorScreenState extends State<DoseCalculatorScreen> {
  final _weightController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final DrugDataService _dataService =
      widget.dataService ?? const DrugDataService();
  late final DoseCalculationService _service =
      widget.service ?? const DoseCalculationService();

  DrugDataset? _dataset;
  Drug? _selectedDrug;
  String _species = 'dog';
  String _weightUnit = 'kg';

  DoseResult? _result;
  DoseCalculationException? _calculationError;
  String? _weightFieldError;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDataset();
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadDataset() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final dataset = await _dataService.loadBundledDataset();
      if (!mounted) return;

      setState(() {
        _dataset = dataset;
        _selectedDrug = dataset.drugs.isNotEmpty ? dataset.drugs.first : null;
        _species = _firstUsableSpecies(dataset.drugs.isNotEmpty
            ? dataset.drugs.first
            : null);
        _loading = false;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'The offline dataset could not be read: $error';
        _loading = false;
      });
    }
  }

  /// Prefers a species the selected drug can actually be dosed in.
  String _firstUsableSpecies(Drug? drug) {
    if (drug == null) return 'dog';
    for (final key in DatasetNormalizer.knownSpecies) {
      if (_service.checkAvailability(drug: drug, species: key).isUsable) {
        return key;
      }
    }
    return DatasetNormalizer.knownSpecies.first;
  }

  void _resetOutcome() {
    _result = null;
    _calculationError = null;
    _weightFieldError = null;
  }

  void _onDrugChanged(Drug? drug) {
    setState(() {
      _selectedDrug = drug;
      _resetOutcome();
      if (drug != null) _species = _firstUsableSpecies(drug);
    });
  }

  void _onSpeciesChanged(String species) {
    setState(() {
      _species = species;
      _resetOutcome();
    });
  }

  void _onUnitChanged(String unit) {
    setState(() {
      _weightUnit = unit;
      _resetOutcome();
    });
  }

  void _calculate() {
    final drug = _selectedDrug;
    if (drug == null) return;

    setState(_resetOutcome);

    if (!(_formKey.currentState?.validate() ?? true)) return;

    try {
      final weightKg = WeightValidator.parseToKg(
        input: _weightController.text,
        unit: _weightUnit,
      );

      final result = _service.calculate(
        drug: drug,
        species: _species,
        weightKg: weightKg,
        datasetVersion: _dataset?.datasetVersion ?? 'unknown',
        weightInput: _weightController.text.trim(),
        weightInputUnit: _weightUnit,
      );

      setState(() => _result = result);
    } on WeightFormatException catch (error) {
      setState(() {
        _weightFieldError = error.message;
        _calculationError = DoseCalculationException(
          code: DoseCalculationErrorCode.weightInvalid,
          field: 'weight',
          message: error.message,
        );
      });
    } on DoseCalculationException catch (error) {
      setState(() {
        _calculationError = error;
        if (error.field == 'weight') _weightFieldError = error.message;
      });
    } catch (error) {
      setState(() {
        _calculationError = DoseCalculationException(
          code: DoseCalculationErrorCode.arithmeticFailure,
          message: 'The calculation could not be completed: $error',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Loading the offline drug dataset',
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }

    final dataset = _dataset;
    if (dataset == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dose Calculator')),
        body: _LoadFailure(
          message: _loadError ?? 'The offline dataset is unavailable.',
          onRetry: _loadDataset,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dose Calculator'),
        actions: [
          if (dataset.hasQualityIssues)
            IconButton(
              tooltip: 'Dataset quality report',
              onPressed: () => _showQualitySheet(dataset),
              icon: const Icon(Icons.report_problem_outlined),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            _DatasetBanner(dataset: dataset),
            const SizedBox(height: 20),

            DrugSelector(
              drugs: dataset.drugs,
              selected: _selectedDrug,
              onChanged: _onDrugChanged,
            ),
            const SizedBox(height: 16),

            SpeciesSelector(
              drug: _selectedDrug,
              selected: _species,
              onChanged: _onSpeciesChanged,
              service: _service,
            ),
            const SizedBox(height: 16),

            WeightInputField(
              controller: _weightController,
              unit: _weightUnit,
              onUnitChanged: _onUnitChanged,
              errorText: _weightFieldError,
              onSubmitted: _calculate,
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Calculate dose'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 20),

            if (_calculationError != null)
              _ErrorCard(error: _calculationError!),

            if (_result != null) DoseResultCard(result: _result!),
          ],
        ),
      ),
    );
  }

  /// Shows every dataset defect the loader tolerated, so the fix can be made in
  /// the data rather than worked around in the app.
  void _showQualitySheet(DrugDataset dataset) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(
              'Dataset quality report',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('Version ${dataset.datasetVersion} · '
                'schema ${dataset.schemaVersion}'),
            const SizedBox(height: 16),
            for (final name in dataset.duplicateNames)
              ListTile(
                dense: true,
                leading: const Icon(Icons.content_copy_outlined),
                title: Text('Duplicate entry: $name'),
                subtitle: const Text(
                  'One copy is kept — the entry with the most usable species '
                  'data. Remove the duplicate in the dataset to silence this.',
                ),
              ),
            for (final issue in dataset.allIssues)
              ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(issue.message),
                subtitle: Text(issue.code),
              ),
          ],
        ),
      ),
    );
  }
}

class _DatasetBanner extends StatelessWidget {
  const _DatasetBanner({required this.dataset});

  final DrugDataset dataset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.offline_bolt_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Offline veterinary reference',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Dataset ${dataset.datasetVersion} · '
                '${dataset.drugs.length} drugs · bundled on device',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Error card driven by the typed failure code.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final DoseCalculationException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      label: '${error.title}. ${error.message}',
      child: Card(
        elevation: 0,
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sd_card_alert_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
