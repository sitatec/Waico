import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

class HealthDashboard extends StatefulWidget {
  const HealthDashboard({super.key});

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  final Health _health = Health();
  bool _isLoading = true;
  bool _permissionsGranted = false;

  // Health data variables
  int _steps = 0;
  double _heartRate = 0.0;
  double _calories = 0.0;
  double _sleepHours = 0.0;
  double _waterIntake = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeHealth();
  }

  List<HealthDataType> get _healthDataTypes => [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.WATER,
  ];

  Future<void> _initializeHealth() async {
    try {
      // Configure health plugin
      await _health.configure();

      // Request activity recognition permission for Android
      await Permission.activityRecognition.request();

      // Request health permissions
      bool requested = await _health.requestAuthorization(_healthDataTypes);

      if (requested) {
        await _fetchHealthData();
        setState(() {
          _permissionsGranted = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _permissionsGranted = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _permissionsGranted = false;
        _isLoading = false;
      });
      debugPrint('Health initialization error: $e');
    }
  }

  Future<void> _fetchHealthData() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      // Fetch health data for today
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: _healthDataTypes,
        startTime: startOfDay,
        endTime: now,
      );

      // Process health data
      _processHealthData(healthData);

      // Get total steps for today
      int? steps = await _health.getTotalStepsInInterval(startOfDay, now);
      if (steps != null) {
        setState(() {
          _steps = steps;
        });
      }
    } catch (e) {
      debugPrint('Error fetching health data: $e');
    }
  }

  void _processHealthData(List<HealthDataPoint> healthData) {
    double heartRateSum = 0;
    int heartRateCount = 0;
    double caloriesSum = 0;
    double sleepSum = 0;
    double waterSum = 0;

    for (var point in healthData) {
      final value = point.value;
      if (value is NumericHealthValue) {
        switch (point.type) {
          case HealthDataType.HEART_RATE:
            heartRateSum += value.numericValue;
            heartRateCount++;
            break;
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            caloriesSum += value.numericValue;
            break;
          case HealthDataType.SLEEP_ASLEEP:
            sleepSum += value.numericValue;
            break;
          case HealthDataType.WATER:
            waterSum += value.numericValue;
            break;
          default:
            break;
        }
      }
    }

    setState(() {
      _heartRate = heartRateCount > 0 ? heartRateSum / heartRateCount : 0;
      _calories = caloriesSum;
      _sleepHours = sleepSum / 60; // Convert to hours
      _waterIntake = waterSum;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade400, Colors.purple.shade400],
          ),
        ),
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (!_permissionsGranted) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey.shade400, Colors.grey.shade600],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.health_and_safety, size: 48, color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              'Health permissions required',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enable health data access to see your wellness insights',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _initializeHealth, child: const Text('Grant Permissions')),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, theme.colorScheme.primary],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s Health Overview',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
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
                    _HealthMetricCard(
                      icon: Icons.directions_walk,
                      title: 'Steps',
                      value: _steps.toString(),
                      unit: '',
                      iconSize: 19,
                    ),
                    _HealthMetricCard(
                      icon: Icons.favorite,
                      title: 'Heart Rate',
                      value: _heartRate.toInt().toString(),
                      unit: 'BPM',
                      iconSize: 17,
                    ),
                    _HealthMetricCard(
                      icon: Icons.local_fire_department,
                      title: 'Calories',
                      value: _calories.toInt().toString(),
                      unit: 'CAL',
                      iconSize: 19,
                    ),
                    _HealthMetricCard(
                      icon: Icons.bedtime,
                      title: 'Sleep',
                      value: _sleepHours.toStringAsFixed(1),
                      unit: 'HOURS',
                    ),
                    _HealthMetricCard(
                      icon: Icons.water_drop,
                      title: 'Water',
                      value: _waterIntake.toStringAsFixed(1),
                      unit: 'LITERS',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthMetricCard extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String title;
  final String value;
  final String unit;

  const _HealthMetricCard({
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
              Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text(
                      value,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 27,
                      ),
                    ),
                  ),
                  Text(
                    unit,
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
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
