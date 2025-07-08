import 'dart:async';
import 'dart:developer';

import 'package:record/record.dart';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'stt_model.dart';

/// Realtime audio recorder with Voice Activity Detection (VAD) to extract speech.
class UserSpeechListener {
  /// Create a speech-to-text listener that combines this speech listener with an STT model.
  /// Returns a listener that outputs transcribed text whenever the user finishes speaking.
  static UserSpeechToTextListener withTranscription({
    required SttModel sttModel,
    int sampleRate = 16_000,
    double minSilenceDuration = 0.6,
    double minSpeechDuration = 0.2,
    int windowFrameCount = 512,
    int numThreads = 1,
    AudioRecorder? audioRecorder,
  }) {
    return UserSpeechToTextListener(
      speechListener: UserSpeechListener(
        audioRecorder: audioRecorder,
        sampleRate: sampleRate,
        minSilenceDuration: minSilenceDuration,
        minSpeechDuration: minSilenceDuration,
        windowFrameCount: windowFrameCount,
        numThreads: numThreads,
      ),
      sttModel: sttModel,
    );
  }

  /// Minimum silence duration in seconds to consider speech ended.
  final double minSilenceDuration;

  /// Minimum speech duration in seconds to consider as valid speech.
  final double minSpeechDuration;

  /// Sample rate of the audio data.
  final int sampleRate;

  /// Window size (number of audio frames to be input to the VAD model at once)
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
  Future<void> initialize(String vadModelPath) async {
    if (_isInitialized) {
      log("UserSpeechListener Already initialized, skipping.");
    }
    try {
      final sileroVadConfig = sherpa_onnx.SileroVadModelConfig(
        model: vadModelPath,
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

      _vad = sherpa_onnx.VoiceActivityDetector(config: config, bufferSizeInSeconds: sileroVadConfig.maxSpeechDuration);

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

  Future<void> pause() async {
    _isPaused = true;
    _speechBuffer.clear();
    await _audioRecorder.pause();
  }

  Future<void> resume() async {
    _isPaused = false;
    await _audioRecorder.resume();
  }

  /// Process audio data from bytes.
  Future<void> _processAudioData(Uint8List audioBytes) async {
    _vad.acceptWaveform(_convertPcm16ToFloat32(audioBytes));

    while (!_vad.isEmpty() && !_isPaused) {
      _speechBuffer.add(_vad.front().samples);
      _vad.pop();
    }
    if (_speechBuffer.isNotEmpty) {
      if (_speechBuffer.length == 1) {
        _speechController.add(_speechBuffer.first);
      } else {
        _speechController.add(_mergeFloat32Lists(_speechBuffer));
      }
      _speechBuffer.clear();
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
}

/// Internal class that combines UserSpeechListener and SttModel for real-time speech-to-text transcription.
/// This class listens to speech from UserSpeechListener and transcribes it using SttModel,
/// outputting the transcribed text in a stream whenever the user finishes speaking.
///
/// Handles cases where multiple speech events are emitted during pauses by accumulating
/// transcribed text and emitting it only when no new audio events are received and speech is not buffering.
class UserSpeechToTextListener {
  final UserSpeechListener _speechListener;
  final SttModel _sttModel;
  StreamSubscription<Float32List>? _speechSubscription;

  /// Stream controller for transcribed text.
  final StreamController<String> _textController = StreamController<String>.broadcast();

  /// Buffer to accumulate transcribed text while user is speaking or pausing
  final List<String> _textBuffer = [];
  final List<Float32List> _speechBuffer = [];
  bool _isPaused = false;

  /// Flag to track if we're currently processing/transcribing
  bool _isProcessing = false;

  /// Create a new speech-to-text listener.
  UserSpeechToTextListener({required UserSpeechListener speechListener, required SttModel sttModel})
    : _speechListener = speechListener,
      _sttModel = sttModel;

  /// Start listening for speech and transcribing it to text.
  /// Returns a stream that emits transcribed text whenever the user finishes speaking.
  StreamSubscription<String> listen(
    void Function(String text) onText, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // Start listening to speech
    _speechSubscription = _speechListener.listen(
      _handleSpeechData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );

    return _textController.stream.listen(onText, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  /// Pause and return any buffered transcription
  Future<String> pause() async {
    _isPaused = true;
    _speechBuffer.clear();
    final bufferedText = _textBuffer.join(' ');
    _textBuffer.clear();
    await _speechListener.pause();
    return bufferedText;
  }

  Future<void> resume() async {
    _isPaused = false;
    await _speechListener.resume();
  }

  /// Handle incoming speech data by transcribing it and managing text buffer
  Future<void> _handleSpeechData(Float32List audioData) async {
    if (_isPaused) return;
    if (_isProcessing) {
      _speechBuffer.add(audioData);
      return;
    }

    _isProcessing = true;

    try {
      _transcribeAndBuffer(audioData);

      while (_speechBuffer.isNotEmpty && !_isPaused) {
        final speech = _speechBuffer.length == 1 ? _speechBuffer.first : _mergeFloat32Lists(_speechBuffer);
        _speechBuffer.clear();
        _transcribeAndBuffer(speech);
      }

      if (_speechListener.isBufferingSpeech) {
        // Don't do anything, when done buffering it will emit a speech event
      } else {
        await _emitBufferedText();
      }
    } catch (e, s) {
      log('Error transcribing speech', error: e, stackTrace: s);
      _textController.addError(e, s);
    } finally {
      _isProcessing = false;
    }
  }

  void _transcribeAndBuffer(Float32List audioData) {
    final transcribedText = _sttModel.transcribeAudio(samples: audioData, sampleRate: _speechListener.sampleRate);

    final cleanedText = transcribedText.trim();
    if (cleanedText.isNotEmpty) {
      _textBuffer.add(cleanedText);
    }
  }

  Future<void> _emitBufferedText() async {
    if (_textBuffer.isNotEmpty && !_isPaused) {
      // Combine all buffered text
      final combinedText = _textBuffer.join(' ');
      _textBuffer.clear();
      // Emit the combined text to the stream
      if (combinedText.isNotEmpty) {
        _textController.add(combinedText);
      }
    }
  }

  /// Check if the user is currently speaking (buffering speech).
  bool get isBufferingSpeech => _speechListener.isBufferingSpeech;

  /// Check if the listener is currently processing/transcribing audio
  bool get isProcessing => _isProcessing;

  /// Stop listening and clean up resources.
  Future<void> dispose() async {
    await _speechSubscription?.cancel();
    _speechSubscription = null;

    _textBuffer.clear();
    await _textController.close();
  }
}

Float32List _mergeFloat32Lists(List<Float32List> lists) {
  // Compute total length
  final totalLength = lists.fold(0, (sum, currentList) => sum + currentList.length);

  // Allocate one big buffer
  final merged = Float32List(totalLength);

  // Copy each list into the merged buffer
  int offset = 0;
  for (final list in lists) {
    merged.setRange(offset, offset + list.length, list);
    offset += list.length;
  }

  return merged;
}
