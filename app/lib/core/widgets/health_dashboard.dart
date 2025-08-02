import 'dart:developer';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:waico/core/services/health_service.dart';
import 'package:waico/core/utils/number_utils.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// Health dashboard widget that displays wellness metrics
class HealthDashboard extends StatefulWidget {
  final VoidCallback? onReady;
  const HealthDashboard({super.key, this.onReady});

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
    _healthService
        .initialize()
        .then((_) {
          widget.onReady?.call();
        })
        .catchError((error) {
          log('HealthService initialization failed: $error');
          // The onReady callback is not an indicator of success state, just a signal that the widget is ready.
          // This can be used to to indicate to other widgets that require permission that they can now check permissions
          // since you can't simultaneously request many permissions at once.
          widget.onReady?.call();
        });
  }

  @override
  void dispose() {
    _healthService.removeListener(_onHealthServiceUpdate);
    super.dispose();
  }

  void _onHealthServiceUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {});
    });
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
      decoration: BoxDecoration(color: theme.colorScheme.primary),
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
          title: LocaleKeys.health_health_connect_title.tr(),
          description: LocaleKeys.health_health_connect_required.tr(),
          buttonText: LocaleKeys.health_install_health_connect.tr(),
        );

      case HealthServiceStatus.permissionsRequired:
        return _buildActionRequired(
          theme,
          icon: Icons.health_and_safety,
          title: LocaleKeys.health_permissions_title.tr(),
          description: LocaleKeys.health_permissions_required.tr(),
          buttonText: LocaleKeys.health_grant_permissions.tr(),
        );

      case HealthServiceStatus.error:
        return _buildActionRequired(
          theme,
          icon: Icons.error_outline,
          title: LocaleKeys.health_service_error.tr(),
          description: _healthService.errorMessage ?? LocaleKeys.common_unknown_error.tr(),
          buttonText: LocaleKeys.common_retry.tr(),
        );

      case HealthServiceStatus.ready:
        return _buildDashboard(theme);
    }
  }

  Widget _buildDashboard(ThemeData theme) {
    final metrics = _healthService.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              LocaleKeys.health_dashboard_title.tr(),
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: LocaleKeys.health_refresh_tooltip.tr(),
              onPressed: _handleActionButton,
            ),
          ],
        ),
        // const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              children: [
                HealthMetricCard(
                  icon: Icons.directions_walk,
                  title: LocaleKeys.health_steps.tr(),
                  value: metrics.steps.toString(),
                  unit: '',
                  iconSize: 15,
                ),
                HealthMetricCard(
                  icon: Icons.favorite,
                  title: LocaleKeys.health_heart_rate.tr(),
                  value: metrics.heartRate.toInt().toString(),
                  unit: LocaleKeys.health_bpm.tr(),
                  iconSize: 14,
                ),
                HealthMetricCard(
                  icon: Icons.local_fire_department,
                  title: LocaleKeys.health_active_energy.tr(),
                  value: metrics.calories.toInt().toString(),
                  unit: LocaleKeys.health_kcal.tr(),
                  iconSize: 16,
                ),
                HealthMetricCard(
                  icon: Icons.bedtime,
                  title: LocaleKeys.health_sleep.tr(),
                  value: metrics.sleepHours.toStringWithoutZeroDecimal(numDecimals: 1),
                  unit: LocaleKeys.health_hours.tr(),
                  iconSize: 15,
                ),
                HealthMetricCard(
                  icon: Icons.water_drop,
                  title: LocaleKeys.health_water.tr(),
                  value: metrics.waterIntake.toStringWithoutZeroDecimal(numDecimals: 1),
                  unit: LocaleKeys.health_liters.tr(),
                  iconSize: 15,
                ),
                HealthMetricCard(
                  icon: Icons.monitor_weight,
                  title: LocaleKeys.health_weight.tr(),
                  value: metrics.weight?.toStringWithoutZeroDecimal(numDecimals: 1) ?? '-',
                  unit: LocaleKeys.health_kg.tr(),
                  iconSize: 15.5,
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontSize: 12)),
              const SizedBox(height: 4),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
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
