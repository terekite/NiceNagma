// Dart side of the native gapless loop player (ios/Runner/AppDelegate.swift).
//
// Control goes out over a MethodChannel; the audio-clock position comes back on
// an EventChannel at ~60 Hz. The app never times playback itself — the matra
// counter and cycle wheel read `positions`, which originate from the audio
// render clock, so UI and sound cannot drift apart.

import 'package:flutter/services.dart';

/// One audio-clock sample: where we are inside the rendered loop right now.
class LoopPosition {
  final int frame; // frame within the loop [0, loopFrames)
  final int loopFrames; // total frames in the loop (all avartans)
  final double sampleRate;
  final bool playing;

  const LoopPosition({
    required this.frame,
    required this.loopFrames,
    required this.sampleRate,
    required this.playing,
  });

  static const zero =
      LoopPosition(frame: 0, loopFrames: 0, sampleRate: 44100, playing: false);

  factory LoopPosition.fromEvent(dynamic e) {
    final m = (e as Map).cast<String, dynamic>();
    return LoopPosition(
      frame: (m['frame'] as num?)?.toInt() ?? 0,
      loopFrames: (m['loopFrames'] as num?)?.toInt() ?? 0,
      sampleRate: (m['sampleRate'] as num?)?.toDouble() ?? 44100,
      playing: m['playing'] as bool? ?? false,
    );
  }

  /// Fractional position through a single avartan (cycle), [0, 1). The rendered
  /// super-loop holds `avartans` cycles; the matra grid is uniform across them.
  double avartanPhase(int avartans, int matraCount) {
    if (loopFrames == 0) return 0;
    final framesPerAvartan = loopFrames / avartans;
    return (frame % framesPerAvartan) / framesPerAvartan;
  }

  /// Current matra index within the cycle, [0, matraCount).
  int matraIndex(int avartans, int matraCount) {
    final p = avartanPhase(avartans, matraCount);
    final idx = (p * matraCount).floor();
    return idx.clamp(0, matraCount - 1);
  }

  /// Which avartan of the super-loop is playing, [0, avartans).
  int avartanIndex(int avartans) {
    if (loopFrames == 0) return 0;
    final framesPerAvartan = loopFrames / avartans;
    return (frame ~/ framesPerAvartan).clamp(0, avartans - 1);
  }
}

class LoopPlayer {
  static const _method = MethodChannel('nicenagma/loop');
  static const _events = EventChannel('nicenagma/loop/position');

  Stream<LoopPosition>? _positions;

  /// Broadcast stream of audio-clock positions (~60 Hz while playing).
  Stream<LoopPosition> get positions =>
      _positions ??= _events.receiveBroadcastStream().map(LoopPosition.fromEvent);

  /// Load a rendered loop WAV, armed for gapless looping. Returns loop length.
  Future<int> load(String path) async {
    final res = await _method.invokeMethod<Map>('load', {'path': path});
    return (res?['loopFrames'] as num?)?.toInt() ?? 0;
  }

  Future<void> play() => _method.invokeMethod('play');
  Future<void> pause() => _method.invokeMethod('pause');
  Future<void> stop() => _method.invokeMethod('stop');

  Future<void> loadTanpura(String path) =>
      _method.invokeMethod('loadTanpura', {'path': path});

  /// Tanpura drone bus volume, 0..1.
  Future<void> setTanpuraVolume(double v) =>
      _method.invokeMethod('setTanpuraVolume', {'volume': v});

  /// Lehra bus volume, 0..1 (0 solos the tanpura).
  Future<void> setLehraVolume(double v) =>
      _method.invokeMethod('setLehraVolume', {'volume': v});
}
