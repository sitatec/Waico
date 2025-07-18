import 'dart:async';
import 'dart:developer' show log;

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show ImageFileAttachment;
import 'package:synchronized/synchronized.dart';
import 'package:waico/core/ai_agent/ai_agent.dart';
import 'package:waico/core/services/audio_stream_player.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/core/services/user_speech_listener.dart';
import 'package:waico/core/utils/string_utils.dart';

class VoiceChatPipeline {
  final AiAgent agent;
  final UserSpeechToTextListener _userSpeechToTextListener;
  final TtsModel _tts;
  final List<XFile> _pendingImages = [];
  String? voice;
  final AudioStreamPlayer _audioStreamPlayer;
  StreamSubscription? _userSpeechStreamSubscription;
  bool _hasChatEnded = false;
  // Used wait until the current TTS task complete before starting the next one.
  final _asyncLock = Lock();

  /// Can be used to animate the AI speech waves widget (value range 0-1)
  Stream<double> get aiSpeechLoudnessStream => _audioStreamPlayer.loudnessStream;

  VoiceChatPipeline({
    required this.agent,
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
    _hasChatEnded = false;
    await _userSpeechToTextListener.initialize();
    _userSpeechStreamSubscription = _userSpeechToTextListener.listen(_onUserSpeechTranscribed);
    _startListeningToUser();
  }

  Future<void> endChat() async {
    if (_hasChatEnded) return;
    _hasChatEnded = true;
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
    await for (final textChunk in agent.sendMessage(text, attachments: attachments)) {
      if (_hasChatEnded) {
        // Currently there is no way to cancel generation once it starts, so we use this variable stop handling.
        return;
      }
      sentenceBuffer += textChunk;

      // A logic to detect readable chunk of a text. It can be a full sentence or up to a comma, or anything that causes a pause
      // when reading. So that the next chunk can be read and it will feel natural.
      // This reduces LLm response latency since we don't have to wait for the full
      // response, we can send the sentences to the TTS model as they are detected in the stream.
      // Also since the TTS mode may it self introduce some latency, smaller chunks will ensure the user
      // Start hearing the response quickly, thus improving the overall "real-timeness".

      final readableChunkSplitter = RegExp(r'(?<=[.,;:?!])\s+|\n+');
      final potentialReadableChunks = sentenceBuffer.split(readableChunkSplitter);

      // Process all but the last, which might be incomplete.
      while (potentialReadableChunks.length > 1) {
        final sentence = potentialReadableChunks.removeAt(0).removeEmojis().trim();
        if (sentence.isNotEmpty) {
          log('Detected sentence: $sentence');
          await _generateSpeech(sentence);
        }
      }

      // The last part is kept in the buffer until the next sentence is detected or stream is done
      sentenceBuffer = potentialReadableChunks.isNotEmpty ? potentialReadableChunks.last.removeEmojis().trim() : '';
    }

    // Now the stream is done — process any remaining sentence
    if (sentenceBuffer.isNotEmpty) {
      log('Remaining sentence: $sentenceBuffer');
      await _generateSpeech(sentenceBuffer, isLastInCurrentTurn: true);
    } else {
      // Use _asyncLock to make sure we start listening to the user after the last tts task is complete.
      await _asyncLock.synchronized(() => _audioStreamPlayer.appendCallback(_startListeningToUser));
    }
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
    await _asyncLock.synchronized(() async {
      final start = DateTime.now();
      final ttsResult = await _tts.generateSpeech(text: text, voice: voice!, speed: 1.0);
      await _audioStreamPlayer.append(ttsResult.toWav(), caption: text);
      log("TTS took: ${DateTime.now().difference(start).inMilliseconds / 1000} seconds");
    });

    if (isLastInCurrentTurn) {
      // Start listening again when the last AI speech is done.
      await _audioStreamPlayer.appendCallback(_startListeningToUser);
    }
  }

  Future<void> dispose() async {
    await _userSpeechStreamSubscription?.cancel();
    await _userSpeechToTextListener.dispose();
    await _audioStreamPlayer.dispose();
    _userSpeechStreamSubscription = null;
  }
}
