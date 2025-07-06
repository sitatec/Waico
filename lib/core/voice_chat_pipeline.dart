import 'dart:async';
import 'dart:developer';

import 'package:audio_session/audio_session.dart' show AudioSession, AudioSessionConfiguration;
import 'package:cross_file/cross_file.dart' show XFile;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show ImageFileAttachment, LlmProvider;
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart' show Kokoro;
import 'package:stts/stts.dart';
import 'package:waico/core/audio_stream_player.dart';
import 'package:waico/core/kokoro_model.dart';

class VoiceChatPipeline {
  final LlmProvider llm;
  final Kokoro _tts;
  final Stt _stt;
  final List<XFile> _pendingImages = [];
  String? voice;
  final AudioStreamPlayer _audioStreamPlayer;
  StreamSubscription? _sttStreamSubscription;
  StreamSubscription? _sttStateSubscription;

  /// Can be used to animate the AI speech waves widget
  Stream<double> get aiSpeechLoudnessStream => _audioStreamPlayer.loudnessStream;

  VoiceChatPipeline({required this.llm, Kokoro? tts, Stt? stt, AudioStreamPlayer? audioStreamPlayer})
    : _stt = stt ?? Stt(),
      _tts = tts ?? KokoroModel.instance,
      _audioStreamPlayer = audioStreamPlayer ?? AudioStreamPlayer();

  Future<void> startChat({required String voice}) async {
    this.voice = voice;

    await _stt.hasPermission();
    _sttStreamSubscription = _stt.onResultChanged.listen(_onSttResultReceived);
    _sttStateSubscription = _stt.onStateChanged.listen((newState) {
      log("New STT state: $newState");
    });
    await _stt.start();
    await _audioStreamPlayer.resume();

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
  }

  Future<void> endChat() async {
    await _sttStreamSubscription?.cancel();
    await _stt.stop();
    await _audioStreamPlayer.stop();
  }

  Future<void> dispose() async {
    await _sttStreamSubscription?.cancel();
    await _stt.dispose();
    await _audioStreamPlayer.dispose();
    await _sttStateSubscription?.cancel();
    _sttStateSubscription = null;
    _sttStreamSubscription = null;
  }

  void addImages(List<XFile> imageFiles) {
    _pendingImages.addAll(imageFiles);
  }

  Future<void> _onSttResultReceived(SttRecognition result) async {
    // TODO: Check for interruption and notify the user that interruption is not supported yet, they need to wait for
    // the ai speech to finish

    if (result.isFinal) {
      final attachments = await _pendingImages.map((imageFile) => ImageFileAttachment.fromFile(imageFile)).wait;
      _pendingImages.clear();

      String sentenceBuffer = "";
      llm
          .sendMessageStream(result.text, attachments: attachments)
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
                  _queueTTS(sentence);
                }
              }

              // The last part is kept in the buffer until the next sentence is detected or stream is done
              sentenceBuffer = potentialSentences.last;
            },
            onDone: () {
              // Process remaining text
              log('Remaining sentence: $sentenceBuffer');
              _queueTTS(sentenceBuffer);
            },
          );
    }
  }

  Future<void> _queueTTS(String text) async {
    final ttsResult = await _tts.createTTS(
      text: text,
      voice: voice,
      trim: false,
      // Kokoro voices are in this format 12_name where 1 is the language code's fist letter 2 is the gender's
      lang: _kokoroToStandardLangCode[voice![0]]!,
    );

    await _audioStreamPlayer.append(ttsResult.toWav(), caption: text);
  }
}

const _kokoroToStandardLangCode = {
  "a": "en-us",
  "b": "en-gb",
  "e": "es",
  "f": "fr-fr",
  "h": "hi",
  "i": "it",
  "p": "pt-br",
  "j": "ja",
  "z": "zh",
};
