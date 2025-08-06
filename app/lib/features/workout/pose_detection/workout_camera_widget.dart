import 'dart:async';
import 'dart:developer' show log;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// A high-performance camera widget with pose detection using native platform views
class WorkoutCameraWidget extends StatefulWidget {
  final RepsCounter? repsCounter;
  final bool showRepCounter;
  final int? exerciseTimerValue;
  final int? originalDuration;
  final bool showDurationTimer;

  const WorkoutCameraWidget({
    super.key,
    this.repsCounter,
    this.showRepCounter = true,
    this.exerciseTimerValue,
    this.originalDuration,
    this.showDurationTimer = false,
  });

  @override
  State<WorkoutCameraWidget> createState() => _WorkoutCameraWidgetState();
}

class _WorkoutCameraWidgetState extends State<WorkoutCameraWidget> with TickerProviderStateMixin {
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<RepCountingState>? _repCountingStateSubscription;
  StreamSubscription<RepetitionData>? _repDataSubscription;

  bool _isInitialized = false;
  String? _errorMessage;
  bool _hasPermission = false;

  // Rep counter state
  RepCountingState? _repCountingState;

  // Animations
  late AnimationController _repAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _repScaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkPermissionsAndStart();
  }

  void _initializeAnimations() {
    _repAnimationController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat();

    _repScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.22,
    ).animate(CurvedAnimation(parent: _repAnimationController, curve: Curves.elasticOut));
  }

  Future<void> _checkPermissionsAndStart() async {
    try {
      final hasPermission = await Permission.camera.request().isGranted;
      if (!hasPermission) {
        setState(() {
          _errorMessage = LocaleKeys.workout_errors_camera_permission_required.tr();
        });
        return;
      }

      setState(() {
        _hasPermission = true;
      });

      // Setup pose detection and rep counter
      _setupRepCounterStream();

      setState(() {
        _isInitialized = true;
      });
    } catch (e, s) {
      log('Error initializing camera.', error: e, stackTrace: s);
      setState(() {
        _errorMessage = LocaleKeys.workout_exercise_camera_initialization_failed.tr(namedArgs: {'error': e.toString()});
      });
    }
  }

  void _setupRepCounterStream() {
    if (widget.repsCounter != null) {
      _repCountingStateSubscription = widget.repsCounter!.stateStream.listen((state) {
        if (mounted) {
          setState(() {
            _repCountingState = state;
          });
        }
      });

      _repDataSubscription = widget.repsCounter!.repStream.listen((repData) {
        if (mounted) {
          // Trigger animation when a new rep is completed
          _repAnimationController.forward().then((_) {
            _repAnimationController.reverse();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _repAnimationController.dispose();
    _pulseController.dispose();
    _repCountingStateSubscription?.cancel();
    _repDataSubscription?.cancel();
    _errorSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Native camera preview platform view
          _NativeCameraPreview(hasPermission: _hasPermission, isInitialized: _isInitialized),
          if (widget.showRepCounter && widget.repsCounter != null && _isInitialized && _repCountingState != null)
            _RepCounterOverlay(repCountingState: _repCountingState!, repScaleAnimation: _repScaleAnimation),
          if (widget.showDurationTimer && widget.exerciseTimerValue != null && _isInitialized)
            _DurationTimerOverlay(timerValue: widget.exerciseTimerValue!, originalDuration: widget.originalDuration),
          if (_errorMessage != null)
            _ErrorOverlay(errorMessage: _errorMessage!, onDismiss: () => setState(() => _errorMessage = null)),
        ],
      ),
    );
  }
}

class _NativeCameraPreview extends StatelessWidget {
  final bool hasPermission;
  final bool isInitialized;

  const _NativeCameraPreview({required this.hasPermission, required this.isInitialized});

  @override
  Widget build(BuildContext context) {
    if (!hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              LocaleKeys.workout_errors_camera_permission_required.tr(),
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (!isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              LocaleKeys.workout_errors_initializing_camera.tr(),
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Use the platform view for camera preview
    return const AndroidView(
      viewType: 'ai.buinitylabs.waico/camera_preview',
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}

class _RepCounterOverlay extends StatelessWidget {
  final RepCountingState repCountingState;
  final Animation<double> repScaleAnimation;

  const _RepCounterOverlay({required this.repCountingState, required this.repScaleAnimation});

  @override
  Widget build(BuildContext context) {
    final lastQuality = repCountingState.lastRep?.formScore ?? 0.0;

    return Positioned(
      top: 8,
      right: 5,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RepCountDisplay(totalReps: repCountingState.totalReps, repScaleAnimation: repScaleAnimation),
              const SizedBox(height: 4),
              Text(
                LocaleKeys.workout_exercise_camera_reps_label.tr(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.8),
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              _QualityIndicator(quality: lastQuality),
              const SizedBox(height: 6),
              _PositionIndicator(state: repCountingState.currentState),
              if (repCountingState.lastRep != null) ...[
                const SizedBox(height: 6),
                _LastRepQualityIndicator(repData: repCountingState.lastRep!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RepCountDisplay extends StatelessWidget {
  final int totalReps;
  final Animation<double> repScaleAnimation;

  const _RepCountDisplay({required this.totalReps, required this.repScaleAnimation});

  Color _getRepCountColor() {
    if (totalReps == 0) return Colors.white;
    if (totalReps >= 20) return Colors.green;
    if (totalReps >= 10) return Colors.blue;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repScaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: repScaleAnimation.value,
          child: Text(
            totalReps.toString(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: _getRepCountColor(),
              shadows: [Shadow(color: Colors.black.withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4)],
            ),
          ),
        );
      },
    );
  }
}

class _QualityIndicator extends StatelessWidget {
  final double quality;

  const _QualityIndicator({required this.quality});

  Color _getQualityColor(double quality) {
    if (quality >= 0.8) return Colors.green;
    if (quality >= 0.6) return Colors.yellow;
    if (quality >= 0.4) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final qualityPercentage = (quality * 100).round();
    final qualityColor = _getQualityColor(quality);

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 13, color: qualityColor),
            const SizedBox(width: 4),
            Text(
              '$qualityPercentage%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: qualityColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 70,
          height: 2,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.white.withOpacity(0.2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: quality,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: qualityColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _PositionIndicator extends StatelessWidget {
  final ExerciseState state;

  const _PositionIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state == ExerciseState.up
        ? Colors.green
        : state == ExerciseState.down
        ? Colors.orange
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        state == ExerciseState.up
            ? LocaleKeys.workout_exercise_camera_position_up.tr()
            : state == ExerciseState.down
            ? LocaleKeys.workout_exercise_camera_position_down.tr()
            : LocaleKeys.workout_exercise_camera_position_neutral.tr(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color, letterSpacing: 1),
      ),
    );
  }
}

class _LastRepQualityIndicator extends StatelessWidget {
  final RepetitionData repData;

  const _LastRepQualityIndicator({required this.repData});

  Color _getQualityColor(RepQuality quality) {
    switch (quality) {
      case RepQuality.excellent:
        return Colors.green;
      case RepQuality.good:
        return Colors.blue;
      case RepQuality.fair:
        return Colors.orange;
      case RepQuality.poor:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final qualityColor = _getQualityColor(repData.quality);
    final qualityLabel = repData.quality.name.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: qualityColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: qualityColor, width: 1),
      ),
      child: Text(
        qualityLabel,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: qualityColor, letterSpacing: 0.8),
      ),
    );
  }
}

class _DurationTimerOverlay extends StatefulWidget {
  final int timerValue;
  final int? originalDuration;

  const _DurationTimerOverlay({required this.timerValue, this.originalDuration});

  @override
  State<_DurationTimerOverlay> createState() => _DurationTimerOverlayState();
}

class _DurationTimerOverlayState extends State<_DurationTimerOverlay> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_DurationTimerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Start pulsing when under 10 seconds
    if (widget.timerValue <= 10 && widget.timerValue > 0) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (widget.timerValue / 60).floor();
    final seconds = widget.timerValue % 60;
    final timeString = minutes > 0
        ? '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : seconds.toString().padLeft(2, '0');

    // Determine color based on remaining time
    Color timerColor = Colors.blue;
    if (widget.timerValue <= 10) {
      timerColor = Colors.red;
    } else if (widget.timerValue <= 30) {
      timerColor = Colors.orange;
    }

    return Positioned(
      top: 8,
      right: 5,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: widget.timerValue <= 10 ? _pulseAnimation.value : 1.0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: timerColor, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, size: 24, color: timerColor),
                    const SizedBox(height: 4),
                    Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: timerColor,
                        shadows: [Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LocaleKeys.workout_exercise_camera_time_label.tr(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildProgressIndicator(widget.timerValue, timerColor),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(int currentTime, Color color) {
    if (widget.originalDuration == null || widget.originalDuration! <= 0) {
      // Fallback: Use estimated progress for visual feedback
      final maxTime = currentTime > 60 ? 120 : 60;
      final progress = currentTime / maxTime;

      return Container(
        width: 70,
        height: 4,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.white.withOpacity(0.2)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: color),
          ),
        ),
      );
    }

    // Accurate progress calculation
    final progress = (widget.originalDuration! - currentTime) / widget.originalDuration!;

    return Container(
      width: 70,
      height: 4,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.white.withOpacity(0.2)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: color),
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onDismiss;

  const _ErrorOverlay({required this.errorMessage, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(errorMessage, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
