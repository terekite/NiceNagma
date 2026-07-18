// The app<->render seam. This is the ONLY way the app obtains audio: it POSTs a
// RenderRequest and caches the returned WAV by the same key the server uses.
// The app knows nothing about synthesis — just JSON in, audio file out.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';

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

/// Raised when the service rejects the nagma (HTTP 422) — the message is the
/// parser error, suitable to show inline in the editor.
class NagmaRejected implements Exception {
  final String message;
  NagmaRejected(this.message);
  @override
  String toString() => message;
}

class RenderClient {
  final String baseUrl;
  RenderClient([String? baseUrl]) : baseUrl = baseUrl ?? Config.renderBaseUrl;

  /// Returns a local file path to the rendered loop WAV, rendering (and caching)
  /// on a miss. Cached renders play fully offline.
  Future<String> getLoop(RenderRequest req) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/render-cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final file = File('${cacheDir.path}/${req.cacheKey()}.wav');
    if (file.existsSync() && file.lengthSync() > 0) return file.path;

    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$baseUrl/render'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(req.toJson()),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw Exception(
          'Cannot reach render service at $baseUrl. Is it running, and is the '
          'phone on the same Wi-Fi as the Mac? ($e)');
    }

    if (resp.statusCode == 422) {
      // { "detail": "nagma parse error: ..." }
      final detail = _detail(resp.body);
      throw NagmaRejected(detail);
    }
    if (resp.statusCode != 200) {
      throw Exception('render failed (${resp.statusCode}): ${_detail(resp.body)}');
    }

    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  /// Quick reachability + capability probe for a friendly startup banner.
  Future<bool> healthy() async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) return false;
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      return (m['ok'] == true) && (m['soundfont'] == true);
    } catch (_) {
      return false;
    }
  }

  static String _detail(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return (m['detail'] ?? body).toString();
    } catch (_) {
      return body;
    }
  }
}
