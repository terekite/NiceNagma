// Tanpura mixer: parses samples from an SF2, mixes the score, and emits an
// exact-length, non-silent, sustained stereo WAV. Uses a synthetic minimal SF2 so
// the test needs no bundled asset.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/sargam.dart' show saToMidi;
import 'package:nicenagma/render/tanpura.dart';
import 'package:nicenagma/render/tanpura_mixer.dart';

/// Build a minimal SF2 with one sustained sample (root 49 = C#3), long enough that
/// the mixer's nearest-root pick + resample covers every tanpura string.
Uint8List _fakeSf2({int root = 49, int frames = 44100 * 8}) {
  final b = BytesBuilder();
  void tag(String s) => b.add(s.codeUnits);
  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  // smpl chunk: a steady (sustained) low-level tone so the output is non-silent.
  tag('smpl');
  u32(frames * 2);
  final pcm = ByteData(frames * 2);
  for (var i = 0; i < frames; i++) {
    // simple periodic waveform, constant amplitude (sustains, no decay)
    final v = (8000 * ((i % 160) < 80 ? 1 : -1)).clamp(-32768, 32767);
    pcm.setInt16(i * 2, v, Endian.little);
  }
  b.add(pcm.buffer.asUint8List());

  // shdr chunk: one 46-byte record + EOS terminal.
  tag('shdr');
  u32(46 * 2);
  final rec = ByteData(46);
  for (var i = 0; i < 20; i++) {
    rec.setUint8(i, 'Tanpura'.codeUnitAt(i % 7));
  }
  rec.setUint32(20, 0, Endian.little); // start
  rec.setUint32(24, frames, Endian.little); // end
  rec.setUint32(28, 1, Endian.little); // loopstart
  rec.setUint32(32, frames - 1, Endian.little); // loopend
  rec.setUint32(36, 44100, Endian.little); // sample rate
  rec.setUint8(40, root); // original pitch
  b.add(rec.buffer.asUint8List());
  final eos = ByteData(46);
  for (var i = 0; i < 3; i++) {
    eos.setUint8(i, 'EOS'.codeUnitAt(i));
  }
  b.add(eos.buffer.asUint8List());
  return b.toBytes();
}

void main() {
  final sf2 = _fakeSf2();

  test('mixed WAV is exact loop length, stereo 16-bit', () {
    final score = tanpuraScore(saMidi: saToMidi('D'), firstStringSwar: 'P');
    final wav = mixTanpuraWav(score, sf2);
    final expectedData = score.loopLengthSamples * 2 * 2; // stereo, 16-bit
    expect(wav.length, 44 + expectedData);
    // RIFF/WAVE header sanity
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
  });

  test('output is non-silent and never goes fully silent (sustained pedal)', () {
    final score = tanpuraScore(saMidi: saToMidi('D'), firstStringSwar: 'P');
    final wav = mixTanpuraWav(score, sf2);
    final pcm = ByteData.sublistView(wav, 44);
    final n = (wav.length - 44) ~/ 2;
    // window-RMS across the loop: no ~0.5 s window should be silent.
    final sr = score.sampleRate;
    final win = (0.5 * sr).round() * 2; // stereo samples per 0.5 s
    var minWinPeak = double.infinity;
    var globalPeak = 0.0;
    for (var w = 0; w + win <= n; w += win) {
      var peak = 0.0;
      for (var i = w; i < w + win; i++) {
        final v = pcm.getInt16(i * 2, Endian.little).abs() / 32768.0;
        if (v > peak) peak = v;
        if (v > globalPeak) globalPeak = v;
      }
      if (peak < minWinPeak) minWinPeak = peak;
    }
    expect(globalPeak, greaterThan(0.5)); // normalized near full scale
    expect(minWinPeak, greaterThan(0.05)); // no silent gap anywhere in the loop
  });
}
