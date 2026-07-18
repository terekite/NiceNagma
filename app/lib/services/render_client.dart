// HTTP render client: the cloud/LAN path. POSTs a RenderRequest to the Python
// render service and caches the returned WAV by the shared cache key. Selected
// via Config.renderer == 'http' (e.g. --dart-define=RENDERER=http). The default
// build renders on-device (see LocalRenderer); this is what you'd point at a
// cloud-hosted render service at scale.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'loop_renderer.dart';

export 'loop_renderer.dart' show RenderRequest, NagmaRejected, LoopRenderer;

class HttpRenderClient implements LoopRenderer {
  final String baseUrl;
  HttpRenderClient([String? baseUrl]) : baseUrl = baseUrl ?? Config.renderBaseUrl;

  @override
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
      throw NagmaRejected(_detail(resp.body));
    }
    if (resp.statusCode != 200) {
      throw Exception('render failed (${resp.statusCode}): ${_detail(resp.body)}');
    }

    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  @override
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
