import 'package:flutter/material.dart';

import 'data/models/dataset.dart';
import 'data/services/drug_data_service.dart';
import 'features/cri_calculator/screens/cri_calculator_screen.dart';
import 'features/dose_calculator/screens/dose_calculator_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VetifiApp());
}

class VetifiApp extends StatelessWidget {
  const VetifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vetifi Reference',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final Future<DrugDataset> _datasetFuture;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.calculate_outlined),
      selectedIcon: Icon(Icons.calculate),
      label: 'Dose',
    ),
    NavigationDestination(
      icon: Icon(Icons.water_drop_outlined),
      selectedIcon: Icon(Icons.water_drop),
      label: 'CRI',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _datasetFuture = const DrugDataService().loadBundledDataset();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DrugDataset>(
      future: _datasetFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The offline drug dataset could not be loaded. '
                  'Please check the bundled dataset.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final DrugDataset activeDataset = snapshot.data!;

        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              const DoseCalculatorScreen(),
              CriCalculatorScreen(activeDataset: activeDataset),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            destinations: _destinations,
            onDestinationSelected: (value) {
              setState(() => _index = value);
            },
          ),
        );
      },
    );
  }
}
