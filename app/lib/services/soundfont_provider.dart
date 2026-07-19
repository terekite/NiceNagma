// Resolves an instrument name to a filesystem path for its soundfont (.sf2).
//
// The native renderer needs a real file URL, not a Flutter asset key, so bundled
// fonts are copied out to app-support on first use. This copy step is the seam
// where DOWNLOADED instrument packs slot in later: a future instrument fetches
// its .sf2 from static hosting into the same dir and returns the path — no change
// to the render pipeline, which is instrument-agnostic. Only harmonium ships in
// the binary (~5.6 MB); everything else stays out of the app download.

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

class SoundfontProvider {
  /// Instrument -> bundled asset. Add on-demand-pack entries here later.
  static const Map<String, String> _bundled = {
    'harmonium': 'assets/soundfonts/harmonium.sf2',
    // Bowed-string sarangi (~6 MB, 39 looped zones C2..D5, built by
    // scripts/build_sarangi.py from CC0 single notes). A selectable melodic
    // voice alongside the harmonium.
    'sarangi': 'assets/soundfonts/sarangi.sf2',
  };

  /// Filesystem path to the instrument's .sf2, materializing the bundled asset on
  /// first use. Subsequent calls return the cached copy.
  Future<String> pathFor(String instrument) async {
    final asset = _bundled[instrument];
    if (asset == null) {
      throw Exception('No soundfont available for instrument "$instrument".');
    }
    final dir = await getApplicationSupportDirectory();
    final sfDir = Directory('${dir.path}/soundfonts');
    if (!sfDir.existsSync()) sfDir.createSync(recursive: true);

    final out = File('${sfDir.path}/$instrument.sf2');
    if (out.existsSync() && out.lengthSync() > 0) return out.path;

    final data = await rootBundle.load(asset);
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out.path;
  }
}
