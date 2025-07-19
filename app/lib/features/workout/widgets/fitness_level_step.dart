import 'package:flutter/material.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/widgets/setup_card.dart';
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

  final List<String> _workoutTypes = [
    'Cardio',
    'Strength Training',
    'HIIT',
    'Yoga',
    'Pilates',
    'CrossFit',
    'Running',
    'Swimming',
    'Cycling',
    'Dancing',
    'Martial Arts',
    'Rock Climbing',
  ];

  final Map<int, String> _frequencyLabels = {
    1: '1x per week',
    2: '2x per week',
    3: '3x per week',
    4: '4x per week',
    5: '5x per week',
    6: '6x per week',
    7: 'Daily',
  };

  void _updateFitnessLevel(dynamic level) {
    widget.onDataChanged(widget.data.copyWith(currentFitnessLevel: level as String?));
  }

  void _updateExperienceLevel(dynamic level) {
    widget.onDataChanged(widget.data.copyWith(experienceLevel: level as String?));
  }

  void _updateFrequency(int frequency) {
    widget.onDataChanged(widget.data.copyWith(weeklyWorkoutFrequency: frequency));
  }

  void _updateWorkoutTypes(dynamic types) {
    widget.onDataChanged(widget.data.copyWith(preferredWorkoutTypes: types as List<String>));
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

          // Workout Frequency
          SetupCard(
            title: 'Workout Frequency',
            icon: Icons.calendar_today,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How often would you like to work out?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),

                Slider(
                  value: widget.data.weeklyWorkoutFrequency.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  onChanged: (value) => _updateFrequency(value.round()),
                  activeColor: theme.colorScheme.primary,
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '1x/week',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _frequencyLabels[widget.data.weeklyWorkoutFrequency]!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Daily',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Preferred Workout Types
          SetupCard(
            title: 'Preferred Workout Types',
            icon: Icons.sports_gymnastics,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What types of workouts do you enjoy? (Select multiple)',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SelectionChips(
                  options: _workoutTypes,
                  selectedOption: widget.data.preferredWorkoutTypes,
                  onSelectionChanged: _updateWorkoutTypes,
                  multiSelect: true,
                  scrollable: true,
                ),

                if (widget.data.preferredWorkoutTypes.isNotEmpty) ...[
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
                            '${widget.data.preferredWorkoutTypes.length} workout type${widget.data.preferredWorkoutTypes.length == 1 ? '' : 's'} selected',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
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
