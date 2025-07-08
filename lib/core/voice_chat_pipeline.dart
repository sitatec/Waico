import 'dart:async';
import 'dart:developer' show log;

import 'package:audio_session/audio_session.dart' show AudioSession, AudioSessionConfiguration;
import 'package:cross_file/cross_file.dart' show XFile;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show LlmProvider, ImageFileAttachment;
import 'package:waico/core/audio_stream_player.dart';
import 'package:waico/core/tts_model.dart';
import 'package:waico/core/user_speech_listener.dart';

class VoiceChatPipeline {
  final LlmProvider llm;
  final UserSpeechToTextListener _userSpeechToTextListener;
  final TtsModel _tts;
  final List<XFile> _pendingImages = [];
  String? voice;
  final AudioStreamPlayer _audioStreamPlayer;
  StreamSubscription? _userSpeechStreamSubscription;

  /// Can be used to animate the AI speech waves widget
  Stream<double> get aiSpeechLoudnessStream => _audioStreamPlayer.loudnessStream;

  VoiceChatPipeline({
    required this.llm,
    UserSpeechToTextListener? userSpeechToTextListener,
    TtsModel? tts,
    AudioStreamPlayer? audioStreamPlayer,
  }) : _tts = tts ?? TtsModel(),
       _audioStreamPlayer = audioStreamPlayer ?? AudioStreamPlayer(),
       _userSpeechToTextListener = userSpeechToTextListener ?? UserSpeechListener.withTranscription();

  Future<void> startChat({required String voice}) async {
    // TODO: Add interruption support (user can interrupt ai). On android cancelling generation is supported by mediapipe
    // But not in flutter yet. On IOS we interrupt but with delay, model generation is generally faster then the synthesized
    // audio, so we can cancel the speech as soon as the model finish generation until IOS support cancelling generation.
    this.voice = voice;

    _userSpeechToTextListener.listen(_onUserSpeechTranscribed);
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    _startListeningToUser();
  }

  Future<void> endChat() async {
    await _userSpeechStreamSubscription?.cancel();
    await _audioStreamPlayer.stop();
  }

  Future<void> _onUserSpeechTranscribed(String text) async {
    // TODO: Check for interruption and notify the user that interruption is not supported yet, they need to wait for
    // the ai speech to finish

    _stopListeningToUser(); // Stop listening to the user since interruption is not supported yet.
    final attachments = await _pendingImages.map((imageFile) => ImageFileAttachment.fromFile(imageFile)).wait;
    _pendingImages.clear();

    String sentenceBuffer = "";
    llm
        .sendMessageStream(text, attachments: attachments)
        .listen(
          (textChunk) {
            sentenceBuffer += textChunk;

            // A sentence detection logic. This reduces LLm response latency since we don't have to wait for the full
            // response, we can send the sentences to the TTS model as they are detected in the stream.

            // It splits the text by sentence-ending punctuation followed by a space or at the end of the string.
            final sentenceEndings = RegExp(r'(?<=[.?!])\s+');
            final potentialSentences = sentenceBuffer.split(sentenceEndings);

            // Process all but the last part, which might be an incomplete sentence.
            for (var i = 0; i < potentialSentences.length - 1; i++) {
              final sentence = potentialSentences[i].trim();
              if (sentence.isNotEmpty) {
                log('Detected sentence: $sentence');
                _generateSpeech(sentence);
              }
            }
            // The last part is kept in the buffer until the next sentence is detected or stream is done
            sentenceBuffer = potentialSentences.last;
          },
          onDone: () {
            if (sentenceBuffer.isNotEmpty) {
              log('Remaining sentence: $sentenceBuffer');
              _generateSpeech(sentenceBuffer, isLastInCurrentTurn: true);
            } else {
              _startListeningToUser();
            }
          },
        );
  }

  void addImages(List<XFile> imageFiles) {
    _pendingImages.addAll(imageFiles);
  }

  /// TODO: Remove when interruption support added.
  Future<void> _startListeningToUser() async {
    await _audioStreamPlayer.pause();
    await _userSpeechToTextListener.resume();
  }

  /// TODO: Remove when interruption support added.
  Future<void> _stopListeningToUser() async {
    await _userSpeechToTextListener.pause();
    await _audioStreamPlayer.resume();
  }

  /// Generate and queue TTS audio
  Future<void> _generateSpeech(String text, {bool isLastInCurrentTurn = false}) async {
    final ttsResult = _tts.generateSpeech(text: text, voice: voice!, speed: 1.0);

    await _audioStreamPlayer.append(ttsResult.toWav(), caption: text);
    if (isLastInCurrentTurn) {
      // Start listening again when the last AI speech is done. TODO: Remove when interruption support added.
      _audioStreamPlayer.appendCallback(_startListeningToUser);
    }
  }

  Future<void> dispose() async {
    await _userSpeechStreamSubscription?.cancel();
    await _audioStreamPlayer.dispose();
    _userSpeechStreamSubscription = null;
  }
}
