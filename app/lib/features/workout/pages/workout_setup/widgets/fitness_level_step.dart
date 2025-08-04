import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/pages/workout_setup/widgets/setup_card.dart';
import 'package:waico/features/workout/widgets/selection_chips.dart';
import 'package:waico/generated/locale_keys.g.dart';

class FitnessLevelStep extends StatefulWidget {
  final WorkoutSetupData data;
  final ValueChanged<WorkoutSetupData> onDataChanged;

  const FitnessLevelStep({super.key, required this.data, required this.onDataChanged});

  @override
  State<FitnessLevelStep> createState() => _FitnessLevelStepState();
}

class _FitnessLevelStepState extends State<FitnessLevelStep> {
  final List<String> _fitnessLevels = [
    LocaleKeys.workout_setup_fitness_level_beginner.tr(),
    LocaleKeys.workout_setup_fitness_level_intermediate.tr(),
    LocaleKeys.workout_setup_fitness_level_advanced.tr(),
    LocaleKeys.workout_setup_fitness_level_expert.tr(),
  ];

  final List<String> _experienceLevels = [
    LocaleKeys.workout_setup_fitness_level_never_exercised.tr(),
    LocaleKeys.workout_setup_fitness_level_exercise_occasionally.tr(),
    LocaleKeys.workout_setup_fitness_level_exercise_1_2_years.tr(),
    LocaleKeys.workout_setup_fitness_level_exercise_3_plus_years.tr(),
    LocaleKeys.workout_setup_fitness_level_professional_athlete.tr(),
  ];

  final List<String> _weekDays = [
    LocaleKeys.workout_setup_fitness_level_monday.tr(),
    LocaleKeys.workout_setup_fitness_level_tuesday.tr(),
    LocaleKeys.workout_setup_fitness_level_wednesday.tr(),
    LocaleKeys.workout_setup_fitness_level_thursday.tr(),
    LocaleKeys.workout_setup_fitness_level_friday.tr(),
    LocaleKeys.workout_setup_fitness_level_saturday.tr(),
    LocaleKeys.workout_setup_fitness_level_sunday.tr(),
  ];

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

    final neverExercised = LocaleKeys.workout_setup_fitness_level_never_exercised.tr();
    final exerciseOccasionally = LocaleKeys.workout_setup_fitness_level_exercise_occasionally.tr();
    final exercise1to2Years = LocaleKeys.workout_setup_fitness_level_exercise_1_2_years.tr();
    final exercise3PlusYears = LocaleKeys.workout_setup_fitness_level_exercise_3_plus_years.tr();

    if ((experience == neverExercised || experience == exerciseOccasionally) && selectedDays >= 4) {
      return LocaleKeys.workout_setup_fitness_level_warning_beginner_overtraining.tr();
    } else if (experience == exercise1to2Years && selectedDays >= 5) {
      return LocaleKeys.workout_setup_fitness_level_warning_intermediate_recovery.tr();
    } else if (experience == exercise3PlusYears && selectedDays == 7) {
      return LocaleKeys.workout_setup_fitness_level_warning_advanced_daily.tr();
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
            LocaleKeys.workout_setup_fitness_level_title.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            LocaleKeys.workout_setup_fitness_level_description.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          // Current Fitness Level
          SetupCard(
            title: LocaleKeys.workout_setup_fitness_level_current_fitness_level.tr(),
            icon: Icons.fitness_center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.workout_setup_fitness_level_current_fitness_question.tr(),
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
            title: LocaleKeys.workout_setup_fitness_level_exercise_experience.tr(),
            icon: Icons.history,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.workout_setup_fitness_level_exercise_background_question.tr(),
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
            title: LocaleKeys.workout_setup_fitness_level_workout_days.tr(),
            icon: Icons.calendar_today,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.workout_setup_fitness_level_workout_days_question.tr(),
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
                            LocaleKeys.workout_setup_fitness_level_days_selected.tr(
                              namedArgs: {
                                'count': _selectedWeekDays.length.toString(),
                                'plural': _selectedWeekDays.length == 1 ? '' : 's',
                              },
                            ),
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
