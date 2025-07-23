import 'package:flutter/material.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/pages/workout_setup/widgets/setup_card.dart';
import 'package:waico/features/workout/widgets/selection_chips.dart';
import 'package:waico/features/workout/widgets/custom_text_field.dart';

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
    'Lose weight',
    'Build muscle',
    'Improve fitness',
    'Increase strength',
    'Better health',
    'Train for event',
    'Stay active',
    'Stress relief',
  ];

  final List<String> _specificGoalOptions = [
    'Lose body fat',
    'Build lean muscle',
    'Improve cardiovascular health',
    'Increase flexibility',
    'Better posture',
    'More energy',
    'Better sleep',
    'Reduce stress',
    'Improve mood',
    'Build confidence',
    'Train for marathon',
    'Prepare for competition',
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
            'What are your fitness goals?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Setting clear goals helps us create a plan that motivates and guides you.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          // Primary Goal
          SetupCard(
            title: 'Primary Goal',
            icon: Icons.track_changes,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SuggestionChips(
                  suggestions: _primaryGoalSuggestions,
                  onSuggestionTapped: _onGoalSuggestionTapped,
                  title: 'Popular goals',
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _primaryGoalController,
                  label: 'Your main fitness goal',
                  hint: 'What do you want to achieve?',
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
                  title: 'Target Weight',
                  icon: Icons.monitor_weight,
                  child: Column(
                    children: [
                      CustomTextField(
                        controller: _targetWeightController,
                        label: 'Target weight (optional)',
                        suffix: 'kg',
                        hint: 'Enter your target weight',
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
            title: 'Additional Goals',
            icon: Icons.checklist,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What else would you like to improve? (Optional)',
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
                            '${widget.data.specificGoals.length} additional goal${widget.data.specificGoals.length == 1 ? '' : 's'} selected',
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
                  ? 'Goal: Lose ${absChange.toStringAsFixed(1)} kg'
                  : 'Goal: Gain ${absChange.toStringAsFixed(1)} kg',
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
