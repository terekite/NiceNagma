// Locks in the sitar wiring: it is exposed as a selectable bundled instrument and
// threads through RenderRequest.instrument (distinct cache key + serialization) so
// the render seam picks up sitar.sf2. Pure logic — no device/platform channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/config.dart';
import 'package:nicenagma/render/compiler.dart';
import 'package:nicenagma/render/midi.dart';
import 'package:nicenagma/render/parser.dart';
import 'package:nicenagma/render/performance.dart' as perf;
import 'package:nicenagma/services/loop_renderer.dart';
import 'package:nicenagma/services/soundfont_provider.dart';

void main() {
  test('sitar is a selectable bundled instrument alongside harmonium', () {
    final names = SoundfontProvider.bundledInstruments.toList();
    expect(names, contains('harmonium'));
    expect(names, contains('sitar'));
  });

  RenderRequest req(String instrument) => RenderRequest(
        nagmaText: 'S R G m | P - D P | S R G m | P - D P',
        bpm: 90,
        sa: 'C',
        instrument: instrument,
      );

  test('instrument is serialized into the render request', () {
    expect(req('sitar').toJson()['instrument'], 'sitar');
  });

  test('choosing sitar yields a different cache key than harmonium', () {
    // Same nagma/bpm/sa — only the instrument differs, so the renderer must not
    // reuse the harmonium loop for a sitar render (and vice versa).
    expect(req('sitar').cacheKey(), isNot(equals(req('harmonium').cacheKey())));
  });

  test('sitar cache key is stable and a 24-char hex digest', () {
    final k = req('sitar').cacheKey();
    expect(k, matches(RegExp(r'^[0-9a-f]{24}$')));
    expect(k, equals(req('sitar').cacheKey()));
  });

  test('sitar is classified as plucked, harmonium is not', () {
    expect(perf.isPlucked('sitar'), isTrue);
    expect(perf.isPlucked('harmonium'), isFalse);
  });

  test('sitar renders no kan-swar grace notes; harmonium does', () {
    // Grace notes are the ONLY seed-dependent difference in event count between
    // the two instruments (jitter/clamping shift timing, never count). So: the
    // sitar count is invariant to seed (no graces), and harmonium exceeds it for
    // at least one seed (graces added). vilambit (60 BPM) => long, grace-eligible
    // notes and the highest grace density.
    final doc = parseNagma(Config.defaultNagma, taal: 'teentaal');
    int sitarCount(int seed) =>
        realize(doc, bpm: 60, sa: 'C', instrument: 'sitar', seed: seed)
            .events
            .length;
    int harmCount(int seed) =>
        realize(doc, bpm: 60, sa: 'C', instrument: 'harmonium', seed: seed)
            .events
            .length;

    final baseline = sitarCount(0);
    var harmoniumEverAddsGraces = false;
    for (var seed = 0; seed < 24; seed++) {
      expect(sitarCount(seed), equals(baseline),
          reason: 'sitar count must not vary with seed (no graces)');
      expect(harmCount(seed) >= baseline, isTrue);
      if (harmCount(seed) > baseline) harmoniumEverAddsGraces = true;
    }
    expect(harmoniumEverAddsGraces, isTrue,
        reason: 'harmonium should add grace notes for at least one seed');
  });

  test('sitar gets per-note micro-detune + meend glides; harmonium gets neither',
      () {
    final doc = parseNagma(Config.defaultNagma, taal: 'teentaal');
    final sitar =
        realize(doc, bpm: 80, sa: 'C', instrument: 'sitar', seed: 1).events;
    final harm =
        realize(doc, bpm: 80, sa: 'C', instrument: 'harmonium', seed: 1).events;

    // Micro-detune (fake round-robin): essentially every plucked note is detuned.
    expect(sitar.where((e) => e.microCents != 0.0).length,
        greaterThan(sitar.length ~/ 2));
    // Meend: at least some ascending steps glide into their note.
    expect(sitar.any((e) => e.glideFromMidi != null), isTrue);
    // A glide only ever starts within ±2 semitones (fits the bend range) and
    // ascends into the note (real sitar pulls the pitch up).
    for (final e in sitar.where((e) => e.glideFromMidi != null)) {
      final step = e.midi - e.glideFromMidi!;
      expect(step, inInclusiveRange(1, 2));
      expect(e.glideS, greaterThan(0));
    }

    // Harmonium is untouched: no detune, no glides, and it keeps its reed swell.
    expect(harm.every((e) => e.microCents == 0.0 && e.glideFromMidi == null),
        isTrue);
    expect(harm.any((e) => e.swell > 0), isTrue);
  });

  test('scoreToMidi emits pitch-bend for sitar, none for harmonium', () {
    final doc = parseNagma(Config.defaultNagma, taal: 'teentaal');
    // Count pitch-bend (0xE0..0xEF) status messages by parsing the track.
    int pitchBends(List<int> midi) => _countStatus(midi, 0xE0);
    final sitarMidi =
        scoreToMidi(realize(doc, bpm: 80, sa: 'C', instrument: 'sitar', seed: 1));
    final harmMidi = scoreToMidi(
        realize(doc, bpm: 80, sa: 'C', instrument: 'harmonium', seed: 1));
    expect(pitchBends(sitarMidi), greaterThan(0));
    expect(pitchBends(harmMidi), equals(0));
  });
}

/// Count channel-voice messages with the given status nibble by walking the
/// single MTrk (handles var-len delta times, running status, and meta/sysex).
int _countStatus(List<int> bytes, int statusNibble) {
  // find "MTrk"
  var i = 0;
  while (i + 4 <= bytes.length &&
      !(bytes[i] == 0x4D &&
          bytes[i + 1] == 0x54 &&
          bytes[i + 2] == 0x72 &&
          bytes[i + 3] == 0x6B)) {
    i++;
  }
  i += 8; // skip "MTrk" + 4-byte length
  var running = 0;
  var count = 0;
  int readVar() {
    var v = 0;
    while (true) {
      final b = bytes[i++];
      v = (v << 7) | (b & 0x7F);
      if (b & 0x80 == 0) break;
    }
    return v;
  }

  while (i < bytes.length) {
    readVar(); // delta time
    var status = bytes[i];
    if (status == 0xFF) {
      i++;
      i++; // meta type
      final len = readVar();
      i += len;
      continue;
    } else if (status == 0xF0 || status == 0xF7) {
      i++;
      final len = readVar();
      i += len;
      continue;
    }
    if (status & 0x80 != 0) {
      running = status;
      i++;
    } else {
      status = running; // running status: reuse, data byte stays
    }
    if ((status & 0xF0) == statusNibble) count++;
    // data-byte count: program/channel-pressure take 1, everything else 2
    final hi = status & 0xF0;
    i += (hi == 0xC0 || hi == 0xD0) ? 1 : 2;
  }
  return count;
}
