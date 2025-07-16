import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:isolate';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

class EmbeddingModel {
  /// Loading the model in GPU/CPU takes time, so we load once for the app lifecycle and use a singleton instance
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static ReceivePort? _receivePort;
  static int _requestCounter = 0;
  static final Map<int, Completer<dynamic>> _pendingRequests = {};

  EmbeddingModel() {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call EmbeddingModel.initialize first");
    }
  }

  static Future<void> initialize({required String modelPath}) async {
    if (_isolate != null) {
      log("EmbeddingModel Already initialized, Skipping.");
      return;
    }

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);

    // Get the send port from the isolate and handle all responses
    final completer = Completer<SendPort>();
    bool handshakeCompleted = false;

    _receivePort!.listen((message) {
      if (!handshakeCompleted && message is SendPort) {
        // Initial handshake - get the send port
        _sendPort = message;
        handshakeCompleted = true;
        completer.complete(message);
      } else if (handshakeCompleted && message is Map<String, dynamic>) {
        // Handle embedding responses
        final requestId = message['requestId'] as int;
        final pendingCompleter = _pendingRequests.remove(requestId);
        if (pendingCompleter != null) {
          if (message['error'] != null) {
            pendingCompleter.completeError(Exception(message['error']));
          } else {
            pendingCompleter.complete(message['result']);
          }
        }
      }
    });

    await completer.future;

    // Initialize the model in the isolate
    final initCompleter = Completer<void>();
    final initRequestId = _requestCounter++;
    _pendingRequests[initRequestId] = initCompleter;

    _sendPort!.send({'action': 'initialize', 'requestId': initRequestId, 'modelPath': modelPath});

    await initCompleter.future;
    log("Embedding model initialized successfully");
  }

  static Future<void> dispose() async {
    if (_isolate != null) {
      _sendPort?.send({'action': 'dispose'});
      _isolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _receivePort = null;
      _pendingRequests.clear();
    }
  }

  /// Generate embeddings for the given text
  Future<List<double>> getEmbeddings(String text) async {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call EmbeddingModel.initialize first");
    }

    final completer = Completer<List<double>>();
    final requestId = _requestCounter++;
    _pendingRequests[requestId] = completer;

    _sendPort!.send({'action': 'getEmbeddings', 'requestId': requestId, 'text': text});

    return completer.future;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    Llama? embedModel;

    receivePort.listen((message) async {
      try {
        if (message is Map<String, dynamic>) {
          final action = message['action'] as String;
          final requestId = message['requestId'] as int?;

          switch (action) {
            case 'initialize':
              try {
                final modelPath = message['modelPath'] as String;

                final modelFile = File(modelPath);
                if (!await modelFile.exists()) {
                  throw Exception("Model file not found: $modelPath");
                }

                final modelParams = ModelParams();
                final contextParams = ContextParams()
                  ..embeddings = true
                  ..nCtx = 512; // multilingual-e5-small's max context length

                embedModel = Llama(modelPath, modelParams, contextParams, SamplerParams());

                mainSendPort.send({'requestId': requestId, 'result': 'initialized'});
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'getEmbeddings':
              try {
                if (embedModel == null) {
                  throw StateError("Embedding model not initialized");
                }

                final text = message['text'] as String;
                final embeddings = embedModel!.getEmbeddings(text);

                mainSendPort.send({'requestId': requestId, 'result': embeddings});
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'dispose':
              embedModel?.dispose();
              embedModel = null;
              Isolate.exit();
          }
        }
      } catch (e) {
        log('Error in Embedding isolate: $e');
      }
    });
  }
}
