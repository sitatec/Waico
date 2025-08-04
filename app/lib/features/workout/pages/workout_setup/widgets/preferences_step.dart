import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/pages/workout_setup/widgets/setup_card.dart';
import 'package:waico/generated/locale_keys.g.dart';

class PreferencesStep extends StatefulWidget {
  final WorkoutSetupData data;
  final ValueChanged<WorkoutSetupData> onDataChanged;

  const PreferencesStep({super.key, required this.data, required this.onDataChanged});

  @override
  State<PreferencesStep> createState() => _PreferencesStepState();
}

class _PreferencesStepState extends State<PreferencesStep> {
  Map<int, String> get _durationLabels => {
    15: LocaleKeys.workout_setup_preferences_15_min.tr(),
    30: LocaleKeys.common_duration_30_min.tr(),
    45: LocaleKeys.common_duration_45_min.tr(),
    60: LocaleKeys.common_duration_1_hour.tr(),
  };

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
            LocaleKeys.workout_setup_preferences_title.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            LocaleKeys.workout_setup_preferences_description.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          const SizedBox(height: 16),

          // Workout Duration Preference
          SetupCard(
            title: LocaleKeys.workout_setup_preferences_workout_duration.tr(),
            icon: Icons.timer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.workout_setup_preferences_workout_duration_question.tr(),
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
                      LocaleKeys.workout_setup_preferences_15_min.tr(),
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
                      LocaleKeys.workout_setup_preferences_1_hours.tr(),
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
            title: LocaleKeys.workout_setup_preferences_setup_summary.tr(),
            icon: Icons.summarize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryItem(
                  LocaleKeys.workout_setup_preferences_physical_stats.tr(),
                  widget.data.weight != null && widget.data.height != null
                      ? LocaleKeys.workout_setup_preferences_weight_height_format.tr(
                          namedArgs: {
                            'weight': widget.data.weight!.toStringAsFixed(1),
                            'height': widget.data.height!.toStringAsFixed(0),
                          },
                        )
                      : LocaleKeys.workout_setup_preferences_not_completed.tr(),
                  widget.data.weight != null && widget.data.height != null,
                  theme,
                ),
                _buildSummaryItem(
                  LocaleKeys.workout_setup_preferences_fitness_level.tr(),
                  widget.data.currentFitnessLevel ?? LocaleKeys.workout_setup_preferences_not_selected.tr(),
                  widget.data.currentFitnessLevel != null,
                  theme,
                ),
                _buildSummaryItem(
                  LocaleKeys.workout_setup_preferences_workout_frequency.tr(),
                  LocaleKeys.workout_setup_preferences_frequency_per_week.tr(
                    namedArgs: {
                      'count': widget.data.selectedWeekDays.length.toString(),
                      'days': widget.data.selectedWeekDays.join(', '),
                    },
                  ),
                  true,
                  theme,
                ),
                _buildSummaryItem(
                  LocaleKeys.workout_setup_preferences_primary_goal.tr(),
                  widget.data.primaryGoal ?? LocaleKeys.workout_setup_preferences_not_specified.tr(),
                  widget.data.primaryGoal != null,
                  theme,
                ),
                _buildSummaryItem(
                  LocaleKeys.workout_setup_preferences_preferred_duration.tr(),
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
