// On-device tanpura render path: Dart sequence -> SMF -> native sampler render.
//
// Parallel to LocalRenderer, but for the tanpura drone: it sequences the 4-string
// Pa-Sa-Sa-kharaj pluck cycle (app/lib/render/tanpura.dart) instead of compiling a
// nagma, and renders it through the same nicenagma/render channel with the pluck
// preset (no harmonium bellows/chorus). The resulting WAV is a seamless loop the
// native LoopPlayer plays on its own bus, independent of the lehra.
//
// It is a separate type (not a LoopRenderer/RenderRequest) so the lehra's cache
// key — which must byte-match the Python service — stays untouched.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../render/sargam.dart' show saToMidi;
import '../render/tanpura.dart';
import '../render/tanpura_mixer.dart';
import 'soundfont_provider.dart';

class TanpuraRequest {
  final String sa; // e.g. "D", "C#"
  final String firstStringSwar; // 'P' | 'm' | 'M' | 'N' (auto-selected)
  final int seed;
  final double cycleLengthS;
  final int cycleCount;
  final int sampleRate;

  const TanpuraRequest({
    required this.sa,
    required this.firstStringSwar,
    this.seed = 0,
    this.cycleLengthS = 7.0,
    this.cycleCount = 4,
    this.sampleRate = 44100,
  });

  String cacheKey() {
    final canonical = jsonEncode({
      'cycleCount': cycleCount,
      'cycleLengthS': cycleLengthS,
      'firstString': firstStringSwar,
      'sa': sa,
      'sampleRate': sampleRate,
      'seed': seed,
    });
    return sha256.convert(utf8.encode(canonical)).toString().substring(0, 24);
  }
}

class TanpuraRenderer {
  final SoundfontProvider _soundfonts;

  TanpuraRenderer({SoundfontProvider? soundfonts})
      : _soundfonts = soundfonts ?? SoundfontProvider();

  /// Render (and cache) the tanpura loop for this request; returns the WAV path.
  ///
  /// The tanpura is synthesized by directly mixing its sustained string samples
  /// (from the bundled tanpura.sf2) at the pluck positions — see tanpura_mixer.dart
  /// for why the sampler can't be used. Deterministic given the request, so it
  /// caches like any other loop.
  Future<String> getTanpura(TanpuraRequest req) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/render-cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    // Distinct prefix so tanpura loops never collide with lehra cache files.
    final out = File('${cacheDir.path}/tanpura-${req.cacheKey()}.wav');
    if (out.existsSync() && out.lengthSync() > 0) return out.path;

    final score = tanpuraScore(
      saMidi: saToMidi(req.sa),
      firstStringSwar: req.firstStringSwar,
      seed: req.seed,
      sampleRate: req.sampleRate,
      cycleLengthS: req.cycleLengthS,
      cycleCount: req.cycleCount,
    );

    final sfPath = await _soundfonts.pathFor('tanpura');
    final sf2Bytes = await File(sfPath).readAsBytes();
    final wav = mixTanpuraWav(score, sf2Bytes);
    await out.writeAsBytes(wav, flush: true);
    return out.path;
  }
}
