import 'dart:developer';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';

class Gemma3n extends LlmProvider with ChangeNotifier {
  /// The number of reserved tokens for Gemma 3n.
  ///
  /// If the current token count is >= _maxTokenCount - _reservedTokenCount, the chat history
  /// will be reset to avoid exceeding the model context window.
  static const _reservedTokenCount = 500;
  static const _maxTokenCount = 4096;

  List<ChatMessage> _history = [];
  int _currentTokenCount = 0;
  late final InferenceModel _model;
  late final InferenceModelSession _chatSession;

  final String loraPath;
  final double temperature;
  final int topK;
  final double topP;
  final bool supportImageInput;

  Gemma3n({
    this.loraPath = '',
    this.temperature = 1.0,
    this.topK = 64,
    this.topP = 0.95,
    this.supportImageInput = true,
  });

  Future<void> initializeModel() async {
    _model = await FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.gemmaIt,
      preferredBackend: PreferredBackend.gpu,
      maxTokens: _maxTokenCount,
      supportImage: supportImageInput,
    );
    _chatSession = await _model.createSession(
      temperature: temperature,
      topK: topK,
      topP: topP,
      enableVisionModality: supportImageInput,
    );
  }

  @override
  Iterable<ChatMessage> get history => _history;

  @override
  set history(Iterable<ChatMessage> history) {
    _history.clear();
    _history.addAll(history);
    // _currentTokenCount =  TODO
    notifyListeners();
  }

  @override
  Stream<String> sendMessageStream(String prompt, {Iterable<Attachment> attachments = const []}) async* {
    _history.add(ChatMessage(text: prompt, attachments: attachments, origin: MessageOrigin.user));

    List<ImageFileAttachment>? imageAttachments;
    if (attachments.isNotEmpty) {
      if (attachments is! List<ImageFileAttachment>) {
        throw ArgumentError('Only a list of ImageFileAttachment is supported');
      }

      imageAttachments = attachments;
    }

    try {
      if ((imageAttachments?.length ?? 0) > 1) {
        for (final attachment in imageAttachments!) {
          await _chatSession.addQueryChunk(Message.imageOnly(imageBytes: attachment.bytes, isUser: true));
        }
        await _chatSession.addQueryChunk(Message.text(text: prompt, isUser: true));
      } else {
        await _chatSession.addQueryChunk(
          Message(text: prompt, imageBytes: imageAttachments?.first.bytes, isUser: true),
        );
      }
      final llmResponse = ChatMessage.llm();
      _history.add(llmResponse);
      await for (final responseChunk in _chatSession.getResponseAsync()) {
        llmResponse.text = (llmResponse.text ?? '') + responseChunk;
        yield responseChunk;
      }

      int responseTokens = await _chatSession.sizeInTokens(llmResponse.text!);
      if (imageAttachments?.isNotEmpty == true) {
        // Add token count for the image attachment
        responseTokens += 256 * imageAttachments!.length; // Assuming 256 tokens per image
      }
      _currentTokenCount += responseTokens;
    } catch (e, stackTrace) {
      log('Error during message generation', error: e, stackTrace: stackTrace);
      throw Exception('Failed to generate response: $e');
    }
  }

  @override
  Stream<String> generateStream(String prompt, {Iterable<Attachment>? attachments}) async* {
    if (attachments?.first is! ImageFileAttachment?) {
      throw ArgumentError('Only ImageFileAttachment is supported for Gemma 3n');
    }
    final imageAttachment = attachments?.first as ImageFileAttachment?;
    // This is for onetime generation with no history.
    final newSession = await _model.createSession(
      temperature: temperature,
      topK: topK,
      enableVisionModality: supportImageInput,
    );
    await newSession.addQueryChunk(Message(text: prompt, imageBytes: imageAttachment?.bytes, isUser: true));
    yield* newSession.getResponseAsync();
  }

  @override
  Future<void> dispose() async {
    await _chatSession.close();
    await _model.close();
    _history = [];
    super.dispose();
  }
}

class Gemma3nMaxTokensExceededException implements Exception {
  final String message;

  Gemma3nMaxTokensExceededException([this.message = 'Maximum token count exceeded']);

  @override
  String toString() => 'Gemma3nMaxTokensExceededException: $message';
}
