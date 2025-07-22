import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:waico/features/workout/pose_detection/pose_detection_service.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';

/// A beautiful camera widget with pose detection and rep counting overlay
class WorkoutCameraWidget extends StatefulWidget {
  final RepsCounter? repsCounter;
  final bool showRepCounter;
  final VoidCallback? onPermissionDenied;
  final Function(String)? onError;

  const WorkoutCameraWidget({
    super.key,
    this.repsCounter,
    this.showRepCounter = true,
    this.onPermissionDenied,
    this.onError,
  });

  @override
  State<WorkoutCameraWidget> createState() => _WorkoutCameraWidgetState();
}

class _WorkoutCameraWidgetState extends State<WorkoutCameraWidget> with TickerProviderStateMixin {
  final PoseDetectionService _poseService = PoseDetectionService.instance;

  StreamSubscription<CameraFrame>? _cameraSubscription;
  StreamSubscription<PoseDetectionResult>? _poseSubscription;
  StreamSubscription<RepetitionRecord>? _repSubscription;
  StreamSubscription<String>? _errorSubscription;

  Uint8List? _currentFrame;
  bool _isInitialized = false;
  String? _errorMessage;

  // Rep counter state
  int _totalReps = 0;
  double _lastQuality = 0.0;
  bool _isUp = false;

  // Animations
  late AnimationController _repAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _repScaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCamera();
  }

  void _initializeAnimations() {
    _repAnimationController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);

    _pulseController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat();

    _repScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _repAnimationController, curve: Curves.elasticOut));

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  Future<void> _initializeCamera() async {
    try {
      // Check permissions
      final hasPermission = await _poseService.hasCameraPermission();
      if (!hasPermission) {
        widget.onPermissionDenied?.call();
        setState(() {
          _errorMessage = 'Camera permission required';
        });
        return;
      }

      // Start pose detection
      final started = await _poseService.start();
      if (!started) {
        setState(() {
          _errorMessage = 'Failed to start camera';
        });
        return;
      }

      // Set up streams
      _setupStreams();

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Camera initialization failed: $e';
      });
      widget.onError?.call(_errorMessage!);
    }
  }

  void _setupStreams() {
    // Camera stream
    _cameraSubscription = _poseService.cameraStream.listen(
      (frame) {
        if (mounted) {
          setState(() {
            _currentFrame = Uint8List.fromList(frame.imageBytes);
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Camera stream error: $error';
          });
        }
      },
    );

    // Pose detection stream
    _poseSubscription = _poseService.landmarkStream.listen((result) {
      if (result.hasPose && widget.repsCounter != null) {
        widget.repsCounter!.processPoseData(worldLandmarks: result.worldLandmarks, imageLandmarks: result.landmarks);

        // Update pose state for visual feedback
        final stats = widget.repsCounter!.getSessionStats();
        if (mounted) {
          setState(() {
            _isUp = stats['isUp'] as bool;
          });
        }
      }
    });

    // Rep counter stream
    if (widget.repsCounter != null) {
      _repSubscription = widget.repsCounter!.repStream.listen((rep) {
        if (mounted) {
          setState(() {
            _totalReps = rep.repNumber;
            _lastQuality = rep.qualityScore;
          });

          // Trigger rep animation
          _repAnimationController.forward().then((_) {
            _repAnimationController.reverse();
          });
        }
      });
    }

    // Error stream
    _errorSubscription = _poseService.errorStream.listen((error) {
      if (mounted) {
        setState(() {
          _errorMessage = error;
        });
        widget.onError?.call(error);
      }
    });
  }

  @override
  void dispose() {
    _repAnimationController.dispose();
    _pulseController.dispose();
    _cameraSubscription?.cancel();
    _poseSubscription?.cancel();
    _repSubscription?.cancel();
    _errorSubscription?.cancel();
    _poseService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera view
          _buildCameraView(),

          // Rep counter overlay (top-right corner)
          if (widget.showRepCounter && widget.repsCounter != null) _buildRepCounterOverlay(),

          // Error overlay
          if (_errorMessage != null) _buildErrorOverlay(),

          // Controls overlay (bottom)
          _buildControlsOverlay(),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_isInitialized || _currentFrame == null) {
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

    return SizedBox.expand(child: Image.memory(_currentFrame!, fit: BoxFit.cover, gaplessPlayback: true));
  }

  Widget _buildRepCounterOverlay() {
    return Positioned(
      top: 60,
      right: 20,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.black.withOpacity(0.8), Colors.black.withOpacity(0.6)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _isUp ? Colors.green : Colors.orange, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rep count with animation
                  AnimatedBuilder(
                    animation: _repScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _repScaleAnimation.value,
                        child: Text(
                          _totalReps.toString(),
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: _getRepCountColor(),
                            shadows: [
                              Shadow(color: Colors.black.withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 4),

                  // "REPS" label
                  Text(
                    'REPS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.8),
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Quality indicator
                  _buildQualityIndicator(),

                  const SizedBox(height: 8),

                  // Position indicator
                  _buildPositionIndicator(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQualityIndicator() {
    final qualityPercentage = (_lastQuality * 100).round();
    final qualityColor = _getQualityColor(_lastQuality);

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
            widthFactor: _lastQuality,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: qualityColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPositionIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isUp ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isUp ? Colors.green : Colors.orange, width: 1),
      ),
      child: Text(
        _isUp ? 'UP' : 'DOWN',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _isUp ? Colors.green : Colors.orange,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
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
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Switch camera button
          _buildControlButton(icon: Icons.flip_camera_ios, onPressed: () => _poseService.switchCamera()),

          const SizedBox(width: 20),

          // Reset reps button
          if (widget.repsCounter != null)
            _buildControlButton(
              icon: Icons.refresh,
              onPressed: () {
                widget.repsCounter!.reset();
                setState(() {
                  _totalReps = 0;
                  _lastQuality = 0.0;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 24),
        onPressed: onPressed,
      ),
    );
  }

  Color _getRepCountColor() {
    if (_totalReps == 0) return Colors.white;
    if (_totalReps >= 20) return Colors.green;
    if (_totalReps >= 10) return Colors.blue;
    return Colors.orange;
  }

  Color _getQualityColor(double quality) {
    if (quality >= 0.8) return Colors.green;
    if (quality >= 0.6) return Colors.yellow;
    if (quality >= 0.4) return Colors.orange;
    return Colors.red;
  }
}
