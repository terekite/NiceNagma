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
import '../render/reduce.dart' show layaForBpm;
import '../render/first_string.dart';
import '../render/models.dart' show NagmaDoc;
import '../render/parser.dart';
import '../services/loop_player.dart';
import '../services/local_renderer.dart';
import '../services/tanpura_renderer.dart';
import '../services/render_client.dart'; // re-exports LoopRenderer, RenderRequest, NagmaRejected

/// Pick the renderer from Config.renderer: on-device by default, HTTP service
/// when RENDERER=http. Both share the RenderRequest->WAV interface and cache key.
LoopRenderer _defaultRenderer() =>
    Config.renderer == 'http' ? HttpRenderClient() : LocalRenderer();

class PlayerController extends ChangeNotifier {
  final LoopRenderer _client;
  final LoopPlayer _player;

  PlayerController({LoopRenderer? client, LoopPlayer? player})
      : _client = client ?? _defaultRenderer(),
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
  double lehraVolume = 1;

  final TanpuraRenderer _tanpura = TanpuraRenderer();
  int _tanpuraGeneration = 0; // guards against stale tanpura renders landing late

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
    // Render the lehra and tanpura independently so one failing never blocks the
    // other. The tanpura bus starts muted (tanpuraVolume 0) until the slider rises.
    await Future.wait([_renderAndLoad(), _renderAndLoadTanpura()]);
  }

  /// The first-string swar for the current nagma (Pa/Ma/tivra-Ma/Ni, auto-derived).
  /// Falls back to Pa if the nagma doesn't parse.
  String get _firstStringSwar {
    try {
      final NagmaDoc doc = parseNagma(nagmaText, taal: taalName);
      return selectFirstStringSwar(swarsInDoc(doc));
    } catch (_) {
      return 'P';
    }
  }

  /// Render the tanpura loop for the current Sa + auto first-string, then load it
  /// onto the (independent) tanpura bus. A tanpura failure must never block the
  /// lehra, so everything here is best-effort.
  Future<void> _renderAndLoadTanpura() async {
    final gen = ++_tanpuraGeneration;
    try {
      final path = await _tanpura.getTanpura(
        TanpuraRequest(sa: sa, firstStringSwar: _firstStringSwar, seed: 0),
      );
      if (gen != _tanpuraGeneration) return; // a newer change superseded us
      await _player.loadTanpura(path); // hot-swaps the buffer; keeps playing
    } catch (_) {
      // Leave the tanpura silent on failure.
    }
  }

  /// The laya the renderer auto-selects for the current BPM, for display. Calls
  /// the same `layaForBpm` the reducer uses, so the label always matches what
  /// actually renders (vilambit <=85, madhya <=160, else drut).
  String get layaLabel => layaForBpm(bpm);

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

  /// Switch taal. Because the text grammar is one line per vibhag, the current
  /// nagma won't fit a different taal's structure — so we also load that taal's
  /// default nagma. Re-renders both lehra and tanpura (first-string may change).
  void setTaal(String name) {
    if (name == taalName) return;
    taalName = name;
    nagmaText = Config.defaultNagmaFor(name);
    nagmaError = null;
    notifyListeners();
    _scheduleReRender();
    _renderAndLoadTanpura();
  }

  void setSa(String v) {
    if (v == sa) return;
    sa = v;
    notifyListeners();
    _scheduleReRender();
    // The tanpura re-renders in-tune for the new Sa (exact, not a pitch shift).
    _renderAndLoadTanpura();
  }

  /// Apply an edited nagma. Returns true if it rendered, false if rejected
  /// (in which case `nagmaError` holds the parser message).
  Future<bool> setNagma(String text) async {
    nagmaText = text;
    nagmaError = null;
    notifyListeners();
    await _renderAndLoad();
    // The first-string tuning may change with the notes, so re-render the tanpura.
    _renderAndLoadTanpura();
    return nagmaError == null;
  }

  Future<void> setTanpuraVolume(double v) async {
    tanpuraVolume = v.clamp(0, 1).toDouble();
    await _player.setTanpuraVolume(tanpuraVolume);
    notifyListeners();
  }

  Future<void> setLehraVolume(double v) async {
    lehraVolume = v.clamp(0, 1).toDouble();
    await _player.setLehraVolume(lehraVolume);
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
