import 'package:flutter/material.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pages/exercise_page.dart';

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
        const SnackBar(content: Text('All exercises completed! Great job!'), backgroundColor: Colors.green),
      );
    }
  }

  void _navigateToExercise(int exerciseIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExerciseCameraPage(
          exercise: widget.session.exercises[exerciseIndex],
          exerciseIndex: exerciseIndex,
          sessionIndex: widget.sessionIndex,
          weekIndex: widget.weekIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.session.sessionName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text('${widget.session.estimatedDuration} min', style: const TextStyle(fontSize: 12)),
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            ),
          ),
        ],
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
                        Text(
                          widget.session.type.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.session.exercises.length} Exercises',
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
                    'Exercises',
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
              label: const Text(
                'START NEXT',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              'Progress',
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

  String _getLoadDescription() {
    if (exercise.load.type == ExerciseLoadType.reps) {
      return '${exercise.load.sets} sets × ${exercise.load.reps} reps';
    } else {
      final minutes = (exercise.load.duration! / 60).floor();
      final seconds = exercise.load.duration! % 60;
      final durationStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
      return '${exercise.load.sets} sets × $durationStr';
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
                        _getLoadDescription(),
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
