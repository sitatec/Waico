import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:waico/core/utils/model_download_utils.dart';

abstract class TtsModel {
  Future<TtsResult> generateSpeech({required String text, required String voice, double speed = 1.0});
}

// Premium TTS models sound natural, near human quality, but slow on most devices. Currently using Kokoro v1.0
class PremiumTtsModel implements TtsModel {
  /// Loading the model in GPU/CPU takes time, so we load once for the app lifecycle and use a singleton instance
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static ReceivePort? _receivePort;
  static int _requestCounter = 0;
  static final Map<int, Completer<TtsResult>> _pendingRequests = {};

  PremiumTtsModel() {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call TtsModel.initialize first");
    }
  }

  static Future<void> initialize({required String modelPath}) async {
    if (_isolate != null) {
      log("TtsModel Already initialized, Skipping.");
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
        // Handle TTS responses
        final requestId = message['requestId'] as int;
        final pendingCompleter = _pendingRequests.remove(requestId);
        if (pendingCompleter != null) {
          if (message['error'] != null) {
            pendingCompleter.completeError(Exception(message['error']));
          } else if (message['action'] == 'initialize') {
            // Special case for initialization - return a dummy TtsResult
            pendingCompleter.complete(TtsResult(samples: Float32List(0), sampleRate: 0));
          } else {
            final samples = message['samples'] as Float32List;
            final sampleRate = message['sampleRate'] as int;
            pendingCompleter.complete(TtsResult(samples: samples, sampleRate: sampleRate));
          }
        }
      }
    });

    await completer.future;

    // Initialize the model in the isolate
    final initCompleter = Completer<TtsResult>();
    final initRequestId = _requestCounter++;
    _pendingRequests[initRequestId] = initCompleter;

    _sendPort!.send({'action': 'initialize', 'requestId': initRequestId, 'modelPath': modelPath});

    await initCompleter.future;
    log("Tts model initialized successfully");
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

  /// Generate audio from text
  @override
  Future<TtsResult> generateSpeech({required String text, required String voice, double speed = 1.0}) async {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call TtsModel.initialize first");
    }

    final completer = Completer<TtsResult>();
    final requestId = _requestCounter++;
    _pendingRequests[requestId] = completer;

    _sendPort!.send({'action': 'generate', 'requestId': requestId, 'text': text, 'voice': voice, 'speed': speed});

    return completer.future;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) {
    initBindings();

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    OfflineTts? tts;

    receivePort.listen((message) async {
      try {
        if (message is Map<String, dynamic>) {
          final action = message['action'] as String;
          final requestId = message['requestId'] as int?;

          switch (action) {
            case 'initialize':
              try {
                final modelPath = message['modelPath'] as String;

                // modelPath path point to a tar.gz archive containing all the model weights and extras
                final modelDirPath = await extractModelData(modelPath);

                final modelFile = File('$modelDirPath/model.onnx');
                final voicesFile = File('$modelDirPath/voices.bin');
                final tokensFile = File('$modelDirPath/tokens.txt');
                final espeakDataDir = Directory('$modelDirPath/espeak-ng-data');
                final dictDir = Directory('$modelDirPath/dict');

                if (!await modelFile.exists()) throw Exception("model.onnx not found in $modelDirPath");
                if (!await voicesFile.exists()) throw Exception("voices.bin not found in $modelDirPath");
                if (!await tokensFile.exists()) throw Exception("tokens.txt not found in $modelDirPath");
                if (!await dictDir.exists()) throw Exception("dict directory not found in $modelDirPath");
                if (!await espeakDataDir.exists()) {
                  throw Exception("espeak-ng-data directory not found in $modelDirPath");
                }

                // Create kokoro model configuration
                final kokoro = OfflineTtsKokoroModelConfig(
                  model: modelFile.path,
                  voices: voicesFile.path,
                  tokens: tokensFile.path,
                  dataDir: espeakDataDir.path,
                  dictDir: dictDir.path,
                  lang: 'en-us', // TODO: get from preferences
                );

                final modelConfig = OfflineTtsModelConfig(
                  kokoro: kokoro,
                  // Although we are using nnapi, it may pick cpu backend, so we are still configuring numThread
                  // If device have more than 4 cores, use 4 threads, otherwise use all the cores
                  numThreads: min(Platform.numberOfProcessors, 4),
                  debug: kDebugMode,
                  provider: Platform.isAndroid ? "nnapi" : "coreml",
                );

                tts = OfflineTts(OfflineTtsConfig(model: modelConfig));

                mainSendPort.send({
                  'requestId': requestId,
                  'action': 'initialize',
                  'samples': Float32List(0), // Dummy response
                  'sampleRate': 0,
                });
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'generate':
              try {
                if (tts == null) {
                  throw StateError("TTS not initialized");
                }

                final text = message['text'] as String;
                final voice = message['voice'] as String;
                final speed = message['speed'] as double;

                final start = DateTime.now();
                final speakerId = _getSpeakerId(voice);
                final audio = tts!.generate(text: text, sid: speakerId, speed: speed);
                log("[InIsolate | TTS took: ${DateTime.now().difference(start).inMilliseconds / 1000} seconds");

                mainSendPort.send({'requestId': requestId, 'samples': audio.samples, 'sampleRate': audio.sampleRate});
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'dispose':
              tts?.free();
              tts = null;
              Isolate.exit();
          }
        }
      } catch (e) {
        log('Error in TTS isolate: $e');
      }
    });
  }

  static int _getSpeakerId(String voice) {
    final speakerId = _premiumVoiceToSpeakerId[voice];
    if (speakerId == null) {
      throw ArgumentError("Invalid voice: $voice. Supported voice: \n${_premiumVoiceToSpeakerId.keys}");
    }
    return speakerId;
  }
}

// Lite TTS models are faster than premium models but sound a bit robotic. Currently using Piper models.
class LiteTtsModel implements TtsModel {
  /// Loading the model in GPU/CPU takes time, so we load once for the app lifecycle and use a singleton instance
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static ReceivePort? _receivePort;
  static int _requestCounter = 0;
  static final Map<int, Completer<TtsResult>> _pendingRequests = {};

  LiteTtsModel() {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call LiteTtsModel.initialize first");
    }
  }

  static Future<void> initialize({required String modelPath}) async {
    if (_isolate != null) {
      log("LiteTtsModel Already initialized, Skipping.");
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
        // Handle TTS responses
        final requestId = message['requestId'] as int;
        final pendingCompleter = _pendingRequests.remove(requestId);
        if (pendingCompleter != null) {
          if (message['error'] != null) {
            pendingCompleter.completeError(Exception(message['error']));
          } else if (message['action'] == 'initialize') {
            // Special case for initialization - return a dummy TtsResult
            pendingCompleter.complete(TtsResult(samples: Float32List(0), sampleRate: 0));
          } else {
            final samples = message['samples'] as Float32List;
            final sampleRate = message['sampleRate'] as int;
            pendingCompleter.complete(TtsResult(samples: samples, sampleRate: sampleRate));
          }
        }
      }
    });

    await completer.future;

    // Initialize the model in the isolate
    final initCompleter = Completer<TtsResult>();
    final initRequestId = _requestCounter++;
    _pendingRequests[initRequestId] = initCompleter;

    _sendPort!.send({'action': 'initialize', 'requestId': initRequestId, 'modelPath': modelPath});

    await initCompleter.future;
    log("Lite TTS model initialized successfully");
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

  /// Generate audio from text
  @override
  Future<TtsResult> generateSpeech({
    required String text,
    double speed = 1.0,
    String voice = 'not_supported_for_lite_models',
  }) async {
    if (_isolate == null || _sendPort == null) {
      throw StateError("Model not initialized. Call LiteTtsModel.initialize first");
    }

    final completer = Completer<TtsResult>();
    final requestId = _requestCounter++;
    _pendingRequests[requestId] = completer;

    _sendPort!.send({'action': 'generate', 'requestId': requestId, 'text': text, 'speed': speed});

    return completer.future;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) {
    initBindings();

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    OfflineTts? tts;

    receivePort.listen((message) async {
      try {
        if (message is Map<String, dynamic>) {
          final action = message['action'] as String;
          final requestId = message['requestId'] as int?;

          switch (action) {
            case 'initialize':
              try {
                final modelPath = message['modelPath'] as String;

                // modelPath path point to a tar.gz archive containing all the model weights and extras
                final modelDirPath = await extractModelData(modelPath);

                final modelFile = File('$modelDirPath/model.onnx');
                final tokensFile = File('$modelDirPath/tokens.txt');
                final espeakDataDir = Directory('$modelDirPath/espeak-ng-data');

                if (!await modelFile.exists()) throw Exception("model.onnx not found in $modelDirPath");
                if (!await tokensFile.exists()) throw Exception("tokens.txt not found in $modelDirPath");
                if (!await espeakDataDir.exists()) {
                  throw Exception("espeak-ng-data directory not found in $modelDirPath");
                }

                // Create VITS model configuration for Lite TTS
                final vits = OfflineTtsVitsModelConfig(
                  model: modelPath,
                  tokens: tokensFile.path,
                  dataDir: espeakDataDir.path,
                  lengthScale: 1.0, // Will be adjusted per request based on speed
                );

                final modelConfig = OfflineTtsModelConfig(
                  vits: vits,
                  // If device have more than 4 cores, use 4 threads, otherwise use all the cores
                  numThreads: min(Platform.numberOfProcessors, 4),
                  provider: Platform.isAndroid ? "xnnpack" : "cpu",
                  debug: kDebugMode,
                );

                final config = OfflineTtsConfig(model: modelConfig, maxNumSenetences: 1);

                tts = OfflineTts(config);

                mainSendPort.send({
                  'requestId': requestId,
                  'action': 'initialize',
                  'samples': Float32List(0), // Dummy response
                  'sampleRate': 0,
                });
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'generate':
              try {
                if (tts == null) {
                  throw StateError("TTS not initialized");
                }

                final text = message['text'] as String;
                final speed = message['speed'] as double;

                final start = DateTime.now();
                // For Lite TTS, always use sid = 0 since it doesn't support multiple voices
                final audio = tts!.generate(text: text, sid: 0, speed: speed);
                log("[InIsolate | Lite TTS took: ${DateTime.now().difference(start).inMilliseconds / 1000} seconds");

                mainSendPort.send({'requestId': requestId, 'samples': audio.samples, 'sampleRate': audio.sampleRate});
              } catch (e) {
                mainSendPort.send({'requestId': requestId, 'error': e.toString()});
              }
              break;

            case 'dispose':
              tts?.free();
              tts = null;
              Isolate.exit();
          }
        }
      } catch (e) {
        log('Error in Lite TTS isolate: $e');
      }
    });
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

final Map<String, int> _premiumVoiceToSpeakerId = {
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
