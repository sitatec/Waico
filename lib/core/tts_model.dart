import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:waico/core/utils/model_download_utils.dart';

class TtsModel {
  /// Loading the model in GPU takes time, so we load once for the app lifecycle and use a singleton instance
  static OfflineTts? _instance;

  TtsModel() {
    if (_instance == null) {
      throw StateError("Model not initialized. Call TtsModel.initialize first");
    }
  }

  static Future<void> initialize({required String modelPath}) async {
    if (_instance != null) {
      log("TtsModel Already initialized, Skipping.");
      return;
    }
    if (!await File(modelPath).exists()) throw Exception("Model path not found: $modelPath");

    // modelPath path point to a tar.gz archive containing all the model weights and extras
    final modelDirPath = extractModelData(modelPath);

    final modelFile = File('$modelDirPath/model.onnx');
    final voicesFile = File('$modelDirPath/voices.bin');
    final tokensFile = File('$modelDirPath/tokens.txt');
    final espeakDataDir = Directory('$modelDirPath/espeak-ng-data');
    final dictDir = Directory('$modelDirPath/dict');

    if (!await modelFile.exists()) throw Exception("model.onnx not found in $modelDirPath");
    if (!await voicesFile.exists()) throw Exception("voices.bin not found in $modelDirPath");
    if (!await tokensFile.exists()) throw Exception("tokens.txt not found in $modelDirPath");
    if (!await espeakDataDir.exists()) throw Exception("espeak-ng-data directory not found in $modelDirPath");
    if (!await dictDir.exists()) throw Exception("dict directory not found in $modelDirPath");

    // Create kokoro model configuration
    final kokoro = OfflineTtsKokoroModelConfig(
      model: modelFile.path,
      voices: voicesFile.path,
      tokens: tokensFile.path,
      dataDir: espeakDataDir.path,
      dictDir: dictDir.path,
      lang: 'en-us', // TODO: get from preferences
    );

    final modelConfig = OfflineTtsModelConfig(kokoro: kokoro, numThreads: 1, debug: kDebugMode);

    _instance = OfflineTts(OfflineTtsConfig(model: modelConfig));
    log("Tts model initialized successfully");
  }

  static Future<void> dispose() async {
    _instance?.free();
    _instance = null;
  }

  /// Generate TTS audio from text
  TtsResult generateSpeech({required String text, required String voice, double speed = 1.0}) {
    if (_instance == null) {
      throw StateError("Model not initialized. Call TtsModel.initialize first");
    }
    final audio = _instance!.generate(text: text, sid: _getSpeakerId(voice), speed: speed);
    return TtsResult(samples: audio.samples, sampleRate: audio.sampleRate);
  }

  int _getSpeakerId(String voice) {
    final speakerId = _voiceToSpeakerId[voice];
    if (speakerId == null) {
      throw ArgumentError("Invalid voice: $voice. Supported voice: \n${_voiceToSpeakerId.keys}");
    }
    return speakerId;
  }
}

/// Result class for TTS generation
class TtsResult {
  final Float32List samples;
  final int sampleRate;

  TtsResult({required this.samples, required this.sampleRate});

  /// Convert float samples to 16-bit PCM
  List<int> toInt16PCM() {
    final pcm = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      // Clamp to [-1, 1] and convert to 16-bit
      final clamped = samples[i].clamp(-1.0, 1.0);
      pcm[i] = (clamped * 32767).round();
    }
    return pcm.toList();
  }

  /// Helper to write a minimal WAV file from PCM data
  List<int> toWav() {
    final pcm = toInt16PCM();
    final int byteRate = sampleRate * 2;
    const int blockAlign = 2;
    final int dataLength = pcm.length * 2;
    final int fileLength = 44 + dataLength;
    final bytes = BytesBuilder();

    // RIFF header
    bytes.add([0x52, 0x49, 0x46, 0x46]); // 'RIFF'
    bytes.add(_intToBytes(fileLength - 8, 4));
    bytes.add([0x57, 0x41, 0x56, 0x45]); // 'WAVE'

    // Format chunk
    bytes.add([0x66, 0x6d, 0x74, 0x20]); // 'fmt '
    bytes.add(_intToBytes(16, 4)); // PCM chunk size
    bytes.add(_intToBytes(1, 2)); // Audio format (1 = PCM)
    bytes.add(_intToBytes(1, 2)); // Num channels
    bytes.add(_intToBytes(sampleRate, 4));
    bytes.add(_intToBytes(byteRate, 4));
    bytes.add(_intToBytes(blockAlign, 2));
    bytes.add(_intToBytes(16, 2)); // Bits per sample

    // Data chunk
    bytes.add([0x64, 0x61, 0x74, 0x61]); // 'data'
    bytes.add(_intToBytes(dataLength, 4));

    // Convert 16-bit PCM to bytes
    for (int sample in pcm) {
      bytes.add([sample & 0xFF, (sample >> 8) & 0xFF]);
    }

    return bytes.takeBytes();
  }

  List<int> _intToBytes(int value, int bytes) {
    final result = <int>[];
    for (var i = 0; i < bytes; i++) {
      result.add((value >> (8 * i)) & 0xFF);
    }
    return result;
  }
}

final Map<String, int> _voiceToSpeakerId = {
  'af_alloy': 0,
  'af_aoede': 1,
  'af_bella': 2,
  'af_heart': 3,
  'af_jessica': 4,
  'af_kore': 5,
  'af_nicole': 6,
  'af_nova': 7,
  'af_river': 8,
  'af_sarah': 9,
  'af_sky': 10,
  'am_adam': 11,
  'am_echo': 12,
  'am_eric': 13,
  'am_fenrir': 14,
  'am_liam': 15,
  'am_michael': 16,
  'am_onyx': 17,
  'am_puck': 18,
  'am_santa': 19,
  'bf_alice': 20,
  'bf_emma': 21,
  'bf_isabella': 22,
  'bf_lily': 23,
  'bm_daniel': 24,
  'bm_fable': 25,
  'bm_george': 26,
  'bm_lewis': 27,
  'ef_dora': 28,
  'em_alex': 29,
  'ff_siwis': 30,
  'hf_alpha': 31,
  'hf_beta': 32,
  'hm_omega': 33,
  'hm_psi': 34,
  'if_sara': 35,
  'im_nicola': 36,
  'jf_alpha': 37,
  'jf_gongitsune': 38,
  'jf_nezumi': 39,
  'jf_tebukuro': 40,
  'jm_kumo': 41,
  'pf_dora': 42,
  'pm_alex': 43,
  'pm_santa': 44,
  'zf_xiaobei': 45,
  'zf_xiaoni': 46,
  'zf_xiaoxiao': 47,
  'zf_xiaoyi': 48,
  'zm_yunjian': 49,
  'zm_yunxi': 50,
  'zm_yunxia': 51,
  'zm_yunyang': 52,
};
