// On-device render path: Dart compile -> SMF -> native AVAudioUnitSampler render.
//
// Mirrors the Python service's pipeline but runs entirely on the phone, so the
// app renders offline with no Mac/service. Same cache dir + cache key as
// HttpRenderClient, so a loop cached by either replays without re-rendering.
//
//   parse (Dart) -> realize (Dart) -> SMF bytes (Dart) -> nicenagma/render (Swift)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../render/compiler.dart';
import '../render/midi.dart';
import '../render/models.dart';
import '../render/parser.dart';
import 'loop_renderer.dart';
import 'soundfont_provider.dart';

class LocalRenderer implements LoopRenderer {
  static const MethodChannel _channel = MethodChannel('nicenagma/render');
  final SoundfontProvider _soundfonts;

  LocalRenderer({SoundfontProvider? soundfonts})
      : _soundfonts = soundfonts ?? SoundfontProvider();

  @override
  Future<String> getLoop(RenderRequest req) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/render-cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final out = File('${cacheDir.path}/${req.cacheKey()}.wav');
    if (out.existsSync() && out.lengthSync() > 0) return out.path;

    // --- parse + compile in Dart (parse errors surface inline like the 422 path)
    final NagmaDoc doc;
    try {
      doc = parseNagma(req.nagmaText, taal: req.taal);
    } on NagmaParseError catch (e) {
      throw NagmaRejected(e.message);
    }
    final score = realize(
      doc,
      bpm: req.bpm,
      sa: req.sa,
      laya: req.laya,
      avartans: req.avartans,
      seed: req.seed,
      instrument: req.instrument,
    );

    // --- SMF -> temp file for the native sequencer
    final midiBytes = scoreToMidi(score);
    final tmp = await getTemporaryDirectory();
    final midiFile = File('${tmp.path}/${req.cacheKey()}.mid');
    await midiFile.writeAsBytes(midiBytes, flush: true);

    final sfPath = await _soundfonts.pathFor(req.instrument);

    try {
      final frames = await _channel.invokeMethod<int>('render', <String, dynamic>{
        'midiPath': midiFile.path,
        'soundfontPath': sfPath,
        'outPath': out.path,
        'sampleRate': score.sampleRate,
        'loopLengthSamples': score.loopLengthSamples,
        'bellowsRateHz': score.bellows['rate_hz'],
        'bellowsDepth': score.bellows['depth'],
      });
      if (frames == null || frames != score.loopLengthSamples) {
        throw Exception(
            'on-device render returned $frames frames, expected ${score.loopLengthSamples}');
      }
    } on PlatformException catch (e) {
      throw Exception('on-device render failed: ${e.message}');
    } finally {
      try {
        await midiFile.delete();
      } catch (_) {}
    }

    return out.path;
  }

  /// On-device rendering is always available.
  @override
  Future<bool> healthy() async => true;
}
