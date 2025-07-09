import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:waico/core/utils/model_download_utils.dart';

class SttModel {
  /// Loading the model in GPU takes time, so we load once for the app lifecycle and use a singleton instance
  static OfflineRecognizer? _instance;

  SttModel() {
    if (_instance == null) {
      throw StateError("Model not initialized. Call SttModel.initialize first");
    }
  }

  static Future<void> initialize({required String modelPath}) async {
    if (_instance != null) {
      log("SttModel Already initialized, Skipping.");
      return;
    }
    if (!await File(modelPath).exists()) throw Exception("Model path not found: $modelPath");

    // modelPath path point to a tar.gz archive containing all the model weights and extras
    final modelDirPath = await extractModelData(modelPath);

    final encoderFile = File('$modelDirPath/encoder.int8.onnx');
    final decoderFile = File('$modelDirPath/decoder.int8.onnx');
    final joinerFile = File('$modelDirPath/joiner.int8.onnx');
    final tokensFile = File('$modelDirPath/tokens.txt');

    if (!await encoderFile.exists()) throw Exception("joiner.int8.onnx not found in $modelDirPath");
    if (!await decoderFile.exists()) throw Exception("decoder.int8.onnx not found in $modelDirPath");
    if (!await joinerFile.exists()) throw Exception("joiner.int8.onnx not found in $modelDirPath");
    if (!await tokensFile.exists()) throw Exception("tokens.txt not found in $modelDirPath");

    // Create parakeet-tdt-0.6b-v2 model configuration
    final parakeetConfig = OfflineTransducerModelConfig(
      encoder: encoderFile.path,
      decoder: decoderFile.path,
      joiner: joinerFile.path,
    );

    final modelConfig = OfflineModelConfig(
      transducer: parakeetConfig,
      tokens: tokensFile.path,
      debug: kDebugMode,
      numThreads: 1,
    );

    _instance = OfflineRecognizer(OfflineRecognizerConfig(model: modelConfig));
    log("Stt model initialized successfully");
  }

  static Future<void> dispose() async {
    _instance?.free();
    _instance = null;
  }

  /// Transcribe audio data to text
  String transcribeAudio({required Float32List samples, required int sampleRate}) {
    if (_instance == null) {
      throw StateError("Model not initialized. Call SttModel.initialize first");
    }

    final stream = _instance!.createStream();

    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _instance!.decode(stream);
      final result = _instance!.getResult(stream);

      return result.text;
    } finally {
      stream.free();
    }
  }
}
