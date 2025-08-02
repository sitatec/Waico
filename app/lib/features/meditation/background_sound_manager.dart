import 'dart:math';
import 'package:just_audio/just_audio.dart';

/// Manages background meditation sounds
class BackgroundSoundManager {
  static const List<String> availableSounds = [
    'meditation_bg_1.m4a',
    'meditation_bg_2.m4a',
    'meditation_bg_3.m4a',
    'meditation_bg_4.m4a',
  ];

  static const Map<String, String> soundNames = {
    'meditation_bg_1.m4a': 'One',
    'meditation_bg_2.m4a': 'Two',
    'meditation_bg_3.m4a': 'Three',
    'meditation_bg_4.m4a': 'Four',
  };

  /// Get a random background sound filename
  static String getRandomSound() {
    final random = Random();
    return availableSounds[random.nextInt(availableSounds.length)];
  }

  /// Get display name for a background sound
  static String getDisplayName(String filename) {
    return soundNames[filename] ?? filename.replaceAll('.m4a', '').replaceAll('meditation_bg_', 'Sound ');
  }

  /// Get all available sounds with their display names
  static List<BackgroundSoundOption> getAllSounds() {
    return availableSounds
        .map((filename) => BackgroundSoundOption(filename: filename, displayName: getDisplayName(filename)))
        .toList();
  }
}

/// Represents a background sound option
class BackgroundSoundOption {
  final String filename;
  final String displayName;

  BackgroundSoundOption({required this.filename, required this.displayName});
}

/// Audio player specifically for background sounds with volume control
class BackgroundAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isPaused = false;
  static const double _baseVolume = 0.3; // Base volume for background audio
  static const double _loweredVolume = 0.15; // Volume during voice playback

  /// Whether background audio is currently playing
  bool get isPlaying => _isPlaying;

  /// Whether background audio is currently paused
  bool get isPaused => _isPaused;

  /// Current volume
  double get volume => _player.volume;

  /// Initialize and load a background sound
  Future<void> loadSound(String soundFilename) async {
    try {
      await _player.setAsset('assets/audio/$soundFilename');
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(_baseVolume);
    } catch (e) {
      throw Exception('Failed to load background sound $soundFilename: $e');
    }
  }

  /// Start playing the background sound
  Future<void> play() async {
    if (!_isPlaying) {
      _isPlaying = true;
      await _player.play();
    }
  }

  /// Stop playing the background sound
  Future<void> stop() async {
    if (_isPlaying) {
      _isPlaying = false;
      await _player.stop();
    }
  }

  /// Pause the background sound
  Future<void> pause() async {
    if (_isPlaying) {
      _isPaused = true;
      await _player.pause();
    }
  }

  /// Resume the background sound
  Future<void> resume() async {
    if (_isPaused) {
      _isPaused = false;
      await _player.play();
    }
  }

  /// Lower volume during voice playback
  Future<void> lowerVolume() async {
    await _player.setVolume(_loweredVolume);
  }

  /// Restore volume after voice playback
  Future<void> restoreVolume() async {
    await _player.setVolume(_baseVolume);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _player.dispose();
    _isPlaying = false;
    _isPaused = false;
  }
}
