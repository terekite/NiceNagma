// The app<->render seam. This is the ONLY way the app obtains audio: it POSTs a
// RenderRequest and caches the returned WAV by the same key the server uses.
// The app knows nothing about synthesis — just JSON in, audio file out.
//
// Scaffolding: compiles conceptually against the planned deps (http,
// path_provider, crypto). Wire into the player on Day 2.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class RenderRequest {
  final String nagmaText;
  final double bpm;
  final String sa; // e.g. "D", "C#"
  final String instrument;
  final String taal;
  final int avartans;
  final int seed;
  final String? laya; // null => auto-select from bpm (vilambit/madhya/drut)

  const RenderRequest({
    required this.nagmaText,
    required this.bpm,
    required this.sa,
    this.instrument = 'harmonium',
    this.taal = 'teentaal',
    this.avartans = 4,
    this.seed = 0,
    this.laya,
  });

  Map<String, dynamic> toJson() => {
        'schema_version': '1.0.0',
        'nagma_text': nagmaText,
        'bpm': bpm,
        'sa': sa,
        'instrument': instrument,
        'taal': taal,
        'avartans': avartans,
        'seed': seed,
        'laya': laya,
        'format': 'wav',
      };

  // Must match the server's _cache_key ordering so client and server agree.
  String cacheKey() {
    final canonical = jsonEncode({
      'avartans': avartans,
      'bpm': bpm,
      'instrument': instrument,
      'laya': laya,
      'nagma': nagmaText.trim(),
      'sa': sa,
      'seed': seed,
      'taal': taal,
    });
    return sha256.convert(utf8.encode(canonical)).toString().substring(0, 24);
  }
}

class RenderClient {
  final String baseUrl; // e.g. http://192.168.1.10:8000
  RenderClient(this.baseUrl);

  /// Returns a local file path to the rendered loop WAV, rendering (and caching)
  /// on a miss. Cached renders play fully offline.
  Future<String> getLoop(RenderRequest req) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/render-cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final file = File('${cacheDir.path}/${req.cacheKey()}.wav');
    if (file.existsSync()) return file.path;

    final resp = await http.post(
      Uri.parse('$baseUrl/render'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req.toJson()),
    );
    if (resp.statusCode != 200) {
      throw Exception('render failed (${resp.statusCode}): ${resp.body}');
    }
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }
}
