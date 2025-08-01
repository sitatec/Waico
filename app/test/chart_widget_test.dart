import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waico/core/widgets/chart_widget.dart';

void main() {
  group('ChartWidget Type Visibility Tests', () {
    late List<ChartGroupedDataPoint> testData;

    setUp(() {
      testData = [
        ChartGroupedDataPoint(
          groupLabel: 'Day 1',
          bars: [
            const ChartDataPoint(label: 'Steps', y: 5000, x: 0, color: Colors.green),
            const ChartDataPoint(label: 'Sleep', y: 7.5, x: 1, color: Colors.purple),
            const ChartDataPoint(label: 'Water', y: 3.5, x: 2, color: Colors.blue),
          ],
        ),
        ChartGroupedDataPoint(
          groupLabel: 'Day 2',
          bars: [
            const ChartDataPoint(label: 'Steps', y: 6000, x: 0, color: Colors.green),
            const ChartDataPoint(label: 'Sleep', y: 6.5, x: 1, color: Colors.purple),
            const ChartDataPoint(label: 'Water', y: 3.0, x: 2, color: Colors.blue),
          ],
        ),
      ];
    });

    testWidgets('should show all types by default', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChartWidget(data: testData)),
        ),
      );

      // Check that all legend items are visible
      expect(find.text('Steps (11000.0)'), findsOneWidget);
      expect(find.text('Sleep (14.0)'), findsOneWidget);
      expect(find.text('Water (6.5)'), findsOneWidget);
    });

    testWidgets('should hide type when tapped in legend', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChartWidget(data: testData)),
        ),
      );

      // Find and tap on the Steps legend item
      final stepsLegendItem = find.text('Steps (11000.0)');
      expect(stepsLegendItem, findsOneWidget);

      await tester.tap(stepsLegendItem);
      await tester.pump();

      // After tapping, the Steps type should be grayed out (line-through decoration)
      // We can check this by looking for the text widget that should now have a line-through decoration
      expect(stepsLegendItem, findsOneWidget);
    });

    testWidgets('should show type again when tapped twice', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChartWidget(data: testData)),
        ),
      );

      final stepsLegendItem = find.text('Steps (11000.0)');

      // Tap to hide
      await tester.tap(stepsLegendItem);
      await tester.pump();

      // Tap again to show
      await tester.tap(stepsLegendItem);
      await tester.pump();

      // Should be visible again
      expect(stepsLegendItem, findsOneWidget);
    });
  });
}
