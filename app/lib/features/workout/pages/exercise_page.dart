import 'dart:async';
import 'dart:developer' show log;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  StreamSubscription<int>? _exerciseIndexSubscription;
  PoseDetectionService? _poseDetectionService;

  bool _isInitialized = false;
  bool _isExerciseStarted = false;
  bool _showInstructions = true;
  bool _isLoading = false;
  int _currentExerciseIndex = 0;
  bool _isCameraPermissionGranted = false;

  // Animation controllers for modern UI
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAnimations();
    _initializeWorkoutSession();
  }

  @override
  void dispose() {
    // TODO: add conversation processing for workout sessions as well
    WidgetsBinding.instance.removeObserver(this);
    _workoutCoachAgent?.chatModel.dispose();
    _exerciseIndexSubscription?.cancel();
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
        // Stop pose detection when app becomes inactive/paused
        if (_poseDetectionService?.isActive == true) {
          _poseDetectionService?.stop();
        }

      case AppLifecycleState.resumed:
        // Restart pose detection when app is resumed
        if (_isCameraPermissionGranted && _isInitialized) {
          _poseDetectionService?.start().then((success) {
            if (!success) {
              log('Failed to restart pose detection service');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(LocaleKeys.common_unknown_error.tr()), backgroundColor: Colors.red),
                );
              }
            }
          });
        }
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App state changes, but no action needed
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
    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize the workout coach agent
      _workoutCoachAgent = WorkoutCoachAgent();
      await _workoutCoachAgent!.initialize();

      // Initialize the voice chat pipeline
      _voiceChatPipeline = VoiceChatPipeline(agent: _workoutCoachAgent!);

      _poseDetectionService = PoseDetectionService.instance;
      // Initialize the session manager
      _sessionManager = WorkoutSessionManager(
        session: widget.session,
        voiceChatPipeline: _voiceChatPipeline!,
        workoutWeek: widget.workoutWeek,
        workoutSessionIndex: widget.workoutSessionIndex,
        poseDetectionService: _poseDetectionService,
      );
      _isCameraPermissionGranted = await _poseDetectionService!.hasCameraPermission;
      _poseDetectionService?.errorStream.listen((error) {
        log('Pose detection error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
        }
      });
      await _sessionManager!.initialize();

      // Listen to exercise index changes
      _exerciseIndexSubscription = _sessionManager!.exerciseIndexStream.listen((index) {
        setState(() {
          _currentExerciseIndex = index;
          _showInstructions = !_isExerciseStarted;
        });
      });

      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _currentExerciseIndex = _sessionManager!.currentExerciseIndex;
      });

      // Navigate to starting exercise if specified
      if (widget.startingExerciseIndex != null &&
          widget.startingExerciseIndex != _sessionManager!.currentExerciseIndex) {
        await _sessionManager!.goToExercise(widget.startingExerciseIndex!);
      }
    } catch (e, s) {
      log('Failed to initialize workout session', error: e, stackTrace: s);
      setState(() {
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize workout session: $e'), backgroundColor: Colors.red),
        );
      });
    }
  }

  Future<void> _startExercise() async {
    if (_sessionManager == null) return;

    setState(() {
      _isExerciseStarted = true;
      _showInstructions = false;
    });

    await _sessionManager!.startCurrentExercise();
  }

  Future<void> _goToNextExercise() async {
    if (_sessionManager?.hasNextExercise == true) {
      setState(() {
        _isExerciseStarted = false;
        _showInstructions = true;
      });
      await _sessionManager!.goToNextExercise();
    }
  }

  Future<void> _goToPreviousExercise() async {
    if (_sessionManager?.hasPreviousExercise == true) {
      setState(() {
        _isExerciseStarted = false;
        _showInstructions = true;
      });
      await _sessionManager!.goToPreviousExercise();
    }
  }

  Future<void> _markExerciseComplete() async {
    await _sessionManager?.markCurrentExerciseAsComplete();

    // If this was the last exercise, navigate back
    if (_sessionManager?.hasNextExercise == false) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              Text('Initializing workout session...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _sessionManager == null) {
      return Scaffold(
        body: Center(
          child: Text('Failed to initialize workout session', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      );
    }

    final currentExercise = _sessionManager!.currentExercise;

    return Scaffold(
      body: SafeArea(
        child: _showInstructions && !_isExerciseStarted
            ? SingleChildScrollView(
                child: InstructionsView(
                  exercise: currentExercise,
                  fadeAnimation: _fadeAnimation,
                  slideAnimation: _slideAnimation,
                  currentExerciseIndex: _currentExerciseIndex,
                  totalExercises: _sessionManager!.totalExercises,
                  onStartExercise: _startExercise,
                ),
              )
            : Stack(
                children: [
                  // Main workout view
                  WorkoutView(
                    sessionManager: _sessionManager,
                    onPermissionDenied: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(LocaleKeys.workout_errors_camera_permission_required.tr()),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                  ),

                  // Control overlay
                  ControlOverlay(
                    showInstructions: _showInstructions,
                    sessionManager: _sessionManager,
                    currentExerciseIndex: _currentExerciseIndex,
                    onGoToPrevious: _goToPreviousExercise,
                    onMarkComplete: _markExerciseComplete,
                    onGoToNext: _goToNextExercise,
                    onBackPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
      ),
    );
  }
}

// Widget classes for better separation of concerns

class InstructionsView extends StatelessWidget {
  final Exercise exercise;
  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final int currentExerciseIndex;
  final int totalExercises;
  final VoidCallback onStartExercise;

  const InstructionsView({
    super.key,
    required this.exercise,
    required this.fadeAnimation,
    required this.slideAnimation,
    required this.currentExerciseIndex,
    required this.totalExercises,
    required this.onStartExercise,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress info card (similar to session_exercises_page)
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
                          'EXERCISE ${currentExerciseIndex + 1} OF $totalExercises',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),

                        InkWell(
                          onTap: context.navBack,
                          child: Text(
                            'CLOSE',
                            style: const TextStyle(
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

              // Exercise image card
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
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade100,
                        child: Icon(Icons.fitness_center, size: 60, color: Theme.of(context).colorScheme.primary),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Exercise load info
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

              // Instructions card
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
                      Text(
                        'Instructions',
                        style: TextStyle(color: Colors.grey.shade800, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.blue.withOpacity(0.1),
                            ),
                            child: Text(
                              exercise.optimalView == 'front'
                                  ? 'Face the camera for this exercise.'
                                  : 'Turn sideways to the camera for this exercise.',
                              style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        exercise.instruction!.length > 120
                            ? '${exercise.instruction!.substring(0, 120)}...'
                            : exercise.instruction!,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
                      ),
                      if (exercise.instruction!.length > 120)
                        TextButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: Colors.white,
                                title: Text(exercise.name, style: TextStyle(color: Colors.grey.shade800)),
                                content: Text(exercise.instruction!, style: TextStyle(color: Colors.grey.shade600)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      'Close',
                                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Text('Read more', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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

              // Start button
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
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutView extends StatelessWidget {
  final WorkoutSessionManager? sessionManager;
  final VoidCallback onPermissionDenied;

  const WorkoutView({super.key, required this.sessionManager, required this.onPermissionDenied});

  @override
  Widget build(BuildContext context) {
    return WorkoutCameraWidget(
      repsCounter: sessionManager?.repsCounter,
      showRepCounter: sessionManager?.repsCounter != null,
    );
  }
}

class ControlOverlay extends StatelessWidget {
  final bool showInstructions;
  final WorkoutSessionManager? sessionManager;
  final int currentExerciseIndex;
  final VoidCallback? onGoToPrevious;
  final VoidCallback onMarkComplete;
  final VoidCallback? onGoToNext;
  final VoidCallback onBackPressed;

  const ControlOverlay({
    super.key,
    required this.showInstructions,
    required this.sessionManager,
    required this.currentExerciseIndex,
    required this.onGoToPrevious,
    required this.onMarkComplete,
    required this.onGoToNext,
    required this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (showInstructions) return Container();

    return Stack(
      children: [
        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Back button
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.grey.shade900, size: 18),
                      onPressed: onBackPressed,
                    ),
                  ),

                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Text(
                          sessionManager?.currentExercise.name ?? '',
                          style: TextStyle(color: Colors.grey.shade900, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                ],
              ),
            ),
          ),
        ),

        // Bottom control buttons
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
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
                    // Previous exercise button
                    ControlButton(
                      icon: Icons.skip_previous,
                      onPressed: sessionManager?.hasPreviousExercise == true ? onGoToPrevious : null,
                      color: Theme.of(context).colorScheme.primary,
                    ),

                    // Complete exercise button
                    ControlButton(
                      icon: Icons.check_circle,
                      onPressed: onMarkComplete,
                      color: Colors.green,
                      isPrimary: true,
                    ),

                    // Next exercise button
                    ControlButton(
                      icon: Icons.skip_next,
                      onPressed: sessionManager?.hasNextExercise == true ? onGoToNext : null,
                      color: Theme.of(context).colorScheme.primary,
                    ),

                    const VerticalDivider(endIndent: 12, indent: 12, width: 1),
                    ControlButton(
                      icon: Icons.cameraswitch_outlined,
                      onPressed: () => sessionManager?.poseDetectionService.switchCamera(),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool isPrimary;

  const ControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.color,
    this.isPrimary = false,
  });

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
