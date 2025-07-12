import 'dart:async';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';

typedef AudioStreamPlayerState = ProcessingState;

class AudioStreamPlayer {
  final AudioPlayer _playerBackend;
  final _audioBuffer = ConcatenatingAudioSource(useLazyPreparation: true, children: []);
  final Map<int, List<FutureOr<void> Function()>> _callbackBuffer = {};
  StreamSubscription<List<int>>? _audioStreamSubscription;
  StreamSubscription<int?>? _currentIndexStreamSubscription;
  final _captionStreamController = StreamController<String?>.broadcast();

  late final AudioLoudnessMonitor _loudnessMonitor;

  bool get isPlaying => _playerBackend.playing;
  Stream<String?> get captionStream => _captionStreamController.stream;

  /// Can be used to animate the AI speech waves for example (value range 0-1)
  Stream<double> get loudnessStream => _loudnessMonitor.loudnessStream;
  AudioStreamPlayerState get state => _playerBackend.processingState;

  AudioStreamPlayer({AudioPlayer? playerBackend}) : _playerBackend = playerBackend ?? AudioPlayer() {
    _loudnessMonitor = AudioLoudnessMonitor(_playerBackend, _audioBuffer);
    _setup();
  }

  void _setup() async {
    await _playerBackend.setAudioSource(_audioBuffer);
    await _playerBackend.setShuffleModeEnabled(false);
    await _playerBackend.setLoopMode(LoopMode.off);
    await _playerBackend.play();
    await _playerBackend.setVolume(2);
    _setupCallbackListeners();
  }

  void _setupCallbackListeners() {
    _currentIndexStreamSubscription = _playerBackend.currentIndexStream.listen((currentIndex) async {
      if (currentIndex == null || _playerBackend.sequence.isNotEmpty != true) {
        return;
      }
      final currentSequence = _audioBuffer[currentIndex] as _RawAudioBytesSource?;
      _captionStreamController.add(currentSequence?.caption);

      if (_callbackBuffer.containsKey(currentIndex)) {
        final callbacks = _callbackBuffer.remove(currentIndex)!;
        for (final callback in callbacks) {
          await callback();
        }
      }
      if (_playerBackend.previousIndex != null) {
        (_audioBuffer[_playerBackend.previousIndex!] as _RawAudioBytesSource).dispose();
      }
    });
    _playerBackend.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_playerBackend.currentIndex != null && _playerBackend.nextIndex == null) {
          // Call the next callback when the current audio is completed and the buffer is empty
          // The case where there are still callbacks after the current audio is completed is less likely to happen.
          // But it can happen due to the async nature of the entire app and network latency.
          final callbacks = _callbackBuffer.remove(_playerBackend.currentIndex! + 1) ?? [];
          for (final callback in callbacks) {
            callback();
          }
          _captionStreamController.add(null);
        }
      }
    });
  }

  Future<void> play(Stream<List<int>> audioStream) async {
    if (_audioStreamSubscription != null) {
      await _audioStreamSubscription!.cancel();
      await _audioBuffer.clear();
    }
    _audioStreamSubscription = audioStream.listen(append);
  }

  Future<void> append(List<int> audioChunk, {String? caption}) async {
    if (isPlaying) {
      await _audioBuffer.add(_RawAudioBytesSource(audioChunk, caption));
    }
  }

  Future<void> appendCallback(FutureOr<void> Function() callback) async {
    if (isPlaying) {
      _callbackBuffer.putIfAbsent(_audioBuffer.length, () => []).add(callback);
    }
  }

  /// Pause the realtime player and clear the buffer
  Future<void> pause() async {
    await _playerBackend.pause();
    // It's a realtime player so we don't need to keep the buffer when paused
    // We want to start with the most recent audio when resumed
    await _audioBuffer.clear();
    _callbackBuffer.clear();
  }

  Future<void> stop() async {
    await _playerBackend.stop();
    await _audioBuffer.clear();
    _callbackBuffer.clear();
  }

  Future<void> resume() async {
    await _playerBackend.play();
  }

  Future<void> dispose() async {
    await _playerBackend.stop();
    await _audioBuffer.clear();
    await _playerBackend.dispose();
    await _audioStreamSubscription?.cancel();
    await _currentIndexStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    _currentIndexStreamSubscription = null;
    await _captionStreamController.close();
    await _loudnessMonitor.dispose();
  }
}

// Used to animate the AI speech waves for example
class AudioLoudnessMonitor {
  final AudioPlayer _player;
  final ConcatenatingAudioSource _audioBuffer;
  final StreamController<double> _loudnessController = StreamController<double>.broadcast();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  List<int>? _currentAudioData;

  Stream<double> get loudnessStream => _loudnessController.stream;

  AudioLoudnessMonitor(this._player, this._audioBuffer) {
    _setupStreams();
  }

  void _setupStreams() {
    // Listen to position changes for real-time loudness calculation
    _positionSubscription = _player.positionStream.listen((position) {
      if (_player.playing && _currentAudioData != null) {
        final loudness = _calculateLoudnessAtPosition(position);
        _loudnessController.add(loudness);
      }
    });

    // Listen to current index changes to update audio data
    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && index < _audioBuffer.length) {
        final audioSource = _audioBuffer[index] as _RawAudioBytesSource?;
        _currentAudioData = audioSource?.bytes;
      } else {
        _currentAudioData = null;
      }
    });

    // Listen to player state changes
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!state.playing) {
        _loudnessController.add(0.0);
      } else if (state.processingState == ProcessingState.completed) {
        _loudnessController.add(0.0);
        _currentAudioData = null;
      }
    });
  }

  // Return current audio loudness in the range 0-1
  double _calculateLoudnessAtPosition(Duration position) {
    if (_currentAudioData == null || _currentAudioData!.isEmpty) return 0.0;

    final duration = _player.duration;
    if (duration == null || duration.inMilliseconds == 0) {
      return _calculateLoudness(_currentAudioData!);
    }

    // Calculate which part of the audio data corresponds to current position
    final progressRatio = position.inMilliseconds / duration.inMilliseconds;
    final audioDataLength = _currentAudioData!.length;

    // Calculate a window around the current position for loudness calculation
    final windowSize = (audioDataLength * 0.05).round().clamp(500, audioDataLength); // 5% window or min 500 bytes
    final currentPosition = (audioDataLength * progressRatio).round();
    final startPos = (currentPosition - windowSize ~/ 2).clamp(0, audioDataLength - windowSize);
    final endPos = (startPos + windowSize).clamp(0, audioDataLength);

    final currentWindow = _currentAudioData!.sublist(startPos, endPos);
    return _calculateLoudness(currentWindow);
  }

  double _calculateLoudness(List<int> audioData) {
    if (audioData.isEmpty) return 0.0;

    // Calculate RMS (Root Mean Square) for loudness estimation
    // For performance, we only sample every 4th byte for estimation
    const int sampleInterval = 4;
    double sum = 0.0;
    int sampleCount = 0;

    for (int i = 0; i < audioData.length; i += sampleInterval) {
      // Convert bytes to 16-bit signed integer (assuming L16 format)
      int sample = audioData[i];
      if (i + 1 < audioData.length) {
        sample = (audioData[i + 1] << 8) | audioData[i];
        if (sample > 32767) sample -= 65536; // Convert to signed
      }

      sum += sample * sample;
      sampleCount++;
    }

    if (sampleCount == 0) return 0.0;

    final rms = math.sqrt(sum / sampleCount);
    // Normalize to 0-1 range (32767 is max value for 16-bit audio)
    return (rms / 32767.0).clamp(0.0, 1.0);
  }

  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _currentIndexSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    await _loudnessController.close();
  }
}

class _RawAudioBytesSource extends StreamAudioSource {
  List<int>? bytes;
  String? caption;

  _RawAudioBytesSource(this.bytes, [this.caption]);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes?.length ?? 0;

    return StreamAudioResponse(
      sourceLength: bytes?.length ?? 0,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes?.sublist(start, end) ?? []),
      contentType: 'audio/wav',
    );
  }

  void dispose() {
    bytes = null;
  }
}
