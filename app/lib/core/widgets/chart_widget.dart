import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:waico/core/constants.dart' as k;

/// Data model for chart data points
class ChartDataPoint {
  final double x;
  final double y;
  final String? label;
  final Color? color;

  const ChartDataPoint({required this.x, required this.y, this.label, this.color});
}

/// Enum to define chart display types
enum ChartType { line, bar }

/// A chart widget that can display line or bar charts with a total value display.
class ChartWidget extends StatefulWidget {
  /// List of data points to display in the chart
  final List<ChartDataPoint> data;

  /// Initial chart type (line or bar)
  final ChartType initialChartType;

  /// Whether to show the chart type toggle button
  final bool showToggleButton;

  /// Whether to show the total value
  final bool showTotal;

  /// Custom title for the chart
  final String? title;

  /// Custom label for the total value
  final String totalLabel;

  /// Number of decimal places for the total value
  final int totalDecimalPlaces;

  /// Primary color for the chart elements
  final Color primaryColor;

  /// Background color for the chart area
  final Color? backgroundColor;

  /// Callback when chart type changes
  final ValueChanged<ChartType>? onChartTypeChanged;

  /// Custom formatter for Y-axis values
  final String Function(double)? yAxisFormatter;

  /// Custom formatter for X-axis values
  final String Function(double)? xAxisFormatter;

  const ChartWidget({
    super.key,
    required this.data,
    this.initialChartType = ChartType.line,
    this.showToggleButton = true,
    this.showTotal = true,
    this.title,
    this.totalLabel = 'Total',
    this.totalDecimalPlaces = 1,
    this.primaryColor = k.primaryColor,
    this.backgroundColor,
    this.onChartTypeChanged,
    this.yAxisFormatter,
    this.xAxisFormatter,
  });

  @override
  State<ChartWidget> createState() => _ChartWidgetState();
}

class _ChartWidgetState extends State<ChartWidget> {
  late ChartType _currentChartType;

  @override
  void initState() {
    super.initState();
    _currentChartType = widget.initialChartType;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with title, total, and toggle button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Title and total section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.title != null) ...[
                        Text(
                          widget.title!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (widget.showTotal) _buildTotalDisplay(context),
                    ],
                  ),
                ),

                // Chart type toggle button
                if (widget.showToggleButton)
                  Container(
                    decoration: BoxDecoration(
                      color: widget.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToggleOption(context, ChartType.line, Icons.show_chart, 'Line'),
                        _buildToggleOption(context, ChartType.bar, Icons.bar_chart, 'Bar'),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Chart area
          Padding(padding: const EdgeInsets.all(16.0), child: _buildChart(context)),
        ],
      ),
    );
  }

  /// Builds the total value display
  Widget _buildTotalDisplay(BuildContext context) {
    final total = widget.data.fold<double>(0, (sum, point) => sum + point.y);

    return Row(
      children: [
        Text(
          '${widget.totalLabel}: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        Text(
          total.toStringAsFixed(widget.totalDecimalPlaces),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: widget.primaryColor),
        ),
      ],
    );
  }

  /// Builds a single toggle option
  Widget _buildToggleOption(BuildContext context, ChartType type, IconData icon, String tooltip) {
    final isSelected = _currentChartType == type;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _toggleChartType(type),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? widget.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 20, color: isSelected ? Colors.white : widget.primaryColor),
        ),
      ),
    );
  }

  /// Toggles between chart types
  void _toggleChartType(ChartType type) {
    if (_currentChartType != type) {
      setState(() {
        _currentChartType = type;
      });
      widget.onChartTypeChanged?.call(type);
    }
  }

  /// Builds the appropriate chart based on current type
  Widget _buildChart(BuildContext context) {
    if (widget.data.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
      );
    }

    switch (_currentChartType) {
      case ChartType.line:
        return _buildLineChart(context);
      case ChartType.bar:
        return _buildBarChart(context);
    }
  }

  /// Builds a line chart
  Widget _buildLineChart(BuildContext context) {
    final spots = widget.data.map((point) => FlSpot(point.x, point.y)).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
          getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
        ),
        titlesData: _buildTitlesData(),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: widget.primaryColor,
            barWidth: 3,
            isStrokeCapRound: true,
            preventCurveOverShooting: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: widget.primaryColor,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(show: true, color: widget.primaryColor.withOpacity(0.1)),
          ),
        ],
        minX: widget.data.map((e) => e.x).reduce((a, b) => a < b ? a : b),
        maxX: widget.data.map((e) => e.x).reduce((a, b) => a > b ? a : b),
        minY: 0,
        maxY: widget.data.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.1,
      ),
    );
  }

  /// Builds a bar chart
  Widget _buildBarChart(BuildContext context) {
    final barGroups = widget.data.asMap().entries.map((entry) {
      final index = entry.key;
      final point = entry.value;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: point.y,
            color: point.color ?? widget.primaryColor,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: widget.data.map((e) => e.y).reduce((a, b) => a > b ? a : b),
              color: Colors.grey.withOpacity(0.1),
            ),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: widget.data.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.1,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final point = widget.data[groupIndex];
              return BarTooltipItem(
                '${point.label ?? 'Value'}\n${point.y.toStringAsFixed(1)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: _buildBarTitlesData(),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
        ),
      ),
    );
  }

  /// Builds titles data for line chart
  FlTitlesData _buildTitlesData() {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final formatted = widget.xAxisFormatter?.call(value) ?? value.toInt().toString();
            return Text(formatted, style: const TextStyle(fontSize: 12, color: Colors.grey));
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            final formatted = widget.yAxisFormatter?.call(value) ?? value.toStringAsFixed(0);
            return Text(formatted, style: const TextStyle(fontSize: 12, color: Colors.grey));
          },
        ),
      ),
    );
  }

  /// Builds titles data for bar chart
  FlTitlesData _buildBarTitlesData() {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index >= 0 && index < widget.data.length) {
              final label =
                  widget.data[index].label ??
                  widget.xAxisFormatter?.call(widget.data[index].x) ??
                  widget.data[index].x.toInt().toString();
              return Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey));
            }
            return const Text('');
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            final formatted = widget.yAxisFormatter?.call(value) ?? value.toStringAsFixed(0);
            return Text(formatted, style: const TextStyle(fontSize: 12, color: Colors.grey));
          },
        ),
      ),
    );
  }

  /// Calculates appropriate interval for axis values
  // double _calculateInterval(Iterable<double> values) {
  //   if (values.isEmpty) return 1.0;

  //   final min = values.reduce((a, b) => a < b ? a : b);
  //   final max = values.reduce((a, b) => a > b ? a : b);
  //   final range = max - min;

  //   if (range <= 0) return 1.0;

  //   // Calculate a nice interval that gives approximately 5-8 ticks
  //   final rawInterval = range / 6;
  //   final magnitude = rawInterval == 0 ? 1.0 : pow(10.0, (log(rawInterval) / ln10).floor()).toDouble();
  //   final normalized = rawInterval / magnitude;

  //   double interval;
  //   if (normalized <= 1) {
  //     interval = magnitude;
  //   } else if (normalized <= 2) {
  //     interval = (2 * magnitude).toDouble();
  //   } else if (normalized <= 5) {
  //     interval = (5 * magnitude).toDouble();
  //   } else {
  //     interval = (10 * magnitude).toDouble();
  //   }

  //   return interval;
  // }
}
