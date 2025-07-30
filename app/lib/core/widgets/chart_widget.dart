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

/// Data model for grouped bar chart data
class ChartGroupedDataPoint {
  final String groupLabel;
  final List<ChartDataPoint> bars;

  const ChartGroupedDataPoint({required this.groupLabel, required this.bars});
}

/// Helper methods for chart data manipulation
class ChartDataHelper {
  /// Groups chart data points by their labels for use in grouped bar charts
  /// This is useful when you have individual data points that you want to group
  static List<ChartGroupedDataPoint> groupDataByLabel(List<ChartDataPoint> data) {
    final Map<String, List<ChartDataPoint>> grouped = {};

    for (final point in data) {
      final label = point.label ?? 'Unlabeled';
      grouped.putIfAbsent(label, () => []).add(point);
    }

    return grouped.entries.map((entry) => ChartGroupedDataPoint(groupLabel: entry.key, bars: entry.value)).toList();
  }

  /// Creates a single-item group for individual data points
  /// Use this when you want to display single bars but need grouped data structure
  static List<ChartGroupedDataPoint> createSingleItemGroups(List<ChartDataPoint> data) {
    return data
        .map(
          (point) => ChartGroupedDataPoint(groupLabel: point.label ?? 'Item ${data.indexOf(point) + 1}', bars: [point]),
        )
        .toList();
  }
}

/// Enum to define chart display types
enum ChartType { line, bar }

/// A chart widget that can display line or bar charts with a total value display.
class ChartWidget extends StatefulWidget {
  /// List of grouped data points to display in the chart
  final List<ChartGroupedDataPoint> data;

  /// Initial chart type (line or bar)
  final ChartType initialChartType;

  /// Whether to show the chart type toggle button
  final bool showToggleButton;

  /// Whether to show the total value
  final bool showTotal;

  /// Whether to show the legend for colors
  final bool showLegend;

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
    this.initialChartType = ChartType.bar,
    this.showToggleButton = true,
    this.showTotal = true,
    this.showLegend = true,
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: widget.primaryColor,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      // Total display is now integrated into the legend
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
          Expanded(
            child: Padding(padding: const EdgeInsets.all(16.0), child: _buildChart(context)),
          ),

          // Legend
          if (widget.showLegend) _buildLegend(context),
        ],
      ),
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

    // Calculate width based on number of groups and chart type
    final double itemWidth = _currentChartType == ChartType.bar ? 80.0 : 60.0; // Bar charts need more space
    const double minWidth = 300.0; // Minimum chart width
    final double calculatedWidth = (widget.data.length * itemWidth).clamp(minWidth, double.infinity);

    Widget chart;
    switch (_currentChartType) {
      case ChartType.line:
        chart = _buildLineChart(context);
        break;
      case ChartType.bar:
        chart = _buildGroupedBarChart(context);
        break;
    }

    // Always wrap in horizontal scroll view for consistent behavior
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: calculatedWidth, child: chart),
    );
  }

  /// Builds a line chart
  Widget _buildLineChart(BuildContext context) {
    // Get all data points from grouped data
    final allDataPoints = widget.data.expand((group) => group.bars).toList();

    if (allDataPoints.isEmpty) {
      return const Center(child: Text('No data available for line chart'));
    }

    // Create multiple lines for different labels
    final lineBarsData = _buildMultipleLineChartBars(context);

    // For line charts, x-axis should range from 0 to number of groups - 1
    final minX = 0.0;
    final maxX = (widget.data.length - 1).toDouble();
    final maxY = allDataPoints.map((e) => e.y).reduce((a, b) => a > b ? a : b);

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
        lineBarsData: lineBarsData,
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: maxY * 1.1,
      ),
    );
  }

  /// Builds a bar chart
  /// Builds a grouped bar chart
  Widget _buildGroupedBarChart(BuildContext context) {
    if (widget.data.isEmpty) {
      return const Center(child: Text('No grouped data available'));
    }

    final barGroups = widget.data.asMap().entries.map((entry) {
      final groupIndex = entry.key;
      final group = entry.value;

      // Generate different colors for bars in the same group
      final defaultColors = [
        widget.primaryColor,
        widget.primaryColor.withOpacity(0.7),
        widget.primaryColor.withOpacity(0.5),
        widget.primaryColor.withOpacity(0.3),
      ];

      final barRods = group.bars.asMap().entries.map((barEntry) {
        final barIndex = barEntry.key;
        final bar = barEntry.value;

        return BarChartRodData(
          toY: bar.y,
          color: bar.color ?? defaultColors[barIndex % defaultColors.length],
          width: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: _getMaxYValue(),
            color: Colors.grey.withOpacity(0.1),
          ),
        );
      }).toList();

      return BarChartGroupData(
        x: groupIndex,
        barRods: barRods,
        barsSpace: 1, // Space between bars within a group
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        maxY: _getMaxYValue() * 1.1,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final groupData = widget.data[groupIndex];
              final barData = groupData.bars[rodIndex];
              return BarTooltipItem(
                '${barData.label ?? 'Value'}\n${barData.y.toStringAsFixed(1)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: _buildGroupedBarTitlesData(),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
        groupsSpace: 20, // Space between groups
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
        ),
      ),
    );
  }

  /// Gets the maximum Y value from grouped data
  double _getMaxYValue() {
    return widget.data.expand((group) => group.bars).map((bar) => bar.y).reduce((a, b) => a > b ? a : b);
  }

  /// Gets all data points from grouped data
  /// Builds multiple line chart bars for grouped data
  List<LineChartBarData> _buildMultipleLineChartBars(BuildContext context) {
    final Map<String, List<MapEntry<int, ChartDataPoint>>> dataByLabel = {};

    // Group all data points by their labels, keeping track of group indices
    for (int groupIndex = 0; groupIndex < widget.data.length; groupIndex++) {
      final group = widget.data[groupIndex];
      for (final bar in group.bars) {
        final label = bar.label ?? 'Unlabeled';
        dataByLabel.putIfAbsent(label, () => []).add(MapEntry(groupIndex, bar));
      }
    }

    // Generate different colors for different lines
    final defaultColors = [
      widget.primaryColor,
      widget.primaryColor.withOpacity(0.8),
      widget.primaryColor.withOpacity(0.6),
      widget.primaryColor.withOpacity(0.4),
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];

    return dataByLabel.entries.map((entry) {
      final label = entry.key;
      final pointsWithIndices = entry.value;
      final colorIndex = dataByLabel.keys.toList().indexOf(label);
      final color = pointsWithIndices.first.value.color ?? defaultColors[colorIndex % defaultColors.length];

      // Use group index as x-coordinate for proper alignment with x-axis labels
      final spots = pointsWithIndices.map((entry) => FlSpot(entry.key.toDouble(), entry.value.y)).toList();

      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 3,
        isStrokeCapRound: true,
        preventCurveOverShooting: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            return FlDotCirclePainter(radius: 4, color: color, strokeWidth: 2, strokeColor: Colors.white);
          },
        ),
        belowBarData: BarAreaData(show: false), // Don't fill area for multiple lines
      );
    }).toList();
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
          reservedSize: 60,
          interval: 1, // Show labels at every integer interval
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            // Only show labels for exact integer values that correspond to our data indices
            if (value == index.toDouble() && index >= 0 && index < widget.data.length) {
              final groupLabel = widget.data[index].groupLabel;
              return Transform.rotate(
                angle: -0.9, // Rotate by approximately 50 degrees (in radians)
                child: Text(
                  groupLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              );
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
            // Only show labels for reasonable intervals to avoid duplicates
            if (value % 1 == 0) {
              // Only show whole numbers
              final formatted = widget.yAxisFormatter?.call(value) ?? value.toStringAsFixed(0);
              return Text(formatted, style: const TextStyle(fontSize: 12, color: Colors.grey));
            }
            return const Text('');
          },
        ),
      ),
    );
  }

  /// Builds titles data for bar chart
  /// Builds titles data for grouped bar chart
  FlTitlesData _buildGroupedBarTitlesData() {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 60,
          interval: 1, // Show labels at every integer interval
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            // Only show labels for exact integer values that correspond to our data indices
            if (value == index.toDouble() && index >= 0 && index < widget.data.length) {
              final groupLabel = widget.data[index].groupLabel;
              return Transform.rotate(
                angle: -0.9, // Rotate by approximately 50 degrees (in radians)
                child: Text(
                  groupLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              );
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
            // Only show labels for reasonable intervals to avoid duplicates
            if (value % 1 == 0) {
              // Only show whole numbers
              final formatted = widget.yAxisFormatter?.call(value) ?? value.toStringAsFixed(0);
              return Text(formatted, style: const TextStyle(fontSize: 12, color: Colors.grey));
            }
            return const Text('');
          },
        ),
      ),
    );
  }

  /// Builds the legend for the chart with totals
  Widget _buildLegend(BuildContext context) {
    List<_LegendItem> legendItems = [];

    // Calculate totals by label/type for display in legend
    final Map<String, double> totalsByType = {};
    for (final group in widget.data) {
      for (final bar in group.bars) {
        final label = bar.label ?? 'Unlabeled';
        totalsByType[label] = (totalsByType[label] ?? 0) + bar.y;
      }
    }

    if (_currentChartType == ChartType.line) {
      // For line charts with grouped data, show legend for different lines (by label)
      final Map<String, Color> labelColorMap = {};
      final defaultColors = [
        widget.primaryColor,
        widget.primaryColor.withOpacity(0.8),
        widget.primaryColor.withOpacity(0.6),
        widget.primaryColor.withOpacity(0.4),
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.purple,
      ];

      // Group data points by their labels to create different lines
      final Map<String, List<ChartDataPoint>> dataByLabel = {};
      for (final group in widget.data) {
        for (final bar in group.bars) {
          final label = bar.label ?? 'Unlabeled';
          dataByLabel.putIfAbsent(label, () => []).add(bar);
        }
      }

      // Assign colors to each line
      dataByLabel.entries.toList().asMap().forEach((index, entry) {
        final label = entry.key;
        final points = entry.value;
        final color = points.first.color ?? defaultColors[index % defaultColors.length];
        labelColorMap[label] = color;
      });

      legendItems = labelColorMap.entries.map((entry) {
        final total = totalsByType[entry.key] ?? 0;
        final labelWithTotal = '${entry.key} (${total.toStringAsFixed(widget.totalDecimalPlaces)})';
        return _LegendItem(color: entry.value, label: labelWithTotal);
      }).toList();
    } else {
      // For bar charts with grouped data, show legend for bars within groups
      final defaultColors = [
        widget.primaryColor,
        widget.primaryColor.withOpacity(0.7),
        widget.primaryColor.withOpacity(0.5),
        widget.primaryColor.withOpacity(0.3),
      ];

      // Get unique bar labels from all groups
      final Set<String> uniqueLabels = {};
      final Map<String, Color> labelColorMap = {};

      for (final group in widget.data) {
        for (int i = 0; i < group.bars.length; i++) {
          final bar = group.bars[i];
          final label = bar.label ?? 'Bar ${i + 1}';
          uniqueLabels.add(label);

          // Assign color - use bar's color if available, otherwise use default colors
          if (!labelColorMap.containsKey(label)) {
            labelColorMap[label] = bar.color ?? defaultColors[i % defaultColors.length];
          }
        }
      }

      legendItems = uniqueLabels.map((label) {
        final total = totalsByType[label] ?? 0;
        final labelWithTotal = '$label (${total.toStringAsFixed(widget.totalDecimalPlaces)})';
        return _LegendItem(color: labelColorMap[label]!, label: labelWithTotal);
      }).toList();
    }

    // Only show legend if there are multiple items or if items have custom colors
    if (legendItems.isEmpty || (legendItems.length == 1 && legendItems.first.color == widget.primaryColor)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total title
          Text(
            'Total',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: widget.primaryColor),
          ),
          const SizedBox(height: 8),
          // Legend items with totals
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: legendItems
                .map(
                  (item) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(_currentChartType == ChartType.line ? 6 : 2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(item.label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
                    ],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// Internal class for legend items
class _LegendItem {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});
}
