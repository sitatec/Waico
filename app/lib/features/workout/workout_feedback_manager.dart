import 'dart:developer' show log;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Used when voice chat is disabled in the workout manager to provide audio feedback and rep counting
/// Manages pre-recorded audio feedback for workout exercises
class WorkoutFeedbackManager {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final String languageCode;

  /// All available feedback folder names for exercises
  static const List<String> _feedbackFolders = [
    'counting',
    'crunch_knee_stability',
    'crunch_hip_stability',
    'reverse_crunch_knee_symmetry',
    'reverse_crunch_range_of_motion',
    'double_crunch_movement_coordination',
    'double_crunch_bilateral_symmetry',
    'double_crunch_full_range_activation',
    'plank_body_alignment',
    'plank_hip_stability',
    'plank_core_engagement',
    'side_plank_body_alignment',
    'side_plank_hip_elevation',
    'side_plank_supporting_arm_stability',
    'side_plank_shoulder_stacking',
    'side_plank_hip_stacking',
    'side_plank_core_stability',
    'pushup_body_alignment',
    'squat_squat_depth',
    'sumo_squat_knee_tracking',
    'sumo_squat_squat_depth',
    'split_squat_front_knee_tracking',
    'superman_arm_extension',
    'superman_leg_extension',
    'superman_bilateral_symmetry',
    'overall_visibility',
    'excellent_form',
  ];

  WorkoutFeedbackManager({required this.languageCode});

  /// Play rep counting audio for the given rep number
  Future<void> playRepCountingAudio(int repNumber) async {
    if (_audioPlayer.playing && _audioPlayer.playerState.processingState != ProcessingState.completed) {
      return; // Rep counting audio should not interrupt feedback audio
    }
    if (repNumber > 30) {
      log('Rep number $repNumber exceeds maximum supported of 30. No audio will be played.');
      return;
    }
    try {
      final audioPath = 'assets/audio/workout/${languageCode}_counting_$repNumber.m4a';

      if (await _audioAssetExists(audioPath)) {
        await _audioPlayer.setAsset(audioPath);
        await _audioPlayer.play();
        log('Playing rep counting audio: $audioPath');
      } else {
        log('Rep counting audio not found: $audioPath');
      }
    } catch (e, s) {
      log('Error playing rep counting audio for rep $repNumber', error: e, stackTrace: s);
    }
  }

  /// Play form feedback audio based on exercise name and feedback key
  Future<void> playFormFeedbackAudio(String exerciseName, String feedbackKey) async {
    if (_audioPlayer.playing &&
        _audioPlayer.playerState.processingState != ProcessingState.completed &&
        !(_audioPlayer.audioSource as UriAudioSource).uri.toString().contains('_counting_')) {
      return; // Only rep counting audio should be interrupted
    }
    try {
      final folderName = _getFeedbackFolderName(exerciseName, feedbackKey);
      if (folderName == null) {
        log('No feedback folder found for exercise: $exerciseName, feedback: $feedbackKey');
        return;
      }

      // Try to play a random feedback audio (1-5.m4a)
      final audioNumber = math.Random().nextInt(5) + 1;
      final audioPath = 'assets/audio/workout/${languageCode}_${folderName}_$audioNumber.m4a';

      if (await _audioAssetExists(audioPath)) {
        await _audioPlayer.setAsset(audioPath);
        await _audioPlayer.play();
        log('Playing form feedback audio: $audioPath');
      } else {
        log('Form feedback audio not found: $audioPath');
      }
    } catch (e, s) {
      log('Error playing form feedback audio for ${exerciseName}_$feedbackKey', error: e, stackTrace: s);
    }
  }

  /// Play excellent form feedback audio
  Future<void> playExcellentFormFeedback() async {
    if (_audioPlayer.playing &&
        _audioPlayer.playerState.processingState != ProcessingState.completed &&
        !(_audioPlayer.audioSource as UriAudioSource).uri.toString().contains('_counting_')) {
      return; // Only rep counting audio should be interrupted
    }
    try {
      // Try to play a random excellent form audio (1-8.m4a)
      final audioNumber = math.Random().nextInt(8) + 1;
      final audioPath = 'assets/audio/workout/${languageCode}_excellent_form_$audioNumber.m4a';

      if (await _audioAssetExists(audioPath)) {
        await _audioPlayer.setAsset(audioPath);
        await _audioPlayer.play();
        log('Playing excellent form feedback: $audioPath');
      } else {
        log('Excellent form feedback audio not found: $audioPath');
      }
    } catch (e, s) {
      log('Error playing excellent form feedback', error: e, stackTrace: s);
    }
  }

  /// Play overall visibility feedback audio
  Future<void> playOverallVisibilityFeedback() async {
    if (_audioPlayer.playing &&
        _audioPlayer.playerState.processingState != ProcessingState.completed &&
        !(_audioPlayer.audioSource as UriAudioSource).uri.toString().contains('_counting_')) {
      return; // Only rep counting audio should be interrupted
    }
    try {
      // Try to play a random overall visibility feedback audio (1-5.m4a)
      final audioNumber = math.Random().nextInt(5) + 1;
      final audioPath = 'assets/audio/workout/${languageCode}_overall_visibility_$audioNumber.m4a';

      if (await _audioAssetExists(audioPath)) {
        await _audioPlayer.setAsset(audioPath);
        await _audioPlayer.play();
        log('Playing overall visibility feedback: $audioPath');
      } else {
        log('Overall visibility feedback audio not found: $audioPath');
      }
    } catch (e, s) {
      log('Error playing overall visibility feedback', error: e, stackTrace: s);
    }
  }

  /// Get the appropriate feedback folder name based on exercise and feedback key
  String? _getFeedbackFolderName(String exerciseName, String feedbackKey) {
    final exerciseNameLower = exerciseName.toLowerCase();

    // Handle global feedback keys
    if (feedbackKey == 'excellent_form') {
      return 'excellent_form';
    }
    if (feedbackKey == 'overall_visibility') {
      return 'overall_visibility';
    }

    // Handle exercise-specific feedback keys
    final exerciseSpecificKey = '${_getExercisePrefix(exerciseNameLower)}_$feedbackKey';

    if (_feedbackFolders.contains(exerciseSpecificKey)) {
      return exerciseSpecificKey;
    }

    log('No feedback folder found for exercise: $exerciseName, feedback: $feedbackKey');
    return null;
  }

  /// Get the exercise prefix for folder naming
  String _getExercisePrefix(String exerciseName) {
    if (exerciseName.contains('crunch')) {
      if (exerciseName.contains('reverse')) {
        return 'reverse_crunch';
      } else if (exerciseName.contains('double')) {
        return 'double_crunch';
      } else {
        return 'crunch';
      }
    } else if (exerciseName.contains('plank')) {
      if (exerciseName.contains('side')) {
        return 'side_plank';
      } else {
        return 'plank';
      }
    } else if (exerciseName.contains('push') && exerciseName.contains('up')) {
      return 'pushup';
    } else if (exerciseName.contains('squat')) {
      if (exerciseName.contains('sumo')) {
        return 'sumo_squat';
      } else if (exerciseName.contains('split')) {
        return 'split_squat';
      } else {
        return 'squat';
      }
    } else if (exerciseName.contains('superman')) {
      return 'superman';
    }

    return exerciseName.replaceAll(' ', '_').toLowerCase();
  }

  /// Check if an audio asset exists
  Future<bool> _audioAssetExists(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop any currently playing audio
  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (e, s) {
      log('Error stopping audio', error: e, stackTrace: s);
    }
  }

  /// Dispose of the audio player
  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
    } catch (e, s) {
      log('Error disposing audio player', error: e, stackTrace: s);
    }
  }
}
