import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:waico/core/utils/model_download_utils.dart';

class SttModel {
  /// Loading the model in GPU takes time, so we load once for the app lifecycle and use a singleton instance
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static ReceivePort? _receivePort;
  static int _requestCounter = 0;
  static final Map<int, Completer<dynamic>> _pendingRequests = {};

  SttModel() {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call SttModel.initialize first");
    }
  }
  static Future<void> initialize({required String modelPath}) async {
    if (_isolate != null) {
      log("SttModel Already initialized, Skipping.");
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
        // Handle STT responses
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
    log("Stt model initialized successfully");
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

  /// Transcribe audio data to text
  Future<String> transcribeAudio({required Float32List samples, required int sampleRate}) async {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call SttModel.initialize first");
    }

    final completer = Completer<String>();
    final requestId = _requestCounter++;
    _pendingRequests[requestId] = completer;

    _sendPort!.send({'action': 'transcribe', 'requestId': requestId, 'samples': samples, 'sampleRate': sampleRate});

    return completer.future;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) {
    initBindings();

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    OfflineRecognizer? recognizer;
    String? modelDirPath;

    receivePort.listen((message) async {
      try {
        if (message is Map<String, dynamic>) {
          final action = message['action'] as String;
          final requestId = message['requestId'] as int?;

          switch (action) {
            case 'initialize':
              try {
                final modelPath = message['modelPath'] as String;
                modelDirPath = await extractModelData(modelPath);

                final encoderFile = File('$modelDirPath/encoder.int8.onnx');
                final decoderFile = File('$modelDirPath/decoder.int8.onnx');
                final joinerFile = File('$modelDirPath/joiner.int8.onnx');
                final tokensFile = File('$modelDirPath/tokens.txt');

                if (!await encoderFile.exists()) throw Exception("encoder.int8.onnx not found in $modelDirPath");
                if (!await decoderFile.exists()) throw Exception("decoder.int8.onnx not found in $modelDirPath");
                if (!await joinerFile.exists()) throw Exception("joiner.int8.onnx not found in $modelDirPath");
                if (!await tokensFile.exists()) throw Exception("tokens.txt not found in $modelDirPath");

                final parakeetConfig = OfflineTransducerModelConfig(
                  encoder: encoderFile.path,
                  decoder: decoderFile.path,
                  joiner: joinerFile.path,
                );

                final modelConfig = OfflineModelConfig(
                  transducer: parakeetConfig,
                  tokens: tokensFile.path,
                  debug: kDebugMode,
                  // If device have more than 4 cores, use 4 threads, otherwise use all the cores
                  numThreads: min(Platform.numberOfProcessors, 4),
                  provider: Platform.isAndroid ? "xnnpack" : "cpu",
                );

                recognizer = OfflineRecognizer(OfflineRecognizerConfig(model: modelConfig));

                mainSendPort.send({'requestId': requestId, 'result': 'initialized'});
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'transcribe':
              try {
                if (recognizer == null) {
                  throw StateError("Recognizer not initialized");
                }

                final samples = message['samples'] as Float32List;
                final sampleRate = message['sampleRate'] as int;

                final stream = recognizer!.createStream();
                try {
                  stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
                  recognizer!.decode(stream);
                  final result = recognizer!.getResult(stream);
                  mainSendPort.send({'requestId': requestId, 'result': result.text});
                } finally {
                  stream.free();
                }
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'dispose':
              recognizer?.free();
              recognizer = null;
              Isolate.exit();
          }
        }
      } catch (e) {
        log('Error in STT isolate: $e');
      }
    });
  }
}
