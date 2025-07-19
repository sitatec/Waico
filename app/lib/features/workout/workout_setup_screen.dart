import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:waico/core/services/health_service.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/widgets/physical_stats_step.dart';
import 'package:waico/features/workout/widgets/fitness_level_step.dart';
import 'package:waico/features/workout/widgets/goals_step.dart';
import 'package:waico/features/workout/widgets/preferences_step.dart';
import 'package:waico/features/workout/widgets/setup_progress_indicator.dart';

class WorkoutSetupScreen extends StatefulWidget {
  const WorkoutSetupScreen({super.key});

  @override
  State<WorkoutSetupScreen> createState() => _WorkoutSetupScreenState();
}

class _WorkoutSetupScreenState extends State<WorkoutSetupScreen> {
  final PageController _pageController = PageController();
  final HealthService _healthService = HealthService();

  int _currentStep = 0;
  WorkoutSetupData _setupData = const WorkoutSetupData();
  bool _isLoading = false;

  final List<String> _stepTitles = ['Physical Stats', 'Fitness Level', 'Your Goals', 'Preferences'];

  @override
  void initState() {
    super.initState();
    _initializeHealthData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initializeHealthData() async {
    if (!_healthService.isReady) {
      await _healthService.initialize();
    }

    if (_healthService.isReady) {
      await _healthService.refreshData();
      final metrics = _healthService.metrics;

      setState(() {
        _setupData = _setupData.copyWith(weight: metrics.weight > 0 ? metrics.weight : null);
      });
    }
  }

  void _updateSetupData(WorkoutSetupData newData) {
    setState(() {
      _setupData = newData;
    });
  }

  Future<void> _nextStep() async {
    if (_currentStep < _stepTitles.length - 1) {
      setState(() {
        _currentStep++;
      });
      await _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      await _finishSetup();
    }
  }

  Future<void> _previousStep() async {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      await _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _finishSetup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Write health data if available
      final now = DateTime.now();

      if (_setupData.weight != null && _healthService.isReady) {
        await _healthService.writeHealthData(type: HealthDataType.WEIGHT, value: _setupData.weight!, startTime: now);
      }

      if (_setupData.height != null && _healthService.isReady) {
        await _healthService.writeHealthData(
          type: HealthDataType.HEIGHT,
          value: _setupData.height! / 100, // Convert cm to meters
          startTime: now,
        );
      }

      // Here you would typically save the setup data to your app's storage/database
      // For now, we'll just show a success message

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save workout setup: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Setup Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            const Text('Your workout profile has been created successfully!', textAlign: TextAlign.center),
            if (_setupData.bmi != null) ...[
              const SizedBox(height: 16),
              Text(
                'Your BMI: ${_setupData.bmi!.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.navBack();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _setupData.weight != null &&
            _setupData.height != null &&
            _setupData.age != null &&
            _setupData.gender != null;
      case 1:
        return _setupData.currentFitnessLevel != null && _setupData.experienceLevel != null;
      case 2:
        return _setupData.primaryGoal != null;
      case 3:
        return true; // Preferences are optional
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Workout Setup',
          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Progress indicator
              Container(
                padding: const EdgeInsets.all(16),
                child: SetupProgressIndicator(
                  currentStep: _currentStep,
                  totalSteps: _stepTitles.length,
                  stepTitles: _stepTitles,
                ),
              ),

              // Page content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    PhysicalStatsStep(data: _setupData, onDataChanged: _updateSetupData),
                    FitnessLevelStep(data: _setupData, onDataChanged: _updateSetupData),
                    GoalsStep(data: _setupData, onDataChanged: _updateSetupData),
                    PreferencesStep(data: _setupData, onDataChanged: _updateSetupData),
                  ],
                ),
              ),

              // Navigation buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2)),
                  ],
                ),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _previousStep,
                          style: OutlinedButton.styleFrom(side: BorderSide(color: theme.colorScheme.primary)),
                          child: Text('Previous', style: TextStyle(color: theme.colorScheme.primary)),
                        ),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 16),
                    Expanded(
                      flex: _currentStep == 0 ? 1 : 1,
                      child: ElevatedButton(
                        onPressed: _canProceed() ? _nextStep : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                        child: Text(
                          _currentStep == _stepTitles.length - 1 ? 'Finish' : 'Next',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
