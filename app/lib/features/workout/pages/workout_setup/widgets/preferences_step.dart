import 'package:flutter/material.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/pages/workout_setup/widgets/setup_card.dart';

class PreferencesStep extends StatefulWidget {
  final WorkoutSetupData data;
  final ValueChanged<WorkoutSetupData> onDataChanged;

  const PreferencesStep({super.key, required this.data, required this.onDataChanged});

  @override
  State<PreferencesStep> createState() => _PreferencesStepState();
}

class _PreferencesStepState extends State<PreferencesStep> {
  final Map<int, String> _durationLabels = {15: '15 min', 30: '30 min', 45: '45 min', 60: '1 hour'};

  void _updateDuration(int duration) {
    widget.onDataChanged(widget.data.copyWith(workoutDurationPreference: duration));
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
            'Let\'s customize your experience',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'These preferences help us recommend workouts that fit your lifestyle.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          const SizedBox(height: 16),

          // Workout Duration Preference
          SetupCard(
            title: 'Workout Duration',
            icon: Icons.timer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How long would you prefer your workouts to be?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),

                Slider(
                  value: (widget.data.workoutDurationPreference).toDouble(),
                  min: 15,
                  max: 60,
                  divisions: 3,
                  onChanged: (value) => _updateDuration(value.round()),
                  activeColor: theme.colorScheme.primary,
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '15 min',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _durationLabels[widget.data.workoutDurationPreference]!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '1 hours',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Summary Card
          SetupCard(
            title: 'Setup Summary',
            icon: Icons.summarize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryItem(
                  'Physical Stats',
                  widget.data.weight != null && widget.data.height != null
                      ? '${widget.data.weight?.toStringAsFixed(1)} kg, ${widget.data.height?.toStringAsFixed(0)} cm'
                      : 'Not completed',
                  widget.data.weight != null && widget.data.height != null,
                  theme,
                ),
                _buildSummaryItem(
                  'Fitness Level',
                  widget.data.currentFitnessLevel ?? 'Not selected',
                  widget.data.currentFitnessLevel != null,
                  theme,
                ),
                _buildSummaryItem(
                  'Workout Frequency',
                  '${widget.data.selectedWeekDays.length}x per week: ${widget.data.selectedWeekDays.join(', ')}',
                  true,
                  theme,
                ),
                _buildSummaryItem(
                  'Primary Goal',
                  widget.data.primaryGoal ?? 'Not specified',
                  widget.data.primaryGoal != null,
                  theme,
                ),
                _buildSummaryItem(
                  'Preferred Duration',
                  _durationLabels[widget.data.workoutDurationPreference]!,
                  true,
                  theme,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, bool isComplete, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isComplete ? Colors.green : theme.colorScheme.outline,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isComplete ? Colors.black.withOpacity(0.75) : theme.colorScheme.outline,
                    fontWeight: isComplete ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
