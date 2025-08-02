import 'dart:async';
import 'dart:io';
import 'dart:developer' show log;
import 'dart:math' show max;
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';
import 'package:waico/features/meditation/background_sound_manager.dart';

/// A player for meditation guides that plays audio chunks with proper timing
class MeditationPlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final BackgroundAudioPlayer _backgroundPlayer = BackgroundAudioPlayer();
  Timer? _pauseTimer;
  bool _isPlaying = false;
  bool _isPaused = false;
  String? _currentMeditationId;
  int _currentChunkIndex = 0;
  List<ScriptElement> _scriptElements = [];

  /// Whether the player is currently playing
  bool get isPlaying => _isPlaying;

  /// Whether the player is paused
  bool get isPaused => _isPaused;

  MeditationPlayer();

  /// Play a meditation guide
  Future<void> playMeditation(MeditationGuide guide) async {
    if (_isPlaying) {
      await stop();
    }

    _isPlaying = true;
    _isPaused = false;
    _currentMeditationId = guide.audioId;

    if (_currentMeditationId == null) {
      throw Exception('No audio ID found for meditation guide. Audio may not have been generated.');
    }

    try {
      // Load and start background sound if available
      if (guide.backgroundSound != null) {
        await _backgroundPlayer.loadSound(guide.backgroundSound!);
        _backgroundPlayer.play();
      }

      await _playMeditationScript(guide.script);
    } catch (e, s) {
      log('Error playing meditation: $e', error: e, stackTrace: s);
      await stop();
      rethrow;
    }
  }

  /// Pause the current meditation
  Future<void> pause() async {
    if (!_isPlaying || _isPaused) return;

    _isPaused = true;
    _pauseTimer?.cancel();
    await _audioPlayer.pause();
    await _backgroundPlayer.pause();
  }

  /// Resume the paused meditation
  Future<void> resume() async {
    if (!_isPlaying || !_isPaused) return;

    _isPaused = false;
    await _audioPlayer.play();
    await _backgroundPlayer.resume();
  }

  /// Stop the current meditation
  Future<void> stop() async {
    _isPlaying = false;
    _isPaused = false;
    _currentMeditationId = null;
    _currentChunkIndex = 0;
    _pauseTimer?.cancel();
    await _audioPlayer.stop();
    await _backgroundPlayer.stop();
  }

  /// Play the meditation script with proper chunk sequencing and pauses
  Future<void> _playMeditationScript(String script) async {
    final appDocumentsDir = await getApplicationDocumentsDirectory();
    final meditationDir = Directory('${appDocumentsDir.path}/meditation_audio/$_currentMeditationId');

    // Parse script to extract chunks and pauses
    _scriptElements = _parseScriptElements(script);
    _currentChunkIndex = 0;

    await _playNextElement(meditationDir);
  }

  /// Play the next element in the meditation script
  Future<void> _playNextElement(Directory meditationDir) async {
    while (_currentChunkIndex < _scriptElements.length && _isPlaying) {
      // Wait if paused
      while (_isPaused && _isPlaying) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!_isPlaying) break;

      final element = _scriptElements[_currentChunkIndex];
      _currentChunkIndex++;

      if (element.type == ElementType.audioChunk) {
        await _playAudioChunk(meditationDir, element.chunkIndex!);
      } else if (element.type == ElementType.pause) {
        await _executePause(element.pauseDuration!);
      }
    }

    // Meditation completed
    if (_isPlaying) {
      _isPlaying = false;
      _isPaused = false;
    }
  }

  /// Parse script elements into chunks and pauses
  List<ScriptElement> _parseScriptElements(String script) {
    log('Parsing meditation script: $script');
    final elements = <ScriptElement>[];

    final regex = RegExp(r'(CHUNK_(\d+))|\[pause\s+(\d+(?:\.\d+)?)\s*s?\]', caseSensitive: false);

    final matches = regex.allMatches(script);

    for (final match in matches) {
      if (match.group(1) != null) {
        // CHUNK_n
        final chunkIndex = int.tryParse(match.group(2)!);
        if (chunkIndex != null) {
          elements.add(ScriptElement(ElementType.audioChunk, chunkIndex: chunkIndex));
        }
      } else if (match.group(3) != null) {
        // [pause Ns]
        final duration = double.tryParse(match.group(3)!);
        if (duration != null) {
          log('Adding pause element with duration: $duration seconds');
          elements.add(
            ScriptElement(ElementType.pause, pauseDuration: max(duration, 5.0)),
          ); // Ensure minimum pause duration of 5 seconds (sometimes the E2B model generates very short pauses)
        }
      }
    }

    return elements;
  }

  /// Play a specific audio chunk
  Future<void> _playAudioChunk(Directory meditationDir, int chunkIndex) async {
    final audioFile = File('${meditationDir.path}/chunk_$chunkIndex.wav');

    if (await audioFile.exists()) {
      try {
        // Lower background volume during voice playback
        await _backgroundPlayer.lowerVolume();

        // Set up the audio source and play
        await _audioPlayer.setFilePath(audioFile.path);
        await _audioPlayer.setVolume(1.0);

        // Play the chunk
        await _audioPlayer.play();

        // Wait for the chunk to finish playing
        await _audioPlayer.playerStateStream.where((state) => state.processingState == ProcessingState.completed).first;

        // Restore background volume after voice finishes
        await _backgroundPlayer.restoreVolume();
      } catch (e) {
        log('Error playing audio chunk $chunkIndex: $e');
      }
    } else {
      log('Audio file not found: ${audioFile.path}');
    }
  }

  /// Execute a pause with the specified duration
  Future<void> _executePause(double durationSeconds) async {
    final completer = Completer<void>();

    _pauseTimer = Timer(Duration(milliseconds: (durationSeconds * 1000).round()), () {
      completer.complete();
    });

    await completer.future;
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
    await _backgroundPlayer.dispose();
  }
}

/// Represents an element in the meditation script
class ScriptElement {
  final ElementType type;
  final int? chunkIndex;
  final double? pauseDuration;

  ScriptElement(this.type, {this.chunkIndex, this.pauseDuration});
}

/// Types of elements in a meditation script
enum ElementType { audioChunk, pause }
