import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart' show extractFileToDisk;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart';

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

    // The modelPath is a compressed archive containing all the whisper model data
    final modelBaseDir = modelPath.replaceAll(".tar.bz2", "");
    if (!await Directory(modelBaseDir).exists()) {
      await extractFileToDisk(modelPath, modelBaseDir);
    }

    final encoderFile = File('$modelBaseDir/encoder.onnx');
    final decoderFile = File('$modelBaseDir/decoder.onnx');
    final tokensFile = File('$modelBaseDir/tokens.txt');

    if (!await encoderFile.exists()) throw Exception("encoder.onnx not found in $modelBaseDir");
    if (!await decoderFile.exists()) throw Exception("decoder.onnx not found in $modelBaseDir");
    if (!await tokensFile.exists()) throw Exception("tokens.txt not found in $modelBaseDir");

    // Create whisper model configuration
    final whisper = OfflineWhisperModelConfig(encoder: encoderFile.path, decoder: decoderFile.path);

    final modelConfig = OfflineModelConfig(
      whisper: whisper,
      tokens: tokensFile.path,
      modelType: 'whisper',
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
