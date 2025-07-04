import 'dart:async';
import 'dart:developer';

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show ImageFileAttachment, LlmProvider;
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart' show Kokoro;
import 'package:stts/stts.dart';

class VoiceChatPipeline {
  final LlmProvider llm;
  final Kokoro tts;
  final Stt stt;
  final List<XFile> _pendingImages = [];
  final String voice;
  StreamSubscription? _sttStreamSubscription;

  VoiceChatPipeline({required this.llm, required this.tts, required this.voice, Stt? stt}) : stt = stt ?? Stt();

  Future<void> startChat() async {
    await stt.hasPermission();
    _sttStreamSubscription = stt.onResultChanged.listen(_onSttResultReceived);
    await stt.start();
  }

  Future<void> endChat() async {
    await stt.stop();
    _sttStreamSubscription?.cancel();
  }

  void addImages(List<XFile> imageFiles) {
    _pendingImages.addAll(imageFiles);
  }

  Future<void> _onSttResultReceived(SttRecognition result) async {
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
    final ttsResult = await tts.createTTS(
      text: text,
      voice: voice,
      // Kokoro voices are in this format 12_name where 1 is the language code's fist letter 2 is the gender's
      lang: _kokoroToStandardLangCode[voice[0]]!,
    );
    // TODO play audio
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
