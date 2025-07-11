import 'package:flutter/material.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/pages/counselor_page.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = <Map<String, dynamic>>[
      {
        'title': 'Meditation',
        'color': const Color.fromARGB(98, 201, 94, 0),
        'image': {'url': 'assets/images/meditation.png', 'size': 80.0},
      },
      {
        'title': 'Sleep',
        'color': const Color.fromARGB(97, 0, 58, 192),
        'image': {'url': 'assets/images/sleep.png', 'size': 90.0},
      },
      {
        'title': 'Nutrition',
        'color': const Color.fromARGB(106, 0, 113, 73),
        'image': {'url': 'assets/images/nutrition.png', 'size': 70.0},
      },
      {
        'title': 'Workout',
        'color': const Color.fromARGB(92, 210, 154, 1),
        'image': {'url': 'assets/images/workout.png', 'size': 90.0},
      },
    ];
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            expandedHeight: MediaQuery.sizeOf(context).height * 0.34,
            flexibleSpace: FlexibleSpaceBar(
              expandedTitleScale: 1.2,
              background: ClipRRect(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                child: const _HealthDashboard(),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            sliver: SliverGrid.builder(
              itemCount: features.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.3,
              ),
              itemBuilder: (context, index) {
                final feature = features[index];
                return FeatureCard(
                  title: feature['title'] as String,
                  color: feature['color'] as Color,
                  image: feature['image']['url'] as String,
                  imageSize: feature['image']['size'],
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 1400)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Theme(
        data: theme.copyWith(
          floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
            backgroundColor: theme.colorScheme.primary,
            sizeConstraints: BoxConstraints(minWidth: 160, minHeight: 52),
          ),
        ),
        child: FloatingActionButton(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onPressed: () {
            context.navigateTo(CounselorPage());
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.voice_chat, color: theme.colorScheme.onPrimary),
              const SizedBox(width: 10),
              Text(
                "Counselor",
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onPrimary,
                ),
                textHeightBehavior: TextHeightBehavior(applyHeightToFirstAscent: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final String title;
  final Color color;
  final String image;
  final double imageSize;

  const FeatureCard({super.key, required this.title, required this.color, required this.image, this.imageSize = 90});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            child: Text(
              title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Image.asset(
              image,
              width: imageSize,
              height: imageSize,
              fit: BoxFit.contain,
              alignment: AlignmentDirectional.bottomEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthDashboard extends StatefulWidget {
  const _HealthDashboard();

  @override
  State<_HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<_HealthDashboard> {
  final Health _health = Health();
  bool _isLoading = true;
  bool _permissionsGranted = false;
  bool _healthConnectInstalled = false;

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

      if (!await _health.isHealthConnectAvailable()) {
        await _health.installHealthConnect();
      }

      // Request activity recognition permission for Android
      await Permission.activityRecognition.request();

      // Request health permissions
      bool authorized = await _health.requestAuthorization(_healthDataTypes);

      _healthConnectInstalled = await _health.isHealthConnectAvailable();

      if (authorized) {
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
      _healthConnectInstalled = await _health.isHealthConnectAvailable();
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
            colors: [Colors.blue.shade400, theme.colorScheme.primary],
          ),
        ),
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (!_permissionsGranted || !_healthConnectInstalled) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade400, theme.colorScheme.primary],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.health_and_safety, size: 48, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _healthConnectInstalled ? 'Health permissions required' : 'Google Health Connect App required',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _healthConnectInstalled
                  ? 'Enable health data access to see your wellness insights'
                  : 'Install the Health Connect App to see your wellness insights',
              style: TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeHealth,
              child: Text(_healthConnectInstalled ? 'Grant Permissions' : 'Install Health Connect'),
            ),
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
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
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
