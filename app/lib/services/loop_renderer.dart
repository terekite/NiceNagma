// The app<->render seam. A LoopRenderer takes a RenderRequest and returns a local
// path to a rendered, exact-sample-length loop WAV. Two implementations exist:
//   - LocalRenderer   (on-device: Dart compile -> native AVAudioUnitSampler)
//   - HttpRenderClient (cloud/LAN: the Python render service)
// They are interchangeable and share the SAME cache key, so switching between
// them never re-renders a loop that's already cached. Config.renderer selects one.
//
// This file is the only shared surface between the app and "how audio is made";
// the rest of the app knows nothing about synthesis — JSON in, audio file out.

import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract class LoopRenderer {
  /// Returns a local file path to the rendered loop WAV, rendering (and caching)
  /// on a miss. Cached renders replay fully offline.
  Future<String> getLoop(RenderRequest req);

  /// Reachability/capability probe for a friendly startup banner. On-device
  /// rendering is always available; the HTTP client actually pings the service.
  Future<bool> healthy();
}

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

  // Must match the server's _cache_key ordering so client and server agree, and
  // so the on-device and HTTP renderers share cached WAVs.
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

/// Raised when a nagma fails to parse — the message is the parser error, suitable
/// to show inline in the editor. (HTTP path: server returns 422; local path: the
/// Dart parser throws.)
class NagmaRejected implements Exception {
  final String message;
  NagmaRejected(this.message);
  @override
  String toString() => message;
}
