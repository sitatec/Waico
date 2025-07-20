import 'package:flutter/material.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/features/workout/models/workout_plan.dart';

/// A beautiful UI page for displaying the user's workout plan with weekly sections
/// and exercise completion tracking
class WorkoutPlanPage extends StatefulWidget {
  const WorkoutPlanPage({super.key});

  @override
  State<WorkoutPlanPage> createState() => _WorkoutPlanPageState();
}

class _WorkoutPlanPageState extends State<WorkoutPlanPage> {
  final UserRepository _userRepository = UserRepository();
  final PageController _pageController = PageController();

  WorkoutPlan? _workoutPlan;
  bool _isLoading = true;
  String? _errorMessage;

  int _currentWeek = 0;

  @override
  void initState() {
    super.initState();
    _loadWorkoutPlan();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkoutPlan() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final plan = await _userRepository.getWorkoutPlan();
      if (plan != null) {
        setState(() {
          _workoutPlan = plan;
          _isLoading = false;
          // Set current week to first incomplete week
          _currentWeek = _findCurrentWeek();
        });

        // Scroll to current week after a short delay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_currentWeek > 0) {
            _pageController.animateToPage(
              _currentWeek,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        });
      } else {
        setState(() {
          _errorMessage = 'No workout plan found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  int _findCurrentWeek() {
    if (_workoutPlan == null) return 0;

    // For now, just return the first week
    // In a real app, this would be based on user progress/dates
    return 0;
  }

  Future<void> _toggleExerciseCompletion(int week, int sessionIndex, int exerciseIndex) async {
    try {
      await _userRepository.toggleExerciseCompletion(week, sessionIndex, exerciseIndex);
      // Trigger a rebuild to update the UI
      setState(() {});
    } catch (e) {
      // Handle error - could show a snackbar
      debugPrint('Error toggling exercise completion: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _LoadingState();
    }

    if (_errorMessage != null) {
      return _ErrorState(errorMessage: _errorMessage!, onRetry: _loadWorkoutPlan);
    }

    if (_workoutPlan == null) {
      return const _NoPlanState();
    }

    return _WorkoutPlanContent(
      workoutPlan: _workoutPlan!,
      pageController: _pageController,
      currentWeek: _currentWeek,
      onWeekChanged: (week) => setState(() => _currentWeek = week),
      onExerciseToggle: _toggleExerciseCompletion,
      userRepository: _userRepository,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Workout Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 60, height: 60, child: CircularProgressIndicator(strokeWidth: 4)),
            SizedBox(height: 24),
            Text('Loading Your Workout Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Getting everything ready...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _ErrorState({required this.errorMessage, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Workout Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Try Again', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoPlanState extends StatelessWidget {
  const _NoPlanState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Workout Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fitness_center_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 24),
              Text('No Workout Plan Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              SizedBox(height: 16),
              Text(
                'It looks like you don\'t have a workout plan yet. Please generate one first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutPlanContent extends StatelessWidget {
  final WorkoutPlan workoutPlan;
  final PageController pageController;
  final int currentWeek;
  final Function(int) onWeekChanged;
  final Function(int, int, int) onExerciseToggle;
  final UserRepository userRepository;

  const _WorkoutPlanContent({
    required this.workoutPlan,
    required this.pageController,
    required this.currentWeek,
    required this.onWeekChanged,
    required this.onExerciseToggle,
    required this.userRepository,
  });

  Future<double> _getWeekProgress(int weekIndex) async {
    final week = workoutPlan.weeklyPlans[weekIndex];
    int totalExercises = 0;
    int completedExercises = 0;

    for (int sessionIndex = 0; sessionIndex < week.workoutSessions.length; sessionIndex++) {
      final session = week.workoutSessions[sessionIndex];
      totalExercises += session.exercises.length;

      for (int exerciseIndex = 0; exerciseIndex < session.exercises.length; exerciseIndex++) {
        if (await userRepository.isExerciseCompleted(week.week, sessionIndex, exerciseIndex)) {
          completedExercises++;
        }
      }
    }

    return totalExercises > 0 ? completedExercises / totalExercises : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          workoutPlan.planName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Plan Overview Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workoutPlan.description, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _InfoChip(icon: Icons.calendar_today, label: '${workoutPlan.totalWeeks} weeks'),
                      const SizedBox(width: 12),
                      _InfoChip(icon: Icons.fitness_center, label: '${workoutPlan.workoutsPerWeek}x/week'),
                      const SizedBox(width: 12),
                      _InfoChip(icon: Icons.trending_up, label: workoutPlan.difficulty),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Week Navigation
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: workoutPlan.weeklyPlans.length,
              itemBuilder: (context, index) {
                final isSelected = index == currentWeek;

                return FutureBuilder<double>(
                  future: _getWeekProgress(index),
                  builder: (context, snapshot) {
                    final progress = snapshot.data ?? 0.0;

                    return GestureDetector(
                      onTap: () {
                        onWeekChanged(index);
                        pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        width: 68,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Week',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.white : Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 40,
                              height: 4,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: isSelected ? Colors.white30 : Colors.grey.shade300,
                                valueColor: AlwaysStoppedAnimation<Color>(isSelected ? Colors.white : Colors.green),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Weekly Plans Content
          Expanded(
            child: PageView.builder(
              controller: pageController,
              onPageChanged: onWeekChanged,
              itemCount: workoutPlan.weeklyPlans.length,
              itemBuilder: (context, weekIndex) {
                final week = workoutPlan.weeklyPlans[weekIndex];
                return _WeeklyPlanView(
                  week: week,
                  weekIndex: weekIndex,
                  onExerciseToggle: onExerciseToggle,
                  userRepository: userRepository,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _WeeklyPlanView extends StatelessWidget {
  final WeeklyPlan week;
  final int weekIndex;
  final Function(int, int, int) onExerciseToggle;
  final UserRepository userRepository;

  const _WeeklyPlanView({
    required this.week,
    required this.weekIndex,
    required this.onExerciseToggle,
    required this.userRepository,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Week Focus
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Week ${week.week} Focus', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(week.focus, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Workout Sessions
          ...week.workoutSessions.asMap().entries.map((entry) {
            final sessionIndex = entry.key;
            final session = entry.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _WorkoutSessionCard(
                session: session,
                sessionIndex: sessionIndex,
                weekIndex: weekIndex,
                onExerciseToggle: onExerciseToggle,
                userRepository: userRepository,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WorkoutSessionCard extends StatelessWidget {
  final WorkoutSession session;
  final int sessionIndex;
  final int weekIndex;
  final Function(int, int, int) onExerciseToggle;
  final UserRepository userRepository;

  const _WorkoutSessionCard({
    required this.session,
    required this.sessionIndex,
    required this.weekIndex,
    required this.onExerciseToggle,
    required this.userRepository,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.fitness_center, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.sessionName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            session.type,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${session.estimatedDuration} min',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Exercises List
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: session.exercises.asMap().entries.map((entry) {
                final exerciseIndex = entry.key;
                final exercise = entry.value;

                return FutureBuilder<bool>(
                  future: userRepository.isExerciseCompleted(weekIndex, sessionIndex, exerciseIndex),
                  builder: (context, snapshot) {
                    final isCompleted = snapshot.data ?? false;

                    return _ExerciseItem(
                      exercise: exercise,
                      isCompleted: isCompleted,
                      onToggle: () => onExerciseToggle(weekIndex, sessionIndex, exerciseIndex),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseItem extends StatelessWidget {
  final Exercise exercise;
  final bool isCompleted;
  final VoidCallback onToggle;

  const _ExerciseItem({required this.exercise, required this.isCompleted, required this.onToggle});

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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.withOpacity(0.1) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCompleted ? Colors.green.withOpacity(0.3) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Completion Checkbox
          GestureDetector(
            onTap: onToggle,
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

          const SizedBox(width: 16),

          // Exercise Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    color: isCompleted ? Colors.grey.shade600 : null,
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
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: exercise.targetMuscles.map((muscle) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                        child: Text(muscle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      );
                    }).toList(),
                  ),
                ],
                if (exercise.restPeriod > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.timer, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Rest: ${exercise.restPeriod}s',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
