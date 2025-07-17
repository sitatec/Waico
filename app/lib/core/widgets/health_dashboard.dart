import 'package:flutter/material.dart';
import 'package:waico/core/services/health_service.dart';

/// Health dashboard widget that displays wellness metrics
class HealthDashboard extends StatefulWidget {
  const HealthDashboard({super.key});

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  late final HealthService _healthService;

  @override
  void initState() {
    super.initState();
    _healthService = HealthService();
    _healthService.addListener(_onHealthServiceUpdate);
    _initializeHealthService();
  }

  @override
  void dispose() {
    _healthService.removeListener(_onHealthServiceUpdate);
    super.dispose();
  }

  void _onHealthServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeHealthService() async {
    await _healthService.initialize();
  }

  Future<void> _handleActionButton() async {
    switch (_healthService.status) {
      case HealthServiceStatus.healthConnectRequired:
        await _healthService.installHealthConnect();
        break;
      case HealthServiceStatus.permissionsRequired:
        await _healthService.requestPermissions();
        break;
      case HealthServiceStatus.ready:
        await _healthService.refreshData();
        break;
      default:
        await _healthService.initialize();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, theme.colorScheme.primary],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(child: _buildContent(theme)),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_healthService.status) {
      case HealthServiceStatus.loading || HealthServiceStatus.uninitialized:
        return const Center(child: CircularProgressIndicator(color: Colors.white));

      case HealthServiceStatus.healthConnectRequired:
        return _buildActionRequired(
          theme,
          icon: Icons.health_and_safety,
          title: 'Google Health Connect App required',
          description: 'Install the Health Connect App to see your wellness insights',
          buttonText: 'Install Health Connect',
        );

      case HealthServiceStatus.permissionsRequired:
        return _buildActionRequired(
          theme,
          icon: Icons.health_and_safety,
          title: 'Health permissions required',
          description: 'Enable health data access to see your wellness insights',
          buttonText: 'Grant Permissions',
        );

      case HealthServiceStatus.error:
        return _buildActionRequired(
          theme,
          icon: Icons.error_outline,
          title: 'Health service error',
          description: _healthService.errorMessage ?? 'An unknown error occurred',
          buttonText: 'Retry',
        );

      case HealthServiceStatus.ready:
        return _buildHealthMetrics(theme);
    }
  }

  Widget _buildActionRequired(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: Colors.white),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _handleActionButton, child: Text(buttonText)),
      ],
    );
  }

  Widget _buildHealthMetrics(ThemeData theme) {
    final metrics = _healthService.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Today\'s Health Overview',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            IconButton(
              onPressed: _handleActionButton,
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              tooltip: 'Refresh data',
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              shrinkWrap: true,
              children: [
                HealthMetricCard(
                  icon: Icons.directions_walk,
                  title: 'Steps',
                  value: metrics.steps.toString(),
                  unit: '',
                  iconSize: 19,
                ),
                HealthMetricCard(
                  icon: Icons.favorite,
                  title: 'Heart Rate',
                  value: metrics.heartRate.toInt().toString(),
                  unit: 'BPM',
                  iconSize: 17,
                ),
                HealthMetricCard(
                  icon: Icons.local_fire_department,
                  title: 'Calories',
                  value: metrics.calories.toInt().toString(),
                  unit: 'CAL',
                  iconSize: 19,
                ),
                HealthMetricCard(
                  icon: Icons.bedtime,
                  title: 'Sleep',
                  value: metrics.sleepHours.toStringAsFixed(1),
                  unit: 'HOURS',
                ),
                HealthMetricCard(
                  icon: Icons.water_drop,
                  title: 'Water',
                  value: metrics.waterIntake.toStringAsFixed(1),
                  unit: 'LITERS',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A widget that displays a single health metric
class HealthMetricCard extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String title;
  final String value;
  final String unit;

  const HealthMetricCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        alignment: AlignmentDirectional.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 5),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    unit,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.topStart,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ],
      ),
    );
  }
}
