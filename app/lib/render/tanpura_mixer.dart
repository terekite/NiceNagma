// Direct-mix tanpura synthesis (no sampler).
//
// Apple's AVAudioUnitSampler ignores SF2 loop points AND volume-envelope
// generators — it decays every held note to silence in ~1.5 s, which makes a slow,
// sustained tanpura (long holds between plucks) impossible through the sampler. So
// the tanpura is synthesized by MIXING its sustained string samples directly at the
// pluck positions, exactly like a tanpura box: each pluck lays down its full baked
// sustain, overlapping sustains form the continuous pedal, and the loop is closed
// with a circular fold. The lehra still uses the sampler (arbitrary melodies).
//
// Samples come from the bundled tanpura.sf2 (the baked-sustain zones), so there is
// no separate asset to ship. Pitch is a per-note linear resample (small shifts).

import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';

class _Sample {
  final Float64List data; // mono, -1..1
  final int root; // MIDI root the sample was recorded at
  _Sample(this.data, this.root);
}

/// Mixes a tanpura [ExpressiveScore] into a mastered, exact-length loop WAV
/// (16-bit stereo PCM). [sf2Bytes] is the bundled tanpura soundfont, read for its
/// baked string samples.
Uint8List mixTanpuraWav(ExpressiveScore score, Uint8List sf2Bytes) {
  final samples = _parseSf2Samples(sf2Bytes);
  final sr = score.sampleRate;
  final loopLen = score.loopLengthSamples;
  // Render past the loop end to capture the full ring, then fold it back circularly.
  final tail = (10.0 * sr).round();
  final buf = Float64List(loopLen + tail);

  for (final e in score.events) {
    final s = _nearestRoot(samples, e.midi);
    final ratio = math.pow(2.0, (e.midi - s.root) / 12.0).toDouble(); // playback speed
    final start = (e.startS * sr).round();
    final gain = (e.velocity / 127.0);
    // Per-note envelope: a short anti-click ramp, then exponential decay over the
    // string's ring time (durS) — each pluck blooms and fades so the four pitches
    // are heard moving, not one flat drone. tau set so it reaches ~-20 dB at durS.
    final rampN = (0.008 * sr).round();
    final tau = e.durS / 1.6 * sr; // gentle: notes ring into each other (connected)
    final maxOut = ((e.durS + 1.5) * sr).round(); // stop once well decayed
    final n = math.min((s.data.length / ratio).floor(), maxOut);
    for (var i = 0; i < n; i++) {
      final idx = start + i;
      if (idx >= buf.length) break;
      final src = i * ratio;
      final i0 = src.floor();
      if (i0 + 1 >= s.data.length) break;
      final frac = src - i0;
      final ramp = i < rampN ? i / rampN : 1.0;
      final env = ramp * math.exp(-i / tau);
      buf[idx] += (s.data[i0] * (1 - frac) + s.data[i0 + 1] * frac) * gain * env;
    }
  }

  // Circular fold: a note ringing past the loop end reappears at the start, so the
  // loop is truly periodic and the density is identical across the seam.
  final body = Float64List(loopLen);
  for (var i = 0; i < loopLen; i++) {
    body[i] = buf[i];
  }
  for (var j = loopLen; j < buf.length; j++) {
    body[(j - loopLen) % loopLen] += buf[j];
  }

  // Dry: a real tanpura recording needs no effect. A comb/Schroeder reverb reads
  // as an echo pedal; the natural jawari decay IS the sound.
  final stereo = [Float64List.fromList(body), Float64List.fromList(body)];
  _normalize(stereo, -1.0);
  return _encodeWav(stereo, sr);
}

// --- SF2 sample extraction ---------------------------------------------------

List<_Sample> _parseSf2Samples(Uint8List b) {
  final smplData = _findChunk(b, 'smpl') + 8; // byte offset of the int16 PCM
  int pcm16(int frame) {
    final o = smplData + frame * 2;
    return (b[o] | (b[o + 1] << 8)).toSigned(16);
  }

  final shdrOff = _findChunk(b, 'shdr');
  final shdrSize = _u32(b, shdrOff + 4);
  final base = shdrOff + 8;
  final out = <_Sample>[];
  for (var r = 0; r + 46 <= shdrSize; r += 46) {
    final o = base + r;
    if (b[o] == 0x45 && b[o + 1] == 0x4F && b[o + 2] == 0x53) break; // "EOS"
    final start = _u32(b, o + 20);
    final end = _u32(b, o + 24);
    final root = b[o + 40];
    if (end <= start) continue;
    final data = Float64List(end - start);
    for (var i = 0; i < data.length; i++) {
      data[i] = pcm16(start + i) / 32768.0;
    }
    out.add(_Sample(data, root));
  }
  return out;
}

_Sample _nearestRoot(List<_Sample> samples, int midi) {
  var best = samples.first;
  for (final s in samples) {
    if ((s.root - midi).abs() < (best.root - midi).abs()) best = s;
  }
  return best;
}

int _findChunk(Uint8List b, String tag) {
  final t = tag.codeUnits;
  for (var i = 0; i + 4 <= b.length; i++) {
    if (b[i] == t[0] && b[i + 1] == t[1] && b[i + 2] == t[2] && b[i + 3] == t[3]) {
      return i;
    }
  }
  throw StateError('SF2 chunk "$tag" not found');
}

int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

void _normalize(List<Float64List> ch, double targetDb) {
  var peak = 0.0;
  for (final c in ch) {
    for (final v in c) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
  }
  if (peak <= 0) return;
  final g = math.pow(10.0, targetDb / 20.0) / peak;
  for (final c in ch) {
    for (var i = 0; i < c.length; i++) {
      c[i] *= g;
    }
  }
}

// --- WAV (16-bit stereo interleaved) -----------------------------------------

Uint8List _encodeWav(List<Float64List> ch, int sr) {
  final n = ch[0].length;
  final bytes = BytesBuilder();
  final header = ByteData(44);
  final dataLen = n * 2 * 2; // stereo, 16-bit
  void s4(int o, String s) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  s4(0, 'RIFF');
  header.setUint32(4, 36 + dataLen, Endian.little);
  s4(8, 'WAVE');
  s4(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 2, Endian.little); // channels
  header.setUint32(24, sr, Endian.little);
  header.setUint32(28, sr * 2 * 2, Endian.little); // byte rate
  header.setUint16(32, 4, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits
  s4(36, 'data');
  header.setUint32(40, dataLen, Endian.little);
  bytes.add(header.buffer.asUint8List());

  final pcm = ByteData(dataLen);
  var o = 0;
  for (var i = 0; i < n; i++) {
    for (final c in ch) {
      var v = (c[i] * 32767.0).round();
      if (v > 32767) v = 32767;
      if (v < -32768) v = -32768;
      pcm.setInt16(o, v, Endian.little);
      o += 2;
    }
  }
  bytes.add(pcm.buffer.asUint8List());
  return bytes.toBytes();
}
