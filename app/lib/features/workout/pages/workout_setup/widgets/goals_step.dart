import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/pages/workout_setup/widgets/setup_card.dart';
import 'package:waico/features/workout/widgets/selection_chips.dart';
import 'package:waico/features/workout/widgets/custom_text_field.dart';
import 'package:waico/generated/locale_keys.g.dart';

class GoalsStep extends StatefulWidget {
  final WorkoutSetupData data;
  final ValueChanged<WorkoutSetupData> onDataChanged;

  const GoalsStep({super.key, required this.data, required this.onDataChanged});

  @override
  State<GoalsStep> createState() => _GoalsStepState();
}

class _GoalsStepState extends State<GoalsStep> {
  late TextEditingController _primaryGoalController;
  late TextEditingController _targetWeightController;

  final List<String> _primaryGoalSuggestions = [
    LocaleKeys.workout_setup_goals_lose_weight.tr(),
    LocaleKeys.workout_setup_goals_build_muscle.tr(),
    LocaleKeys.workout_setup_goals_improve_fitness.tr(),
    LocaleKeys.workout_setup_goals_increase_strength.tr(),
    LocaleKeys.workout_setup_goals_better_health.tr(),
    LocaleKeys.workout_setup_goals_train_for_event.tr(),
    LocaleKeys.workout_setup_goals_stay_active.tr(),
    LocaleKeys.workout_setup_goals_stress_relief.tr(),
  ];

  final List<String> _specificGoalOptions = [
    LocaleKeys.workout_setup_goals_lose_body_fat.tr(),
    LocaleKeys.workout_setup_goals_build_lean_muscle.tr(),
    LocaleKeys.workout_setup_goals_improve_cardiovascular.tr(),
    LocaleKeys.workout_setup_goals_increase_flexibility.tr(),
    LocaleKeys.workout_setup_goals_better_posture.tr(),
    LocaleKeys.workout_setup_goals_more_energy.tr(),
    LocaleKeys.workout_setup_goals_better_sleep.tr(),
    LocaleKeys.workout_setup_goals_reduce_stress.tr(),
    LocaleKeys.workout_setup_goals_improve_mood.tr(),
    LocaleKeys.workout_setup_goals_build_confidence.tr(),
    LocaleKeys.workout_setup_goals_train_for_marathon.tr(),
    LocaleKeys.workout_setup_goals_prepare_for_competition.tr(),
  ];

  @override
  void initState() {
    super.initState();
    _primaryGoalController = TextEditingController(text: widget.data.primaryGoal ?? '');
    _targetWeightController = TextEditingController(text: widget.data.targetWeight ?? '');
  }

  @override
  void dispose() {
    _primaryGoalController.dispose();
    _targetWeightController.dispose();
    super.dispose();
  }

  void _updatePrimaryGoal(String goal) {
    widget.onDataChanged(widget.data.copyWith(primaryGoal: goal));
  }

  void _updateTargetWeight(String weight) {
    widget.onDataChanged(widget.data.copyWith(targetWeight: weight));
  }

  void _updateSpecificGoals(dynamic goals) {
    widget.onDataChanged(widget.data.copyWith(specificGoals: goals as List<String>));
  }

  void _onGoalSuggestionTapped(String suggestion) {
    _primaryGoalController.text = suggestion;
    _updatePrimaryGoal(suggestion);
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
            LocaleKeys.workout_setup_goals_title.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            LocaleKeys.workout_setup_goals_description.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          // Primary Goal
          SetupCard(
            title: LocaleKeys.workout_setup_goals_primary_goal.tr(),
            icon: Icons.track_changes,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SuggestionChips(
                  suggestions: _primaryGoalSuggestions,
                  onSuggestionTapped: _onGoalSuggestionTapped,
                  title: LocaleKeys.workout_setup_goals_popular_goals.tr(),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _primaryGoalController,
                  label: LocaleKeys.workout_setup_goals_main_fitness_goal.tr(),
                  hint: LocaleKeys.workout_setup_goals_main_fitness_goal_hint.tr(),
                  onChanged: _updatePrimaryGoal,
                  maxLines: 2,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Target Weight (if relevant)
          if (widget.data.primaryGoal != null &&
              (widget.data.primaryGoal!.toLowerCase().contains('weight') ||
                  widget.data.primaryGoal!.toLowerCase().contains('lose') ||
                  widget.data.primaryGoal!.toLowerCase().contains('muscle')))
            Column(
              children: [
                SetupCard(
                  title: LocaleKeys.workout_setup_goals_target_weight.tr(),
                  icon: Icons.monitor_weight,
                  child: Column(
                    children: [
                      CustomTextField(
                        controller: _targetWeightController,
                        label: LocaleKeys.workout_setup_goals_target_weight_optional.tr(),
                        suffix: LocaleKeys.common_unit_kg.tr(),
                        hint: LocaleKeys.workout_setup_goals_target_weight_hint.tr(),
                        keyboardType: TextInputType.number,
                        onChanged: _updateTargetWeight,
                      ),
                      if (widget.data.weight != null && widget.data.targetWeight != null)
                        Padding(padding: const EdgeInsets.only(top: 12), child: _buildWeightDifferenceInfo(theme)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),

          // Specific Goals
          SetupCard(
            title: LocaleKeys.workout_setup_goals_additional_goals.tr(),
            icon: Icons.checklist,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.workout_setup_goals_additional_goals_description.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SelectionChips(
                  options: _specificGoalOptions,
                  selectedOption: widget.data.specificGoals,
                  onSelectionChanged: _updateSpecificGoals,
                  multiSelect: true,
                  scrollable: true,
                ),

                if (widget.data.specificGoals.isNotEmpty) ...[
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
                        Icon(Icons.flag, color: theme.colorScheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            LocaleKeys.workout_setup_goals_goals_selected.tr(
                              namedArgs: {
                                'count': widget.data.specificGoals.length.toString(),
                                'plural': widget.data.specificGoals.length == 1 ? '' : 's',
                              },
                            ),
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

  Widget _buildWeightDifferenceInfo(ThemeData theme) {
    final currentWeight = widget.data.weight!;
    final targetWeight = double.tryParse(widget.data.targetWeight!);

    if (targetWeight == null) return const SizedBox.shrink();

    final difference = targetWeight - currentWeight;
    final isLoss = difference < 0;
    final absChange = difference.abs();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isLoss ? Icons.trending_down : Icons.trending_up, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLoss
                  ? LocaleKeys.workout_setup_goals_goal_lose.tr(namedArgs: {'weight': absChange.toStringAsFixed(1)})
                  : LocaleKeys.workout_setup_goals_goal_gain.tr(namedArgs: {'weight': absChange.toStringAsFixed(1)}),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
