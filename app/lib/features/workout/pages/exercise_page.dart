import 'dart:async';
import 'dart:ui';
import 'dart:developer' show log;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pose_detection/pose_detection_service.dart';
import 'package:waico/features/workout/pose_detection/workout_camera_widget.dart';
import 'package:waico/features/workout/workout_session_manager.dart';
import 'package:waico/features/workout/workout_coach_agent.dart';
import 'package:waico/generated/locale_keys.g.dart';

class ExercisePage extends StatefulWidget {
  final WorkoutSession session;
  final int workoutWeek;
  final int workoutSessionIndex;
  final int? startingExerciseIndex; // Optional starting exercise index

  const ExercisePage({
    super.key,
    required this.session,
    required this.workoutWeek,
    required this.workoutSessionIndex,
    this.startingExerciseIndex,
  });

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends State<ExercisePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  WorkoutSessionManager? _sessionManager;
  VoiceChatPipeline? _voiceChatPipeline;
  WorkoutCoachAgent? _workoutCoachAgent;
  PoseDetectionService? _poseDetectionService;

  bool _isInitialized = false;
  bool _isCameraPermissionGranted = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addObserver(this);
    _setupAnimations();
    _initializeWorkoutSession();
  }

  @override
  void dispose() {
    // Reset orientation
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    WidgetsBinding.instance.removeObserver(this);
    _workoutCoachAgent?.chatModel.dispose();
    _sessionManager?.dispose();
    _voiceChatPipeline?.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (_poseDetectionService?.isActive == true) {
          _poseDetectionService?.stop();
        }
        break;
      case AppLifecycleState.resumed:
        if (_isCameraPermissionGranted &&
            _isInitialized &&
            _sessionManager?.currentState.currentPhase == WorkoutPhaseType.exercising) {
          _poseDetectionService?.start().then((success) {
            if (!success && mounted) {
              log('Failed to restart pose detection service');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(LocaleKeys.common_unknown_error.tr()), backgroundColor: Colors.red),
              );
            }
          });
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _setupAnimations() {
    _fadeController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _initializeWorkoutSession() async {
    setState(() => _isInitialized = false);
    try {
      _workoutCoachAgent = WorkoutCoachAgent();
      await _workoutCoachAgent?.initialize();
      _voiceChatPipeline = VoiceChatPipeline(agent: _workoutCoachAgent!);
      _poseDetectionService = PoseDetectionService.instance;

      _sessionManager = WorkoutSessionManager(
        session: widget.session,
        voiceChatPipeline: _voiceChatPipeline!,
        workoutWeek: widget.workoutWeek,
        workoutSessionIndex: widget.workoutSessionIndex,
        poseDetectionService: _poseDetectionService,
      );

      _isCameraPermissionGranted = await _poseDetectionService?.hasCameraPermission ?? false;
      _poseDetectionService?.errorStream.listen((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
        }
      });

      await _sessionManager?.initialize();

      if (widget.startingExerciseIndex != null &&
          widget.startingExerciseIndex != _sessionManager?.currentState.currentExerciseIndex) {
        await _sessionManager?.goToExercise(widget.startingExerciseIndex!);
      }
      if (mounted) setState(() => _isInitialized = true);
    } catch (e, s) {
      log('Failed to initialize workout session', error: e, stackTrace: s);
      // If the user quickly navigates away, before the state is set to initialized,
      // we need to ensure we don't call setState on a disposed widget.
      if (!mounted) return;
      setState(() => _isInitialized = true); // Stop loading even on error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize workout session: $e'), backgroundColor: Colors.red),
        );
      });
    }
  }

  Future<void> _markExerciseComplete() async {
    await _sessionManager?.markCurrentExerciseAsComplete();
    if (_sessionManager?.currentState.currentPhase == WorkoutPhaseType.finished) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              const Text('Initializing workout session...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (_sessionManager == null) {
      return const Scaffold(
        body: Center(
          child: Text('Failed to initialize workout session', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      );
    }

    return StreamBuilder<WorkoutSessionState>(
      stream: _sessionManager!.stateStream,
      initialData: _sessionManager!.currentState,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final state = snapshot.data!;
        final showInstructions = state.currentPhase == WorkoutPhaseType.preExercise && state.currentSet == 1;

        return Scaffold(
          body: showInstructions
              ? SafeArea(
                  child: SingleChildScrollView(
                    child: InstructionsView(
                      state: state,
                      fadeAnimation: _fadeAnimation,
                      slideAnimation: _slideAnimation,
                      onStartExercise: () => _sessionManager!.startCurrentExercise(),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    WorkoutView(state: state),
                    if (state.currentPhase == WorkoutPhaseType.resting)
                      RestOverlay(state: state, onSkipRest: () => _sessionManager!.startCurrentExercise()),
                    if (state.currentPhase == WorkoutPhaseType.exercising)
                      _BackButton(onBackPressed: () => Navigator.pop(context)),
                    ControlOverlay(
                      state: state,
                      onGoToPrevious: () => _sessionManager!.goToPreviousExercise(),
                      onMarkComplete: _markExerciseComplete,
                      onGoToNext: () => _sessionManager!.goToNextExercise(),
                      onSwitchCamera: () => _sessionManager!.poseDetectionService.switchCamera(),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// --- Widget Classes ---

class InstructionsView extends StatelessWidget {
  final WorkoutSessionState state;
  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final VoidCallback onStartExercise;

  const InstructionsView({
    super.key,
    required this.state,
    required this.fadeAnimation,
    required this.slideAnimation,
    required this.onStartExercise,
  });

  @override
  Widget build(BuildContext context) {
    final exercise = state.currentExercise;
    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          'EXERCISE ${state.currentExerciseIndex + 1} OF ${state.totalExercises}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        InkWell(
                          onTap: context.navBack,
                          child: const Text(
                            'CLOSE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      exercise.name,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    exercise.image ?? 'assets/images/workout.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade100,
                      child: Icon(Icons.fitness_center, size: 60, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ),
                child: Text(
                  '${exercise.load.sets} sets × ${exercise.load.reps ?? exercise.load.duration ?? 'N/A'} ${exercise.load.type.name}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (exercise.instruction != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Instructions',
                        style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        exercise.instruction!,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    'No instructions available for this exercise.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.primary,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onStartExercise,
                    child: const Center(
                      child: Text(
                        'START EXERCISE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (state.restTimerValue != null && state.restTimerValue! > 0)
                Center(
                  child: Text('Auto-starting in ${state.restTimerValue}s...', style: TextStyle(color: Colors.orange)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutView extends StatelessWidget {
  final WorkoutSessionState state;
  const WorkoutView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return WorkoutCameraWidget(
      repsCounter: state.repsCounter,
      showRepCounter:
          state.currentExercise.load.type == ExerciseLoadType.reps && state.currentPhase == WorkoutPhaseType.exercising,
    );
  }
}

class RestOverlay extends StatelessWidget {
  final WorkoutSessionState state;
  final VoidCallback onSkipRest;
  const RestOverlay({super.key, required this.state, required this.onSkipRest});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black.withOpacity(0.6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'REST',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
              const SizedBox(height: 20),
              Text(
                '${state.restTimerValue ?? 0}',
                style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                'Next: Set ${state.currentSet} - ${state.currentExercise.name}',
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 40),
              TextButton(
                onPressed: onSkipRest,
                child: Text('SKIP REST', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onBackPressed;
  const _BackButton({required this.onBackPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 5,
      child: SafeArea(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.8), size: 18),
            onPressed: onBackPressed,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

class ControlOverlay extends StatelessWidget {
  final WorkoutSessionState state;
  final VoidCallback onGoToPrevious;
  final VoidCallback onMarkComplete;
  final VoidCallback onGoToNext;
  final VoidCallback onSwitchCamera;

  const ControlOverlay({
    super.key,
    required this.state,
    required this.onGoToPrevious,
    required this.onMarkComplete,
    required this.onGoToNext,
    required this.onSwitchCamera,
  });

  @override
  Widget build(BuildContext context) {
    final exercise = state.currentExercise;
    final orientation = MediaQuery.orientationOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: SizedBox(
          width: orientation == Orientation.portrait ? screenWidth : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      exercise.name,
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      ' - Set ${state.currentSet}/${exercise.load.sets}${exercise.load.type == ExerciseLoadType.duration ? ' | Time: ${state.exerciseTimerValue ?? exercise.load.duration}s' : ''}',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2)),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ControlButton(
                        icon: Icons.skip_previous,
                        onPressed: state.hasPreviousExercise ? onGoToPrevious : null,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      ControlButton(
                        icon: Icons.check_circle,
                        onPressed: onMarkComplete,
                        color: Colors.green,
                        isPrimary: true,
                      ),
                      ControlButton(
                        icon: Icons.skip_next,
                        onPressed: state.hasNextExercise ? onGoToNext : null,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const VerticalDivider(endIndent: 12, indent: 12, width: 1),
                      ControlButton(
                        icon: Icons.cameraswitch_outlined,
                        onPressed: onSwitchCamera,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool isPrimary;
  const ControlButton({super.key, required this.icon, this.onPressed, required this.color, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    return Container(
      width: isPrimary ? 48 : 36,
      height: isPrimary ? 48 : 36,
      decoration: BoxDecoration(
        color: isEnabled ? (isPrimary ? color : Colors.white) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(isPrimary ? 24 : 16),
        border: isPrimary
            ? null
            : Border.all(color: isEnabled ? color.withOpacity(0.3) : Colors.grey.shade300, width: 1),
        boxShadow: isEnabled && isPrimary
            ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
            : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(isPrimary ? 24 : 16),
          onTap: onPressed,
          child: Center(
            child: Icon(
              icon,
              color: isEnabled ? (isPrimary ? Colors.white : color) : Colors.grey.shade400,
              size: isPrimary ? 22 : 17,
            ),
          ),
        ),
      ),
    );
  }
}
