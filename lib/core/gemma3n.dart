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
  static const _reservedTokenCount = 1024;
  static const _maxTokenCount = 32768;

  Iterable<ChatMessage> _history = [];
  int _currentTokenCount = 0;
  late final InferenceModel _model;
  late final InferenceModelSession _chatSession;

  final String modelPath;
  final String loraPath;
  final double temperature;
  final int topK;
  final bool supportImageInput;

  Gemma3n({
    required this.modelPath,
    this.loraPath = '',
    this.temperature = 0.8,
    this.topK = 40,
    this.supportImageInput = true,
  });

  Future<void> initializeModel() async {
    _model = await FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.gemmaIt,
      preferredBackend: PreferredBackend.gpu,
      maxTokens: _maxTokenCount,
      supportImage: true,
      maxNumImages: 1,
    );
    _chatSession = await _model.createSession(
      temperature: temperature,
      topK: topK,
      enableVisionModality: supportImageInput,
    );
  }

  @override
  Iterable<ChatMessage> get history => _history;

  @override
  set history(Iterable<ChatMessage> history) => _history = history;

  @override
  Stream<String> sendMessageStream(String prompt, {Iterable<Attachment>? attachments}) async* {
    if (attachments?.first is! ImageFileAttachment?) {
      throw ArgumentError('Only ImageFileAttachment is supported for Gemma 3n');
    }

    final imageAttachment = attachments?.first as ImageFileAttachment?;
    await _chatSession.addQueryChunk(Message(text: prompt, imageBytes: imageAttachment?.bytes, isUser: true));

    final buffer = StringBuffer();
    await for (final token in _chatSession.getResponseAsync()) {
      buffer.write(token);
      yield token;
    }

    int responseTokens = await _chatSession.sizeInTokens(buffer.toString());
    if (imageAttachment != null) {
      // Add token count for the image attachment
      responseTokens += 256;
    }
    _currentTokenCount += responseTokens;

    if (_currentTokenCount >= (_maxTokenCount - _reservedTokenCount)) {
      throw Gemma3nMaxTokensExceededException(
        'Maximum token count exceeded. Current: $_currentTokenCount, Max: ${_maxTokenCount - _reservedTokenCount}',
      );
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
}

class Gemma3nMaxTokensExceededException implements Exception {
  final String message;

  Gemma3nMaxTokensExceededException([this.message = 'Maximum token count exceeded']);

  @override
  String toString() => 'Gemma3nMaxTokensExceededException: $message';
}
