// ExpressiveScore -> Standard MIDI File bytes.
//
// Dart port of render/src/nagma_render/midi.py. The score carries absolute-second
// onsets; we pick a fixed tempo/PPQ and convert seconds->ticks losslessly. The
// native AVAudioSequencer then plays this MIDI through the sampler.
//
// Beyond note on/off, this emits per-note CC11 (expression) swells — a note
// starts at (1-swell) of full and rises to full over its attack. Because CC is
// per-CHANNEL, notes are spread across the MIDI channels by a greedy allocator so
// one note's swell never bleeds onto an overlapping note.

import 'dart:typed_data';

import 'models.dart';

// Fixed conversion basis. 500000 us/beat = 120 BPM = 0.5 s/beat.
const int _usPerBeat = 500000;
const double _secPerBeat = _usPerBeat / 1000000.0;
const int _ticksPerBeat = 960;

/// Our multisampled harmonium SF2 puts its single preset at bank 0, program 0.
const int defaultProgram = 0;

// Channels a note may use — all except 9 (GM percussion).
final List<int> _channels = [for (var c = 0; c < 16; c++) if (c != 9) c];

/// A voice keeps sounding ~this long after note-off (SF2 release env), so a
/// channel isn't reused until then, or the reused channel's CC11 would bend the
/// previous note's release tail.
const double _releaseTailS = 0.35;

// Swell attack shaping.
const double _swellAttackFrac = 0.5;
const double _swellAttackMaxS = 0.6;
const int _swellSteps = 8;

int _secToTicks(double seconds) =>
    (seconds / _secPerBeat * _ticksPerBeat).round();

/// Greedy interval colouring: lowest channel free at startS; else the one that
/// frees earliest. Updates freeAt for the chosen channel.
int _allocateChannel(Map<int, double> freeAt, double startS, double endS) {
  int? ch;
  for (final c in _channels) {
    if (freeAt[c]! <= startS + 1e-9) {
      ch = c;
      break;
    }
  }
  ch ??= _channels.reduce((a, b) => freeAt[a]! <= freeAt[b]! ? a : b);
  freeAt[ch] = endS + _releaseTailS;
  return ch;
}

/// CC11 (tick, value) pairs: start at (1-depth)*127, ramp to 127 over the attack,
/// then hold. Empty depth -> a single full-level set.
List<List<int>> _swellCc(int on, int off, double depth) {
  final start = (127 * (1.0 - depth)).round();
  final pairs = <List<int>>[
    [on, start]
  ];
  if (depth <= 0) return pairs;
  final attack = _min(((off - on) * _swellAttackFrac).toInt(),
      _secToTicks(_swellAttackMaxS));
  for (var k = 1; k <= _swellSteps; k++) {
    final t = on + attack * k ~/ _swellSteps;
    final v = (start + (127 - start) * k / _swellSteps).round();
    pairs.add([t, v]);
  }
  return pairs;
}

int _min(int a, int b) => a < b ? a : b;

/// One MIDI event, pre-sort. order sequences same-tick messages: 0 note_off /
/// program, 1 control_change, 2 note_on.
class _Ev {
  final int tick;
  final int order;
  final String kind; // 'prog' | 'cc' | 'on' | 'off'
  final int channel;
  final int a;
  final int b;
  _Ev(this.tick, this.order, this.kind, this.channel, this.a, this.b);
}

/// Build a single-track, multi-channel Standard MIDI File from the score.
Uint8List scoreToMidi(ExpressiveScore score, {int program = defaultProgram}) {
  final events = <_Ev>[];
  final freeAt = {for (final c in _channels) c: -1e9};
  final used = <int>{};

  final sorted = List<Event>.from(score.events)
    ..sort((x, y) => x.startS.compareTo(y.startS));

  for (final e in sorted) {
    final on = _secToTicks(e.startS);
    var off = _secToTicks(e.startS + e.durS);
    if (off <= on) off = on + 1;
    final ch = _allocateChannel(freeAt, e.startS, e.startS + e.durS);
    used.add(ch);
    for (final tv in _swellCc(on, off, e.swell)) {
      events.add(_Ev(tv[0], 1, 'cc', ch, 11, tv[1]));
    }
    events.add(_Ev(on, 2, 'on', ch, e.midi, e.velocity));
    events.add(_Ev(off, 0, 'off', ch, e.midi, 0));
  }

  for (final ch in used.toList()..sort()) {
    events.add(_Ev(0, 0, 'prog', ch, program, 0));
  }

  events.sort((x, y) {
    final t = x.tick.compareTo(y.tick);
    return t != 0 ? t : x.order.compareTo(y.order);
  });

  // --- serialize the track ------------------------------------------------
  final track = <int>[];
  // set_tempo meta at time 0: FF 51 03 tttttt
  _writeVarLen(track, 0);
  track.addAll([0xFF, 0x51, 0x03,
    (_usPerBeat >> 16) & 0xFF, (_usPerBeat >> 8) & 0xFF, _usPerBeat & 0xFF]);

  var prev = 0;
  for (final ev in events) {
    final dt = ev.tick - prev;
    prev = ev.tick;
    _writeVarLen(track, dt);
    switch (ev.kind) {
      case 'prog':
        track.addAll([0xC0 | ev.channel, ev.a & 0x7F]);
        break;
      case 'cc':
        track.addAll([0xB0 | ev.channel, ev.a & 0x7F, ev.b & 0x7F]);
        break;
      case 'on':
        track.addAll([0x90 | ev.channel, ev.a & 0x7F, ev.b & 0x7F]);
        break;
      case 'off':
        track.addAll([0x80 | ev.channel, ev.a & 0x7F, 0]);
        break;
    }
  }
  // end-of-track meta
  _writeVarLen(track, 0);
  track.addAll([0xFF, 0x2F, 0x00]);

  // --- assemble the file --------------------------------------------------
  final out = <int>[];
  // MThd
  out.addAll([0x4D, 0x54, 0x68, 0x64]); // "MThd"
  _writeUint32(out, 6);
  _writeUint16(out, 0); // format 0
  _writeUint16(out, 1); // one track
  _writeUint16(out, _ticksPerBeat); // division
  // MTrk
  out.addAll([0x4D, 0x54, 0x72, 0x6B]); // "MTrk"
  _writeUint32(out, track.length);
  out.addAll(track);

  return Uint8List.fromList(out);
}

void _writeVarLen(List<int> buf, int value) {
  // MIDI variable-length quantity (big-endian, 7 bits/byte, high bit = continue).
  var v = value;
  if (v < 0) v = 0;
  final bytes = <int>[v & 0x7F];
  v >>= 7;
  while (v > 0) {
    bytes.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  for (var i = bytes.length - 1; i >= 0; i--) {
    buf.add(bytes[i]);
  }
}

void _writeUint32(List<int> buf, int v) {
  buf.addAll([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
}

void _writeUint16(List<int> buf, int v) {
  buf.addAll([(v >> 8) & 0xFF, v & 0xFF]);
}
