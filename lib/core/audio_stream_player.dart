import 'dart:async';

import 'package:just_audio/just_audio.dart';

typedef AudioStreamPlayerState = ProcessingState;

class AudioStreamPlayer {
  final AudioPlayer _playerBackend;
  final _audioBuffer = ConcatenatingAudioSource(useLazyPreparation: true, children: []);
  final Map<int, List<FutureOr<void> Function()>> _callbackBuffer = {};
  StreamSubscription<List<int>>? _audioStreamSubscription;
  StreamSubscription<int?>? _currentIndexStreamSubscription;
  final _captionStreamController = StreamController<String?>.broadcast();

  bool get isPlaying => _playerBackend.playing;
  Stream<String?> get captionStream => _captionStreamController.stream;
  AudioStreamPlayerState get state => _playerBackend.processingState;

  AudioStreamPlayer({AudioPlayer? playerBackend}) : _playerBackend = playerBackend ?? AudioPlayer() {
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
      if (currentIndex == null || _playerBackend.sequence?.isNotEmpty != true) {
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
      contentType: 'audio/L16',
    );
  }

  void dispose() {
    bytes = null;
  }
}
