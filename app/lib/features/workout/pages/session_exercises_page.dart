import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pages/exercise_page.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// Page that displays exercises for a specific workout session
class SessionExercisesPage extends StatefulWidget {
  final WorkoutSession session;
  final int sessionIndex;
  final int weekIndex;

  const SessionExercisesPage({super.key, required this.session, required this.sessionIndex, required this.weekIndex});

  @override
  State<SessionExercisesPage> createState() => _SessionExercisesPageState();
}

class _SessionExercisesPageState extends State<SessionExercisesPage> {
  final UserRepository _userRepository = UserRepository();
  List<bool> _exerciseCompletionStatus = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExerciseStatus();
  }

  Future<void> _loadExerciseStatus() async {
    setState(() {
      _isLoading = true;
    });

    final status = <bool>[];
    for (int i = 0; i < widget.session.exercises.length; i++) {
      final isCompleted = await _userRepository.isExerciseCompleted(widget.weekIndex, widget.sessionIndex, i);
      status.add(isCompleted);
    }

    setState(() {
      _exerciseCompletionStatus = status;
      _isLoading = false;
    });
  }

  Future<void> _toggleExerciseCompletion(int exerciseIndex) async {
    await _userRepository.toggleExerciseCompletion(widget.weekIndex, widget.sessionIndex, exerciseIndex);
    await _loadExerciseStatus();
  }

  void _startNextIncompleteExercise() {
    final nextIncompleteIndex = _exerciseCompletionStatus.indexWhere((completed) => !completed);

    if (nextIncompleteIndex != -1) {
      _navigateToExercise(nextIncompleteIndex);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleKeys.workout_plan_all_exercises_completed.tr()), backgroundColor: Colors.green),
      );
    }
  }

  void _navigateToExercise(int exerciseIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExercisePage(
          session: widget.session,
          workoutWeek: widget.weekIndex,
          workoutSessionIndex: widget.sessionIndex,
          startingExerciseIndex: exerciseIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        titleSpacing: 8,
        title: Text(widget.session.sessionName, style: const TextStyle(fontSize: 20)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Session info card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.session.type.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              LocaleKeys.workout_setup_estimated_duration.tr(
                                namedArgs: {'duration': widget.session.estimatedDuration.toString()},
                              ),
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          LocaleKeys.workout_session_exercise_count.tr(
                            namedArgs: {'count': widget.session.exercises.length.toString()},
                          ),
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildProgressBar(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Exercises list
                  Text(
                    LocaleKeys.workout_session_exercises_title.tr(),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 16),

                  ...widget.session.exercises.asMap().entries.map((entry) {
                    final exerciseIndex = entry.key;
                    final exercise = entry.value;
                    final isCompleted = _exerciseCompletionStatus.isNotEmpty
                        ? _exerciseCompletionStatus[exerciseIndex]
                        : false;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ExerciseCard(
                        exercise: exercise,
                        exerciseIndex: exerciseIndex,
                        isCompleted: isCompleted,
                        onTap: () => _navigateToExercise(exerciseIndex),
                        onToggleCompletion: () => _toggleExerciseCompletion(exerciseIndex),
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 100), // Space for FAB
                ],
              ),
            ),
      floatingActionButton: !_isLoading && _exerciseCompletionStatus.any((completed) => !completed)
          ? FloatingActionButton.extended(
              onPressed: _startNextIncompleteExercise,
              backgroundColor: Theme.of(context).colorScheme.primary,
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              label: Text(
                LocaleKeys.workout_session_start_next_button.tr(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  Widget _buildProgressBar() {
    if (_exerciseCompletionStatus.isEmpty) {
      return const SizedBox.shrink();
    }

    final completedCount = _exerciseCompletionStatus.where((completed) => completed).length;
    final totalCount = _exerciseCompletionStatus.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              LocaleKeys.workout_session_progress_label.tr(),
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              '$completedCount / $totalCount',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white.withOpacity(0.3),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          minHeight: 6,
        ),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final int exerciseIndex;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback onToggleCompletion;

  const _ExerciseCard({
    required this.exercise,
    required this.exerciseIndex,
    required this.isCompleted,
    required this.onTap,
    required this.onToggleCompletion,
  });

  String _getLoadDescription(BuildContext context) {
    if (exercise.load.type == ExerciseLoadType.reps) {
      return LocaleKeys.workout_exercise_sets_x_reps.tr(
        namedArgs: {'sets': exercise.load.sets.toString(), 'reps': exercise.load.reps.toString()},
      );
    } else {
      final minutes = (exercise.load.duration! / 60).floor();
      final seconds = exercise.load.duration! % 60;
      final durationStr = minutes > 0
          ? LocaleKeys.workout_exercise_duration_m_s.tr(
              namedArgs: {'minutes': minutes.toString(), 'seconds': seconds.toString()},
            )
          : LocaleKeys.workout_exercise_duration_s.tr(namedArgs: {'seconds': seconds.toString()});
      return LocaleKeys.workout_exercise_sets_x_duration.tr(
        namedArgs: {'sets': exercise.load.sets.toString(), 'duration': durationStr},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isCompleted ? Border.all(color: Colors.green.withOpacity(0.3), width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Exercise number
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCompleted ? Colors.green : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : Text(
                            '${exerciseIndex + 1}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 16),

                // Exercise details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isCompleted ? Colors.grey.shade600 : Colors.grey.shade800,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getLoadDescription(context),
                        style: TextStyle(
                          color: isCompleted ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (exercise.targetMuscles.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: exercise.targetMuscles.take(3).map((muscle) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(muscle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Completion toggle
                GestureDetector(
                  onTap: onToggleCompletion,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green : Colors.transparent,
                      border: Border.all(color: isCompleted ? Colors.green : Colors.grey.shade400, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isCompleted ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
