import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/firestore_stock_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const StockTrackerApp());
  } catch (e, stack) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText('Error al iniciar Firebase:\n$e\n\n$stack'),
        ),
      ),
    ));
  }
}

class StockTrackerApp extends StatefulWidget {
  const StockTrackerApp({super.key});

  @override
  State<StockTrackerApp> createState() => _StockTrackerAppState();
}

class _StockTrackerAppState extends State<StockTrackerApp> {
  late final FirestoreStockService _stockService;

  @override
  void initState() {
    super.initState();
    _stockService = FirestoreStockService();
  }

  @override
  void dispose() {
    _stockService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: HomeScreen(stockService: _stockService),
    );
  }
}