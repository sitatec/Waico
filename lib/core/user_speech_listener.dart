import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Voice Activity Detection (VAD) listener for real-time audio processing.
/// Uses SherpaOnnx for speech detection and streams detected speech segments.
class UserSpeechListener {
  /// Minimum silence duration in seconds to consider speech ended.
  final double minSilenceDuration;

  /// Minimum speech duration in seconds to consider as valid speech.
  final double minSpeechDuration;

  /// Sample rate of the audio data.
  final int sampleRate;

  /// Window size for VAD processing.
  final int windowFrameCount;

  /// Number of threads for VAD processing.
  final int numThreads;

  final AudioRecorder _audioRecorder;
  late final sherpa_onnx.VoiceActivityDetector _vad;
  bool _isInitialized = false;
  bool _isPaused = false;

  final List<Float32List> _speechBuffer = [];

  /// Stream controller for complete speech utterances.
  final StreamController<Float32List> _speechController = StreamController<Float32List>.broadcast();

  StreamSubscription? _recordingStreamSubscription;

  /// Create a new speech listener.
  UserSpeechListener({
    this.sampleRate = 16_000,
    this.minSilenceDuration = 0.6,
    this.minSpeechDuration = 0.2,
    this.windowFrameCount = 512,
    this.numThreads = 1,
    AudioRecorder? audioRecorder,
  }) : _audioRecorder = audioRecorder ?? AudioRecorder();

  Future<bool> get hasRecordingPermission => _audioRecorder.hasPermission();

  /// User started speaking but not done yet, so the current speech is not emitted to the stream yet, it is buffering.
  bool get isBufferingSpeech => _vad.isDetected();

  /// Initialize the VAD with the given model path.
  Future<void> initialize(String modelPath) async {
    if (_isInitialized) {
      log("UserSpeechListener Already initialized, skipping.");
    }
    try {
      final sileroVadConfig = sherpa_onnx.SileroVadModelConfig(
        model: modelPath,
        minSilenceDuration: minSilenceDuration,
        minSpeechDuration: minSpeechDuration,
        windowSize: windowFrameCount,
        maxSpeechDuration: 60,
      );

      final config = sherpa_onnx.VadModelConfig(
        sileroVad: sileroVadConfig,
        numThreads: numThreads,
        debug: kDebugMode,
        sampleRate: sampleRate,
      );

      _vad = sherpa_onnx.VoiceActivityDetector(config: config, bufferSizeInSeconds: 60);

      _isInitialized = true;
    } catch (e, s) {
      log('VAD model initialization failed: $e', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Release the VAD listener resources.
  Future<void> dispose() async {
    _vad.free();
    _isInitialized = false;
    await _speechController.close();
    await _recordingStreamSubscription?.cancel();
  }

  /// Listen to complete speech utterances.
  /// Returns a stream that emits complete audio data when speech ends (either naturally or manually).
  StreamSubscription<Float32List> listen(
    void Function(Float32List audioData) onSpeech, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    assert(_isInitialized, "Uninitialized. Call initialize first");

    if (_recordingStreamSubscription != null) {
      // Already recording
      return _speechController.stream.listen(onSpeech, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    }

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      echoCancel: true,
      autoGain: true,
      noiseSuppress: true,
      androidConfig: AndroidRecordConfig(
        audioManagerMode: AudioManagerMode.modeInCommunication,
        audioSource: AndroidAudioSource.voiceCommunication,
        setSpeakerphoneOn: true,
      ),
    );

    _audioRecorder.startStream(config).then((stream) {
      _recordingStreamSubscription = stream.listen((data) async {
        if (!_isPaused) {
          await _processAudioData(data);
        }
      });
    });

    return _speechController.stream.listen(onSpeech, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  /// Process audio data from bytes.
  Future<void> _processAudioData(Uint8List audioBytes) async {
    _vad.acceptWaveform(_convertPcm16ToFloat32(audioBytes));

    while (!_vad.isEmpty()) {
      _speechBuffer.add(_vad.front().samples);
      _vad.pop();
    }
    if (_speechBuffer.isNotEmpty) {
      _speechController.add(_mergeFloat32Lists(_speechBuffer));
    }
  }

  Float32List _convertPcm16ToFloat32(Uint8List pcmBytes) {
    final int sampleCount = pcmBytes.length ~/ 2;
    final Float32List floatSamples = Float32List(sampleCount);
    final ByteData byteData = ByteData.sublistView(pcmBytes);

    for (int i = 0; i < sampleCount; i++) {
      final int intSample = byteData.getInt16(i * 2, Endian.little);
      floatSamples[i] = intSample / 32768.0;
    }

    return floatSamples;
  }

  Float32List _mergeFloat32Lists(List<Float32List> lists) {
    // 1. Compute total length
    final totalLength = lists.fold(0, (sum, currentList) => sum + currentList.length);

    // 2. Allocate one big buffer
    final merged = Float32List(totalLength);

    // 3. Copy each list into the merged buffer
    int offset = 0;
    for (final list in lists) {
      merged.setRange(offset, offset + list.length, list);
      offset += list.length;
    }

    return merged;
  }
}
