import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';

/// A high-performance camera widget with pose detection using native platform views
class WorkoutCameraWidget extends StatefulWidget {
  final RepsCounter? repsCounter;
  final bool showRepCounter;

  const WorkoutCameraWidget({super.key, this.repsCounter, this.showRepCounter = true});

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
          _errorMessage = 'Camera permission required';
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
    } catch (e) {
      setState(() {
        _errorMessage = 'Initialization failed: $e';
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text('Camera permission required', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      );
    }

    if (!isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Initializing camera...', style: TextStyle(color: Colors.white, fontSize: 16)),
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
    final isUp = repCountingState.currentState == ExerciseState.up;
    final lastQuality = repCountingState.lastRep?.formScore ?? 0.0;

    return Positioned(
      top: 24,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0.3)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RepCountDisplay(totalReps: repCountingState.totalReps, repScaleAnimation: repScaleAnimation),
            const SizedBox(height: 4),
            Text(
              'REPS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.8),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            _QualityIndicator(quality: lastQuality),
            const SizedBox(height: 8),
            _PositionIndicator(isUp: isUp),
            if (repCountingState.lastRep != null) ...[
              const SizedBox(height: 8),
              _LastRepQualityIndicator(repData: repCountingState.lastRep!),
            ],
          ],
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
              fontSize: 30,
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
            Icon(Icons.star_rounded, size: 14, color: qualityColor),
            const SizedBox(width: 4),
            Text(
              '$qualityPercentage%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: qualityColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 80,
          height: 4,
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
  final bool isUp;

  const _PositionIndicator({required this.isUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isUp ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isUp ? Colors.green : Colors.orange, width: 1),
      ),
      child: Text(
        isUp ? 'UP' : 'DOWN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isUp ? Colors.green : Colors.orange,
          letterSpacing: 1,
        ),
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
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: qualityColor, letterSpacing: 0.8),
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
