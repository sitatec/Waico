import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';
import 'package:waico/features/meditation/meditation_player.dart';

/// Widget for playing meditation audio chunks and background sound
class MeditationSoundPlayer extends StatefulWidget {
  final MeditationGuide guide;

  const MeditationSoundPlayer({super.key, required this.guide});

  @override
  State<MeditationSoundPlayer> createState() => _MeditationSoundPlayerState();
}

class _MeditationSoundPlayerState extends State<MeditationSoundPlayer> {
  MeditationPlayer? _meditationPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;
  List<String> _audioChunks = [];

  @override
  void initState() {
    super.initState();
    _initializePlayers();
  }

  @override
  void dispose() {
    _meditationPlayer?.dispose();
    super.dispose();
  }

  Future<void> _initializePlayers() async {
    try {
      // Initialize meditation player if audio chunks exist
      if (widget.guide.audioId != null) {
        _meditationPlayer = MeditationPlayer();
        // Check if audio files exist
        final appDocumentsDir = await getApplicationDocumentsDirectory();
        final meditationDir = Directory('${appDocumentsDir.path}/meditation_audio/${widget.guide.audioId}');
        if (await meditationDir.exists()) {
          final audioFiles = await meditationDir.list().where((f) => f.path.endsWith('.wav')).toList();
          _audioChunks = audioFiles.map((f) => f.path).toList();
        }
      }

      setState(() {
        _isInitialized = true;
      });
    } catch (e, s) {
      log('Error initializing audio players', error: e, stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing audio: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _playPause() async {
    if (!_isInitialized) return;

    try {
      if (_isPlaying) {
        await _meditationPlayer?.pause();
      } else {
        if (_meditationPlayer != null) {
          // Start meditation playback
          if (_meditationPlayer!.isPaused) {
            _meditationPlayer!.resume();
          } else {
            _meditationPlayer!.playMeditation(widget.guide);
          }
        }
      }
      setState(() {
        _isPlaying = !_isPlaying;
      });
    } catch (e, s) {
      log('Error controlling playback', error: e, stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error controlling playback: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _stop() async {
    if (!_isInitialized) return;

    try {
      await _meditationPlayer?.stop();
      setState(() {
        _isPlaying = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping playback: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // If no audio chunks exist, show the script text
    if (_audioChunks.isEmpty) {
      return _buildScriptView(theme);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: Padding(padding: const EdgeInsets.all(32), child: Image.asset('assets/images/meditation.png')),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Keep only play/stop fro now. TODO: enable other controls and fix resumption issue
                // Stop button
                // IconButton(onPressed: _isPlaying ? _stop : null, icon: const Icon(Icons.stop), iconSize: 32),
                const SizedBox(width: 16),

                // Play/Pause button
                IconButton(
                  onPressed: _isPlaying ? _stop : _playPause,
                  icon: Icon(_isPlaying ? Icons.stop_circle : Icons.play_circle),
                  iconSize: 48,
                  color: theme.colorScheme.primary,
                ),

                const SizedBox(width: 16),

                // Placeholder for future controls
                // IconButton(onPressed: null, icon: const Icon(Icons.skip_next), iconSize: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScriptView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Script text
        Text('Meditation Script', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(widget.guide.script, style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87)),
      ],
    );
  }

  // TODO: allow the user to select background sound from here and not during creation
}
