import 'dart:async';
import 'dart:developer' show log;

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show ImageFileAttachment;
import 'package:synchronized/synchronized.dart';
import 'package:waico/core/ai_agent/ai_agent.dart';
import 'package:waico/core/services/audio_stream_player.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/core/services/user_speech_listener.dart';
import 'package:waico/core/utils/string_utils.dart';
import 'package:waico/generated/locale_keys.g.dart';

class VoiceChatPipeline {
  final AiAgent agent;
  final UserSpeechToTextListener _userSpeechToTextListener;
  final TtsModel _tts;
  final List<XFile> _pendingImages = [];
  String? voice;
  double? speechSpeed;
  final AudioStreamPlayer _audioStreamPlayer;
  StreamSubscription? _userSpeechStreamSubscription;
  bool _hasChatEnded = false;
  bool _isBusy = false;
  bool _isOnHold = false;
  String _onHoldBuffer = "";
  final _aiSpeechState = StreamController<String>.broadcast();
  // Used wait until the current TTS task complete before starting the next one.
  final _asyncLock = Lock();

  /// Can be used to animate the AI speech waves widget (value range 0-1)
  Stream<double> get aiSpeechLoudnessStream => _audioStreamPlayer.loudnessStream;

  /// Stream of AI speech state (e.g. "thinking", "speaking", "listening", "Remembering", "Using x tool").
  Stream<String> get aiSpeechStateStream => _aiSpeechState.stream;

  /// `true` if the pipeline is currently busy (typically when processing a message from use or system).
  /// This can be used to prevent conflicts, or overload the AI agent with many messages, and in an unordered manner.
  bool get isBusy => _isBusy;

  VoiceChatPipeline({
    required this.agent,
    UserSpeechToTextListener? userSpeechToTextListener,
    TtsModel? tts,
    AudioStreamPlayer? audioStreamPlayer,
  }) : _tts = tts ?? TtsModelFactory.instance,
       _audioStreamPlayer = audioStreamPlayer ?? AudioStreamPlayer(),
       _userSpeechToTextListener = userSpeechToTextListener ?? UserSpeechListener.withTranscription();

  Future<void> startChat({required String voice, double speechSpeed = 1.0}) async {
    // TODO: Add interruption support (user can interrupt ai). On android cancelling generation is supported by mediapipe
    // But not in flutter yet. On IOS we interrupt but with delay, model generation is generally faster then the synthesized
    // audio, so we can cancel the speech as soon as the model finish generation until IOS support cancelling generation.
    this.voice = voice;
    this.speechSpeed = speechSpeed;
    _hasChatEnded = false;
    await _userSpeechToTextListener.initialize();
    _userSpeechStreamSubscription = _userSpeechToTextListener.listen(_onMessageReceived);
    await startListeningToUser();
  }

  /// Sends a system message to the AI agent. This is not the same as a system prompt
  /// It is just a message from the system/app to the AI agent.
  ///
  /// Returns `true` if the message was successfully added, `false` if nor (chat has ended or the pipeline is busy)
  Future<bool> addSystemMessage(String message) async {
    if (_hasChatEnded || isBusy) return false;

    _onMessageReceived(message);
    return true;
  }

  /// Adds a system speech to the chat. For now it just generates the speech and plays it.
  /// This is not sent to the AI agent.
  ///
  /// Returns `true` if the speech was successfully added, `false` if not (chat has ended or the pipeline is busy)
  Future<bool> addSystemSpeech(String text) async {
    if (_hasChatEnded || isBusy) return false;
    final isAudioPaused = !_audioStreamPlayer.isPlaying;
    if (isAudioPaused) _audioStreamPlayer.resume();
    await _generateSpeech(text);
    // If the audio was paused before, we pause it again after the speech is completed.
    if (isAudioPaused) _audioStreamPlayer.appendCallback(_audioStreamPlayer.pause);
    return true;
  }

  /// Enter "on hold" state, which means the AI is waiting for the user to finish their speech.
  void hold() {
    _isOnHold = true;
  }

  /// Exit "on hold" state, which means the AI is ready to process the next user message.
  Future<void> unHold() async {
    _isOnHold = false;
    if (_onHoldBuffer.isNotEmpty) {
      final userMessage = _onHoldBuffer;
      _onHoldBuffer = "";
      await _onMessageReceived(userMessage);
    }
  }

  Future<void> endChat() async {
    if (_hasChatEnded) return;
    _hasChatEnded = true;
    await _userSpeechStreamSubscription?.cancel();
    await stopListeningToUser();
  }

  Future<void> _onMessageReceived(String text) async {
    // TODO: Check for interruption and notify the user that interruption is not supported yet, they need to wait for
    // the ai speech to finish
    if (_hasChatEnded) return;
    if (_isOnHold) {
      _onHoldBuffer += text;
      return;
    }
    _enterBusyState();

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
        // Remove emojis and "*#" markdown syntax
        final sentence = potentialReadableChunks.removeAt(0).removeEmojis().replaceAll(RegExp('[*#]'), '').trim();
        if (sentence.isNotEmpty) {
          log('Detected sentence: $sentence | length: ${sentence.length}');
          await _generateSpeech(sentence);
        }
      }

      // The last part is kept in the buffer until the next sentence is detected or stream is done
      sentenceBuffer = potentialReadableChunks.isNotEmpty ? potentialReadableChunks.last.removeEmojis().trim() : '';
    }

    // Now the stream is done — process any remaining sentence
    if (sentenceBuffer.isNotEmpty) {
      log('Remaining sentence: $sentenceBuffer | length: ${sentenceBuffer.length}');
      await _generateSpeech(sentenceBuffer, isLastInCurrentTurn: true);
    } else {
      // Use _asyncLock to make sure we start listening to the user after the last tts task is complete.
      await _asyncLock.synchronized(() => _audioStreamPlayer.appendCallback(_exitBusyState));
    }
  }

  void addImages(List<XFile> imageFiles) {
    _pendingImages.addAll(imageFiles);
  }

  Future<void> startListeningToUser() async {
    await _audioStreamPlayer.pause();
    await _userSpeechToTextListener.resume();
    _aiSpeechState.add(LocaleKeys.voice_chat_listening.tr());
  }

  Future<void> stopListeningToUser() async {
    await _userSpeechToTextListener.pause();
    await _audioStreamPlayer.resume();
  }

  Future<void> _enterBusyState() async {
    _isBusy = true;
    // Stop listening to the user since interruption is not supported yet.
    await stopListeningToUser();
    // For now only "Speaking" state is emitted, when the AI is generating.
    _aiSpeechState.add(LocaleKeys.voice_chat_speaking.tr());
  }

  Future<void> _exitBusyState() async {
    _isBusy = false;
    await startListeningToUser();
  }

  /// Generate and queue TTS audio
  Future<void> _generateSpeech(String text, {bool isLastInCurrentTurn = false}) async {
    await _asyncLock.synchronized(() async {
      final start = DateTime.now();
      final ttsResult = await _tts.generateSpeech(text: text, voice: voice, speed: speechSpeed ?? 1.0);
      await _audioStreamPlayer.append(ttsResult.toWav(), caption: text);
      log("TTS took: ${DateTime.now().difference(start).inMilliseconds / 1000} seconds");
    });

    if (isLastInCurrentTurn) {
      await _audioStreamPlayer.appendCallback(_exitBusyState);
    }
  }

  Future<void> dispose() async {
    await _userSpeechStreamSubscription?.cancel();
    await _userSpeechToTextListener.dispose();
    await _audioStreamPlayer.dispose();
    _userSpeechStreamSubscription = null;
  }
}
