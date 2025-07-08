import 'dart:async';

import 'package:audio_session/audio_session.dart' show AudioSession, AudioSessionConfiguration;
import 'package:cross_file/cross_file.dart' show XFile;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show LlmProvider;
import 'package:waico/core/audio_stream_player.dart';
import 'package:waico/core/tts_model.dart';

class VoiceChatPipeline {
  final LlmProvider llm;
  final TtsModel _tts;
  final List<XFile> _pendingImages = [];
  String? voice;
  final AudioStreamPlayer _audioStreamPlayer;
  StreamSubscription? _sttStreamSubscription;
  StreamSubscription? _sttStateSubscription;

  /// Can be used to animate the AI speech waves widget
  Stream<double> get aiSpeechLoudnessStream => _audioStreamPlayer.loudnessStream;

  VoiceChatPipeline({required this.llm, TtsModel? tts, AudioStreamPlayer? audioStreamPlayer})
    : _tts = tts ?? TtsModel(),
      _audioStreamPlayer = audioStreamPlayer ?? AudioStreamPlayer();

  Future<void> startChat({required String voice}) async {
    this.voice = voice;
    // TODO: Add interruption support (user can interrupt ai). On android cancelling generation is supported by mediapipe
    // But not in flutter yet. On IOS we interrupt but with delay, model generation is generally faster then the synthesized
    // audio, so we can cancel the speech as soon as the model finish generation until IOS support cancelling generation.
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    _startListeningToUser();
  }

  Future<void> endChat() async {
    await _sttStreamSubscription?.cancel();
    await _audioStreamPlayer.stop();
  }

  Future<void> dispose() async {
    await _sttStreamSubscription?.cancel();
    await _audioStreamPlayer.dispose();
    await _sttStateSubscription?.cancel();
    _sttStateSubscription = null;
    _sttStreamSubscription = null;
  }

  void addImages(List<XFile> imageFiles) {
    _pendingImages.addAll(imageFiles);
  }

  Future<void> _startListeningToUser() async {
    await _audioStreamPlayer.pause();
  }

  /// Generate and queue TTS audio
  Future<void> generateTts(String text, {bool isLastInCurrentTurn = false}) async {
    final ttsResult = _tts.generateSpeech(text: text, voice: voice!, speed: 1.0);

    await _audioStreamPlayer.append(ttsResult.toWav(), caption: text);
    if (isLastInCurrentTurn) {
      _audioStreamPlayer.appendCallback(_startListeningToUser);
    }
  }
}
