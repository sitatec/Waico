import 'package:flutter/material.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/features/workout/models/workout_status.dart';
import 'package:waico/features/workout/pages/workout_plan_generation_page.dart';
import 'package:waico/features/workout/pages/workout_plan_page.dart';
import 'package:waico/features/workout/pages/workout_setup/workout_setup_page.dart';

/// Router page that determines which workout page to show based on user's current state
class WorkoutRouterPage extends StatefulWidget {
  const WorkoutRouterPage({super.key});

  @override
  State<WorkoutRouterPage> createState() => _WorkoutRouterPageState();
}

class _WorkoutRouterPageState extends State<WorkoutRouterPage> {
  final UserRepository _userRepository = UserRepository();

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _determineWorkoutState();
  }

  Future<void> _determineWorkoutState() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });

      final workoutStatus = await _userRepository.getWorkoutStatus();

      if (mounted) {
        switch (workoutStatus) {
          case WorkoutStatus.noSetup:
            // User hasn't completed setup, go to setup page
            context.navigateTo(const WorkoutSetupPage(), replaceCurrent: true);
            break;
          case WorkoutStatus.setupCompleteNoPlan:
            // User has setup but no plan, go to generation page
            context.navigateTo(const WorkoutPlanGenerationPage(), replaceCurrent: true);
            break;
          case WorkoutStatus.planReady:
            // User has a plan, go to workout view
            context.navigateTo(const WorkoutPlanPage(), replaceCurrent: true);
            break;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _LoadingState();
    } else if (_hasError) {
      return _ErrorState(
        errorMessage: _errorMessage ?? 'An unexpected error occurred',
        onRetry: _determineWorkoutState,
      );
    } else {
      // This should not happen as we navigate away in all success cases
      return const _LoadingState();
    }
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading Workout',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Checking your workout status...',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
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
          'Workout',
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
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
