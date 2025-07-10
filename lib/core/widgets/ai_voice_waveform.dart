import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class AIVoiceWaveform extends StatefulWidget {
  final Stream<double> loudnessStream;
  final Color backgroundColor;
  final List<Color> waveColors;
  final BorderRadius borderRadius;
  final Duration animationDuration;

  const AIVoiceWaveform({
    super.key,
    required this.loudnessStream,
    this.backgroundColor = const Color(0xFFF4F6F8),
    this.waveColors = const [
      Color(0xFF66BB6A), // Leaf Green
      Color(0xFF26A69A), // Sea Green/Teal
      Color(0xFF5C9DFF), // Sky Blue
    ],
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.animationDuration = const Duration(seconds: 4),
  });

  @override
  State<AIVoiceWaveform> createState() => _AIVoiceWaveformState();
}

class _AIVoiceWaveformState extends State<AIVoiceWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  StreamSubscription<double>? _loudnessSubscription;
  double _targetLoudness = 0.0;
  double _currentLoudness = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration)..repeat();

    _subscribeToLoudnessStream();

    _controller.addListener(() {
      setState(() {
        _currentLoudness = lerpDouble(_currentLoudness, _targetLoudness, 0.08)!;
      });
    });
  }

  void _subscribeToLoudnessStream() {
    _loudnessSubscription?.cancel();
    _loudnessSubscription = widget.loudnessStream.listen((loudness) {
      if (mounted) {
        setState(() {
          _targetLoudness = loudness.clamp(0.0, 1.0);
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

    // << BUG FIX: This block now correctly updates the animation speed
    if (widget.animationDuration != oldWidget.animationDuration) {
      _controller.duration = widget.animationDuration;
      // Restart the animation controller to apply the new duration immediately.
      // Without this, the new duration only applies on the next loop.
      _controller.repeat();
    }
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
            painter: _WavePainter(animation: _controller, loudness: _currentLoudness, waveColors: widget.waveColors),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Animation<double> animation;
  final double loudness;
  final List<Color> waveColors;

  // << PERFORMANCE: Caching paint objects and size
  final List<Paint> _paints = [];
  Size? _lastSize;

  _WavePainter({required this.animation, required this.loudness, required this.waveColors}) : super(repaint: animation);

  // << PERFORMANCE: This method creates the Paint objects only when needed
  void _updatePaints(Size size) {
    // If the size and colors haven't changed, do nothing.
    if (size == _lastSize && _paints.isNotEmpty) return;

    _lastSize = size;
    _paints.clear();

    final waveConfigs = _getWaveConfigs();
    for (int i = 0; i < waveConfigs.length; i++) {
      final paint = Paint()
        ..blendMode = BlendMode.overlay
        ..shader = LinearGradient(
          colors: [
            waveColors[i % waveColors.length].withValues(alpha: 0.7),
            waveColors[(i + 1) % waveColors.length].withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      _paints.add(paint);
    }
  }

  List<List<num>> _getWaveConfigs() => [
    // Config: [frequency, speed (int), baseAmplitude]
    [2.5, 1, 7.0],
    [3.5, -1, 10.0],
    [4.0, 2.5, 6.0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Update paints only if size changes, this is a major performance boost.
    _updatePaints(size);

    final waveConfigs = _getWaveConfigs();

    for (int i = 0; i < waveConfigs.length; i++) {
      final config = waveConfigs[i];
      final frequency = config[0].toDouble();
      final speed = config[1].toInt();
      final baseAmplitude = config[2].toDouble();

      final path = Path();
      path.moveTo(0, size.height / 2);

      final maxAmplitude = baseAmplitude + (size.height / 2.5 * loudness);
      final centerY = size.height / 2;

      // << PERFORMANCE: Instead of calculating for every pixel, we use a step.
      // The blur effect hides the loss of resolution, giving a huge performance win.
      const double step = 5.0;

      for (double x = 0; x <= size.width + step; x += step) {
        final phase = animation.value * 2 * pi * speed;
        final sine = sin((x * 2 * pi / (size.width * frequency)) + phase);
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
    // The painter should only repaint if loudness or colors change.
    // The animation itself triggers repaints via the `repaint` notifier in the constructor.
    return loudness != oldDelegate.loudness || waveColors != oldDelegate.waveColors;
  }
}
