import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pages/workout_plan_page.dart';
import 'package:waico/features/workout/workout_plan_generator.dart';
import 'package:waico/features/workout/pages/workout_setup/workout_setup_page.dart';
import 'package:waico/generated/locale_keys.g.dart';

class WorkoutPlanGenerationPage extends StatefulWidget {
  const WorkoutPlanGenerationPage({super.key});

  @override
  State<WorkoutPlanGenerationPage> createState() => _WorkoutPlanGenerationPageState();
}

class _WorkoutPlanGenerationPageState extends State<WorkoutPlanGenerationPage> {
  final UserRepository _userRepository = UserRepository();

  bool _isGenerating = false;
  bool _hasError = false;
  String? _errorMessage;
  WorkoutSetupData? _setupData;
  WorkoutPlan? _generatedPlan;

  // Progress tracking
  Map<String, List<WorkoutSession>> _parsedProgress = {};
  String _rawTextProgress = '';
  bool _showUIProgress = true; // Toggle between UI and raw text progress

  @override
  void initState() {
    super.initState();
    _loadSetupData();
  }

  Future<void> _loadSetupData() async {
    try {
      final setupData = await _userRepository.getWorkoutSetupData();
      if (setupData != null) {
        setState(() {
          _setupData = setupData;
        });
      } else {
        // No setup data found, redirect to setup
        if (mounted) {
          context.navigateTo(const WorkoutSetupPage(), replaceCurrent: true);
        }
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = LocaleKeys.workout_errors_failed_load_setup_data.tr(namedArgs: {'error': e.toString()});
      });
    }
  }

  Future<void> _generateWorkoutPlan() async {
    if (_setupData == null) return;

    setState(() {
      _isGenerating = true;
      _hasError = false;
      _errorMessage = null;
      _parsedProgress = {};
      _rawTextProgress = '';
    });

    try {
      final generator = WorkoutPlanGenerator();

      // Progress callback to update UI during generation
      void onProgress(WorkoutGenerationProgress progress) {
        setState(() {
          _parsedProgress = progress.parsedProgress;
          _rawTextProgress = progress.rawText;
        });
      }

      final workoutPlan = await generator.generate(_setupData!, progressCallback: onProgress);

      // Save the generated plan
      await _userRepository.saveWorkoutPlan(workoutPlan);

      setState(() {
        _generatedPlan = workoutPlan;
        _isGenerating = false;
      });

      // Show success message and navigate back
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _hasError = true;
        _errorMessage = LocaleKeys.workout_errors_failed_generate_plan.tr(namedArgs: {'error': e.toString()});
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(LocaleKeys.workout_plan_generated_title.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text(
              LocaleKeys.workout_plan_generated_message.tr(namedArgs: {'planName': _generatedPlan?.planName ?? ''}),
              textAlign: TextAlign.center,
            ),
            if (_generatedPlan != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      LocaleKeys.workout_plan_details.tr(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LocaleKeys.workout_plan_summary.tr(
                        namedArgs: {
                          'totalWeeks': _generatedPlan!.totalWeeks.toString(),
                          'workoutsPerWeek': _generatedPlan!.workoutsPerWeek.toString(),
                        },
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      LocaleKeys.workout_plan_difficulty.tr(namedArgs: {'difficulty': _generatedPlan!.difficulty}),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.navBack();
              context.navigateTo(const WorkoutPlanPage(), replaceCurrent: true);
            },
            child: Text(LocaleKeys.workout_setup_start_training.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header section
        Text(
          LocaleKeys.workout_generation_analyzing_profile.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),

        const SizedBox(height: 16),

        // Toggle Switch for progress view
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              LocaleKeys.workout_generation_ui_progress.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _showUIProgress
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: _showUIProgress ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: !_showUIProgress,
              onChanged: (value) {
                setState(() {
                  _showUIProgress = !value;
                });
              },
              activeColor: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              LocaleKeys.workout_generation_raw_text_progress.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: !_showUIProgress
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: !_showUIProgress ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Progress content
        Expanded(child: _showUIProgress ? _buildUIProgress() : _buildTextProgress()),

        const SizedBox(height: 32),

        // Tip section
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(Icons.tips_and_updates, color: Theme.of(context).colorScheme.primary, size: 22),
              const SizedBox(height: 8),
              Text(
                LocaleKeys.workout_generation_tip.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildIdleState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.fitness_center, size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 32),
        Text(
          LocaleKeys.workout_generation_ready_title.tr(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            LocaleKeys.workout_generation_ready_description.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        if (_setupData != null) ...[
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.workout_generation_your_profile.tr(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_setupData!.primaryGoal != null)
                  Text(LocaleKeys.workout_setup_goal_label.tr(namedArgs: {'goal': _setupData!.primaryGoal!})),
                if (_setupData!.currentFitnessLevel != null)
                  Text(
                    LocaleKeys.workout_setup_fitness_level_label.tr(
                      namedArgs: {'level': _setupData!.currentFitnessLevel!},
                    ),
                  ),
                Text(
                  LocaleKeys.workout_setup_frequency_label.tr(
                    namedArgs: {'frequency': _setupData!.selectedWeekDays.length.toString()},
                  ),
                ),
                Text(
                  LocaleKeys.workout_setup_duration_label.tr(
                    namedArgs: {'duration': _setupData!.workoutDurationPreference.toString()},
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _generateWorkoutPlan,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome, size: 20),
                const SizedBox(width: 8),
                Text(
                  LocaleKeys.workout_setup_generate_plan.tr(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.navigateTo(const WorkoutSetupPage(), replaceCurrent: true),
          child: Text(LocaleKeys.workout_setup_update_profile.tr()),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 80, color: Colors.red),
        const SizedBox(height: 32),
        Text(
          LocaleKeys.workout_generation_failed_title.tr(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.red),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            _errorMessage ?? LocaleKeys.workout_generation_default_error.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _generateWorkoutPlan,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              LocaleKeys.workout_buttons_retry.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.navigateTo(const WorkoutSetupPage(), replaceCurrent: true),
          child: Text(LocaleKeys.workout_setup_update_profile.tr()),
        ),
      ],
    );
  }

  Widget _buildUIProgress() {
    if (_parsedProgress.isEmpty) {
      return Center(
        child: Text(
          LocaleKeys.workout_generation_waiting_for_start.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.workout_generation_progress_overview.tr(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          ..._parsedProgress.entries.map((entry) {
            final weekName = entry.key;
            final sessions = entry.value;
            final isCompleted = sessions.isNotEmpty;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCompleted
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                    : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCompleted
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                      : Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: isCompleted
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        weekName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            LocaleKeys.workout_generation_session_count.plural(
                              sessions.length,
                              namedArgs: {'count': sessions.length.toString()},
                            ),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  ),
                  if (sessions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...sessions.map(
                      (session) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.fitness_center, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    session.sessionName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                if (session.estimatedDuration > 0)
                                  Text(
                                    LocaleKeys.workout_setup_estimated_duration.tr(
                                      namedArgs: {'duration': session.estimatedDuration.toString()},
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            if (session.exercises.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                LocaleKeys.workout_generation_exercises.tr(
                                  namedArgs: {'exercises': session.exercises.map((e) => e.name).join(', ')},
                                ),
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      LocaleKeys.workout_generation_generating_sessions.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTextProgress() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.text_snippet, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                LocaleKeys.workout_generation_raw_text_title.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _rawTextProgress.isEmpty ? LocaleKeys.workout_generation_waiting_for_start.tr() : _rawTextProgress,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          LocaleKeys.workout_generation_title.tr(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _isGenerating
            ? _buildLoadingState()
            : _hasError
            ? _buildErrorState()
            : _buildIdleState(),
      ),
    );
  }
}
