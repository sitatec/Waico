import 'dart:developer';
import 'dart:typed_data';

import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

class KokoroModel {
  static Kokoro? _instance;

  static Kokoro get instance {
    if (_instance == null) {
      throw StateError("Model not initialized. Call KokoroModel.initialize first");
    }

    return _instance!;
  }

  static Future<void> initialize({required String modelPath, required String voicesPath}) async {
    if (_instance != null) {
      log("Kokoro Already initialized, Skipping.");
      return;
    }

    _instance = Kokoro(KokoroConfig(modelPath: modelPath, voicesPath: voicesPath));
    await _instance!.initialize();
  }

  static Future<void> dispose() async {
    await _instance?.dispose();
  }
}

extension KokoroUtils on TtsResult {
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
    bytes.add(pcm.buffer.asUint8List());

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
