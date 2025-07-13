import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

/// Health metrics data model
class HealthMetrics {
  final int steps;
  final double heartRate;
  final double calories;
  final double sleepHours;
  final double waterIntake;
  final DateTime lastUpdated;

  const HealthMetrics({
    required this.steps,
    required this.heartRate,
    required this.calories,
    required this.sleepHours,
    required this.waterIntake,
    required this.lastUpdated,
  });

  HealthMetrics copyWith({
    int? steps,
    double? heartRate,
    double? calories,
    double? sleepHours,
    double? waterIntake,
    DateTime? lastUpdated,
  }) {
    return HealthMetrics(
      steps: steps ?? this.steps,
      heartRate: heartRate ?? this.heartRate,
      calories: calories ?? this.calories,
      sleepHours: sleepHours ?? this.sleepHours,
      waterIntake: waterIntake ?? this.waterIntake,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Health service status
enum HealthServiceStatus { loading, permissionsRequired, healthConnectRequired, ready, error }

/// A service that provides a simple and intuitive API for health data
class HealthService extends ChangeNotifier {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();

  HealthServiceStatus _status = HealthServiceStatus.loading;
  HealthMetrics _metrics = HealthMetrics(
    steps: 0,
    heartRate: 0.0,
    calories: 0.0,
    sleepHours: 0.0,
    waterIntake: 0.0,
    lastUpdated: DateTime.now(),
  );
  String? _errorMessage;

  /// Current health service status
  HealthServiceStatus get status => _status;

  /// Current health metrics
  HealthMetrics get metrics => _metrics;

  /// Error message if status is error
  String? get errorMessage => _errorMessage;

  /// Whether the service is ready to provide data
  bool get isReady => _status == HealthServiceStatus.ready;

  /// Health data types that this service manages
  static const List<HealthDataType> _healthDataTypes = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.WATER,
    HealthDataType.WEIGHT, // TODO: show in the dashboard
  ];

  /// Initialize the health service
  Future<void> initialize() async {
    try {
      _updateStatus(HealthServiceStatus.loading);

      // Configure health plugin
      await _health.configure();

      // Check if Health Connect is available
      if (!await _health.isHealthConnectAvailable()) {
        _updateStatus(HealthServiceStatus.healthConnectRequired);
        return;
      }

      // Request activity recognition permission for Android
      await Permission.activityRecognition.request();

      // Request health permissions
      bool authorized = await _health.requestAuthorization(_healthDataTypes);

      if (authorized) {
        await refreshData();
        _updateStatus(HealthServiceStatus.ready);
      } else {
        _updateStatus(HealthServiceStatus.permissionsRequired);
      }
    } catch (e) {
      _setError('Failed to initialize health service: $e');
      debugPrint('Health service initialization error: $e');
    }
  }

  /// Install Health Connect (Android only)
  Future<void> installHealthConnect() async {
    try {
      await _health.installHealthConnect();
      // After installation, re-initialize
      await initialize();
    } catch (e) {
      _setError('Failed to install Health Connect: $e');
      debugPrint('Health Connect installation error: $e');
    }
  }

  /// Request permissions again
  Future<void> requestPermissions() async {
    await initialize();
  }

  /// Refresh health data from the current day
  Future<void> refreshData() async {
    if (_status == HealthServiceStatus.loading) return;

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      // Get total steps for today
      int? steps = await _health.getTotalStepsInInterval(startOfDay, now);

      // Fetch other health data for today
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: _healthDataTypes,
        startTime: startOfDay,
        endTime: now,
      );

      // Process the health data
      final processedMetrics = _processHealthData(healthData, steps ?? 0);

      _metrics = processedMetrics.copyWith(lastUpdated: DateTime.now());
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh health data: $e');
      debugPrint('Error refreshing health data: $e');
    }
  }

  /// Get health data for a specific date range
  Future<List<HealthDataPoint>> getHealthDataForRange({
    required DateTime startTime,
    required DateTime endTime,
    List<HealthDataType>? types,
  }) async {
    try {
      return await _health.getHealthDataFromTypes(
        types: types ?? _healthDataTypes,
        startTime: startTime,
        endTime: endTime,
      );
    } catch (e) {
      debugPrint('Error fetching health data for range: $e');
      return [];
    }
  }

  /// Get steps for a specific date range
  Future<int> getStepsForRange({required DateTime startTime, required DateTime endTime}) async {
    try {
      final steps = await _health.getTotalStepsInInterval(startTime, endTime);
      return steps ?? 0;
    } catch (e) {
      debugPrint('Error fetching steps for range: $e');
      return 0;
    }
  }

  /// Write health data
  Future<bool> writeHealthData({
    required HealthDataType type,
    required num value,
    required DateTime startTime,
    DateTime? endTime,
    String? unit,
  }) async {
    try {
      return await _health.writeHealthData(
        value: value.toDouble(),
        type: type,
        startTime: startTime,
        endTime: endTime ?? startTime,
        unit: unit != null
            ? HealthDataUnit.values.firstWhere(
                (u) => u.name.toLowerCase() == unit.toLowerCase(),
                orElse: () => HealthDataUnit.NO_UNIT,
              )
            : HealthDataUnit.NO_UNIT,
      );
    } catch (e) {
      debugPrint('Error writing health data: $e');
      return false;
    }
  }

  /// Process raw health data into metrics
  HealthMetrics _processHealthData(List<HealthDataPoint> healthData, int steps) {
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

    return HealthMetrics(
      steps: steps,
      heartRate: heartRateCount > 0 ? heartRateSum / heartRateCount : 0,
      calories: caloriesSum,
      sleepHours: sleepSum / 60, // Convert minutes to hours
      waterIntake: waterSum,
      lastUpdated: DateTime.now(),
    );
  }

  void _updateStatus(HealthServiceStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _setError(String error) {
    _status = HealthServiceStatus.error;
    _errorMessage = error;
    notifyListeners();
  }
}
