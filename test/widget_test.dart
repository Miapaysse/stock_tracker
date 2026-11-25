import 'package:flutter_test/flutter_test.dart';
import 'package:stock_tracker/main.dart';

void main() {
  testWidgets('Carga inicial de la app Stock Tracker', (WidgetTester tester) async {
    await tester.pumpWidget(const StockTrackerApp());
    expect(find.byType(StockTrackerApp), findsOneWidget);
  });
}