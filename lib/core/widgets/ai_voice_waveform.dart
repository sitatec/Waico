import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class AIVoiceWaveform extends StatefulWidget {
  final Stream<double> loudnessStream;
  final Color backgroundColor;
  final List<Color> waveColors;
  final BorderRadius borderRadius;

  const AIVoiceWaveform({
    super.key,
    required this.loudnessStream,
    this.backgroundColor = const Color.fromARGB(255, 238, 243, 247),
    this.waveColors = const [Color(0xFF66BB6A), Color(0xFF4B9B6E), const Color.fromARGB(255, 66, 165, 245)],
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    // The animation speed is now controlled by loudness, so duration is removed.
  });

  @override
  State<AIVoiceWaveform> createState() => _AIVoiceWaveformState();
}

class _AIVoiceWaveformState extends State<AIVoiceWaveform> with SingleTickerProviderStateMixin {
  static const _minLoudness = 0.15;

  late final AnimationController _controller;
  StreamSubscription<double>? _loudnessSubscription;
  double _targetLoudness = _minLoudness;
  double _currentLoudness = 0.0;

  // << NEW: This variable will hold the animation's progress, updated on every frame.
  double _animationPhase = 0.0;

  @override
  void initState() {
    super.initState();
    // The controller is now just a "ticker" to drive the animation frame-by-frame.
    // Its duration is constant and does not affect the visual speed directly.
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

    _subscribeToLoudnessStream();

    _controller.addListener(() {
      // Define the range for the animation speed.
      const double idleSpeed = 0.0; // Speed when loudness is 0
      const double maxSpeed = 1.0; // Speed when loudness is 1

      // Interpolate the speed based on the current (smoothed) loudness.
      final speed = lerpDouble(idleSpeed, maxSpeed, _currentLoudness)!;

      // Increment the animation phase. The multiplier (0.1) adjusts the overall speed.
      _animationPhase = (_animationPhase + speed * 0.1) % (2 * pi);

      setState(() {
        // Smoothly update the loudness value.
        _currentLoudness = lerpDouble(_currentLoudness, _targetLoudness, 0.07)!;
      });
    });
  }

  void _subscribeToLoudnessStream() {
    _loudnessSubscription?.cancel();
    _loudnessSubscription = widget.loudnessStream.listen((loudness) {
      if (mounted) {
        setState(() {
          _targetLoudness = loudness.clamp(_minLoudness, 1);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant AIVoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loudnessStream != oldWidget.loudnessStream) {
      _subscribeToLoudnessStream();
    }
    // The logic for updating animationDuration is no longer needed.
  }

  @override
  void dispose() {
    _controller.dispose();
    _loudnessSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        color: widget.backgroundColor,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 5, tileMode: TileMode.decal),
          child: CustomPaint(
            size: Size.infinite,
            painter: _WavePainter(phase: _animationPhase, loudness: _currentLoudness, waveColors: widget.waveColors),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  // << MODIFIED: Takes a simple double for phase, not the whole animation.
  final double phase;
  final double loudness;
  final List<Color> waveColors;

  final List<Paint> _paints = [];
  Size? _lastSize;

  _WavePainter({required this.phase, required this.loudness, required this.waveColors})
    : super(repaint: Listenable.merge([ValueNotifier(phase), ValueNotifier(loudness)]));

  void _updatePaints(Size size) {
    if (size == _lastSize && _paints.isNotEmpty) return;

    _lastSize = size;
    _paints.clear();

    final waveConfigs = _getWaveConfigs();
    for (int i = 0; i < waveConfigs.length; i++) {
      final paint = Paint()
        ..blendMode = BlendMode.overlay
        ..shader = LinearGradient(
          colors: [
            waveColors[(i + 1) % waveColors.length].withOpacity(0.4),
            waveColors[i % waveColors.length].withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      _paints.add(paint);
    }
  }

  List<List<num>> _getWaveConfigs() => [
    // Config: [frequency, speed (int), baseAmplitude]
    [2.5, 1, 5.0],
    [3.5, -1, 8.0],
    [4.0, 2, 4.0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _updatePaints(size);

    final waveConfigs = _getWaveConfigs();

    for (int i = 0; i < waveConfigs.length; i++) {
      final config = waveConfigs[i];
      final frequency = config[0].toDouble();
      final speed = config[1].toInt();
      final baseAmplitude = config[2].toDouble();

      final path = Path();
      path.moveTo(0, size.height / 2);

      final maxAmplitude = baseAmplitude + (size.height / 3 * loudness);
      final centerY = size.height / 2.5;
      const double step = 5.0;

      for (double x = 0; x <= size.width + step; x += step) {
        // << MODIFIED: The main animation phase is now provided directly.
        final sinePhase = this.phase * speed;
        final sine = sin((x * 2 * pi / (size.width * frequency)) + sinePhase);
        final y = centerY + sine * maxAmplitude;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      canvas.drawPath(path, _paints[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    // Repaint if the phase, loudness, or colors change.
    return oldDelegate.phase != phase || oldDelegate.loudness != loudness || oldDelegate.waveColors != waveColors;
  }
}
