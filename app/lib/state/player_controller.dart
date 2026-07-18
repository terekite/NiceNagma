// Orchestrates the whole player: params -> re-render -> load -> gapless playback.
//
// Coarse state (params, playing, rendering, error) is exposed via ChangeNotifier
// so the controls rebuild on change. The high-frequency audio-clock position is
// a separate ValueNotifier so only the cycle wheel repaints at 60 Hz, not the
// whole tree.
//
// Core thesis in action: any tempo/Sa/nagma change is a *re-render* (a new WAV
// from the service, seconds), never a time-stretch. `render/` guarantees the
// returned WAV is an exact-sample-length loop; the native player just loops it.

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../taal.dart';
import '../services/loop_player.dart';
import '../services/render_client.dart';

class PlayerController extends ChangeNotifier {
  final RenderClient _client;
  final LoopPlayer _player;

  PlayerController({RenderClient? client, LoopPlayer? player})
      : _client = client ?? RenderClient(),
        _player = player ?? LoopPlayer();

  // --- Params (a change to any of these triggers a re-render) ---
  String nagmaText = Config.defaultNagma;
  double bpm = Config.defaultBpm;
  String sa = Config.defaultSa;
  String taalName = Config.defaultTaal;
  int avartans = Config.defaultAvartans;

  // --- Playback / render state ---
  bool playing = false;
  bool rendering = false;
  String? error; // fatal-ish (service unreachable / render failed)
  String? nagmaError; // inline editor validation (422)
  bool serviceHealthy = true;
  double tanpuraVolume = 0;

  // --- High-frequency audio-clock position (wheel + matra counter) ---
  final ValueNotifier<LoopPosition> position =
      ValueNotifier<LoopPosition>(LoopPosition.zero);

  Taal get taal => Taal.byName(taalName);

  StreamSubscription<LoopPosition>? _posSub;
  Timer? _debounce;
  int _renderGeneration = 0; // guards against stale async renders landing late

  /// Called once at startup. Probes the service, then renders + loads the
  /// default lehra so the very first frame the user sees is ready to play.
  Future<void> init() async {
    _posSub = _player.positions.listen((p) {
      position.value = p;
      if (p.playing != playing) {
        playing = p.playing;
        notifyListeners();
      }
    });
    serviceHealthy = await _client.healthy();
    if (!serviceHealthy) notifyListeners();
    await _renderAndLoad();
  }

  /// The laya band the server will auto-select for the current BPM, for display.
  /// Mirrors core's reduction thresholds (vilambit < 60 <= madhya < 160 <= drut).
  String get layaLabel {
    if (bpm < 60) return 'vilambit';
    if (bpm < 160) return 'madhya';
    return 'drut';
  }

  Future<void> togglePlay() async {
    if (rendering) return;
    if (playing) {
      await _player.pause();
      playing = false;
    } else {
      await _player.play();
      playing = true;
    }
    notifyListeners();
  }

  void setBpm(double v) {
    final clamped = v.clamp(Config.minBpm, Config.maxBpm).toDouble();
    if (clamped == bpm) return;
    bpm = clamped;
    notifyListeners();
    _scheduleReRender();
  }

  void setSa(String v) {
    if (v == sa) return;
    sa = v;
    notifyListeners();
    _scheduleReRender();
  }

  /// Apply an edited nagma. Returns true if it rendered, false if rejected
  /// (in which case `nagmaError` holds the parser message).
  Future<bool> setNagma(String text) async {
    nagmaText = text;
    nagmaError = null;
    notifyListeners();
    await _renderAndLoad();
    return nagmaError == null;
  }

  Future<void> setTanpuraVolume(double v) async {
    tanpuraVolume = v.clamp(0, 1).toDouble();
    await _player.setTanpuraVolume(tanpuraVolume);
    notifyListeners();
  }

  // Coalesce rapid slider/dropdown changes into one render.
  void _scheduleReRender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _renderAndLoad);
  }

  Future<void> _renderAndLoad() async {
    final gen = ++_renderGeneration;
    rendering = true;
    error = null;
    notifyListeners();

    final req = RenderRequest(
      nagmaText: nagmaText,
      bpm: bpm,
      sa: sa,
      taal: taalName,
      avartans: avartans,
    );

    try {
      final path = await _client.getLoop(req);
      if (gen != _renderGeneration) return; // a newer change superseded us
      await _player.load(path); // seamlessly swaps buffer; keeps playing if playing
      serviceHealthy = true;
    } on NagmaRejected catch (e) {
      if (gen != _renderGeneration) return;
      nagmaError = e.message;
    } catch (e) {
      if (gen != _renderGeneration) return;
      error = e.toString();
      serviceHealthy = false;
    } finally {
      if (gen == _renderGeneration) {
        rendering = false;
        notifyListeners();
      }
    }
  }

  /// Retry after a failed startup render (e.g. once the service is up).
  Future<void> retry() async {
    serviceHealthy = await _client.healthy();
    await _renderAndLoad();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _posSub?.cancel();
    position.dispose();
    super.dispose();
  }
}
