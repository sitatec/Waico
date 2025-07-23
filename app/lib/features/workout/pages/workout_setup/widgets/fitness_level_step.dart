import 'package:flutter/material.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/pages/workout_setup/widgets/setup_card.dart';
import 'package:waico/features/workout/widgets/selection_chips.dart';

class FitnessLevelStep extends StatefulWidget {
  final WorkoutSetupData data;
  final ValueChanged<WorkoutSetupData> onDataChanged;

  const FitnessLevelStep({super.key, required this.data, required this.onDataChanged});

  @override
  State<FitnessLevelStep> createState() => _FitnessLevelStepState();
}

class _FitnessLevelStepState extends State<FitnessLevelStep> {
  final List<String> _fitnessLevels = ['Beginner', 'Intermediate', 'Advanced', 'Expert'];

  final List<String> _experienceLevels = [
    'Never exercised regularly',
    'Exercise occasionally',
    'Exercise regularly (1-2 years)',
    'Exercise regularly (3+ years)',
    'Professional athlete',
  ];

  final List<String> _weekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  List<String> get _selectedWeekDays => widget.data.selectedWeekDays;

  void _updateFitnessLevel(dynamic level) {
    widget.onDataChanged(widget.data.copyWith(currentFitnessLevel: level as String?));
  }

  void _updateExperienceLevel(dynamic level) {
    widget.onDataChanged(widget.data.copyWith(experienceLevel: level as String?));
  }

  void _updateSelectedWeekDays(dynamic days) {
    widget.onDataChanged(widget.data.copyWith(selectedWeekDays: days as List<String>));
  }

  String _getWarningMessage() {
    final selectedDays = _selectedWeekDays.length;
    final experience = widget.data.experienceLevel;

    if (selectedDays <= 2) return '';

    if ((experience == 'Never exercised regularly' || experience == 'Exercise occasionally') && selectedDays >= 4) {
      return 'For your selected experience, we recommend starting with 2-3 days per week to avoid overtraining.';
    } else if (experience == 'Exercise regularly (1-2 years)' && selectedDays >= 5) {
      return 'Make sure to include enough rest days for recovery.';
    } else if (experience == 'Exercise regularly (3+ years)' && selectedDays == 7) {
      return 'Daily workouts require careful planning. Make sure to vary intensity and include recovery activities.';
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about your fitness level',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'This helps us recommend the right intensity and type of workouts.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          // Current Fitness Level
          SetupCard(
            title: 'Current Fitness Level',
            icon: Icons.fitness_center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How would you rate your current fitness?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SelectionChips(
                  options: _fitnessLevels,
                  selectedOption: widget.data.currentFitnessLevel,
                  onSelectionChanged: _updateFitnessLevel,
                  multiSelect: false,
                  scrollable: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Experience Level
          SetupCard(
            title: 'Exercise Experience',
            icon: Icons.history,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What\'s your exercise background?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SelectionChips(
                  options: _experienceLevels,
                  selectedOption: widget.data.experienceLevel,
                  onSelectionChanged: _updateExperienceLevel,
                  multiSelect: false,
                  scrollable: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Workout Days
          SetupCard(
            title: 'Workout Days',
            icon: Icons.calendar_today,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which days would you like to work out?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SelectionChips(
                  options: _weekDays,
                  selectedOption: _selectedWeekDays,
                  onSelectionChanged: _updateSelectedWeekDays,
                  multiSelect: true,
                  scrollable: false,
                ),

                if (_selectedWeekDays.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_selectedWeekDays.length} day${_selectedWeekDays.length == 1 ? '' : 's'} selected',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Warning message
                if (_getWarningMessage().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getWarningMessage(),
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
