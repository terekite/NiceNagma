// Mirrors render/tests/test_midi.py. Parses the SMF bytes our writer produces
// back into absolute-timed messages to verify channel allocation + CC11 swells.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/compiler.dart';
import 'package:nicenagma/render/midi.dart';
import 'package:nicenagma/render/parser.dart';

const stock = "S r g m | P m g r | P d n S' | n d P m";

class Msg {
  final int absTick;
  final String type; // note_on | note_off | control_change | program_change
  final int channel;
  final int data1;
  final int data2;
  Msg(this.absTick, this.type, this.channel, this.data1, this.data2);
}

/// Minimal SMF-format-0 reader for a single track. Our writer never uses running
/// status, but handle it defensively anyway.
List<Msg> parseSmf(Uint8List bytes) {
  var p = 0;
  int u32() {
    final v = (bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3];
    p += 4;
    return v;
  }

  // Header: "MThd" len(6) format ntracks division
  p = 8; // skip "MThd" + length
  p += 6; // skip format(2) ntracks(2) division(2)
  // Track: "MTrk" length
  p += 4; // "MTrk"
  final trackLen = u32();
  final end = p + trackLen;

  int readVarLen() {
    var value = 0;
    while (true) {
      final b = bytes[p++];
      value = (value << 7) | (b & 0x7F);
      if (b & 0x80 == 0) break;
    }
    return value;
  }

  final msgs = <Msg>[];
  var t = 0;
  var runningStatus = 0;
  while (p < end) {
    t += readVarLen();
    var status = bytes[p];
    if (status & 0x80 != 0) {
      p++;
      runningStatus = status;
    } else {
      status = runningStatus; // running status: reuse last status byte
    }

    if (status == 0xFF) {
      p++; // meta type
      final len = readVarLen();
      p += len; // skip meta payload
      continue;
    }
    final high = status & 0xF0;
    final ch = status & 0x0F;
    switch (high) {
      case 0x80:
        final n = bytes[p++], v = bytes[p++];
        msgs.add(Msg(t, 'note_off', ch, n, v));
        break;
      case 0x90:
        final n = bytes[p++], v = bytes[p++];
        msgs.add(Msg(t, v > 0 ? 'note_on' : 'note_off', ch, n, v));
        break;
      case 0xB0:
        final c = bytes[p++], v = bytes[p++];
        msgs.add(Msg(t, 'control_change', ch, c, v));
        break;
      case 0xC0:
        final prog = bytes[p++];
        msgs.add(Msg(t, 'program_change', ch, prog, 0));
        break;
      case 0xA0:
      case 0xE0:
        p += 2;
        break;
      case 0xD0:
        p += 1;
        break;
      default:
        p += 1;
    }
  }
  return msgs;
}

List<Msg> buildMidi({double bpm = 70, int avartans = 2}) {
  final score = compileScore(parseNagma(stock), bpm: bpm, sa: 'C', avartans: avartans, seed: 3);
  return parseSmf(scoreToMidi(score));
}

void main() {
  test('no overlapping notes share a channel', () {
    final msgs = buildMidi();
    // Reconstruct (on,off) intervals per channel.
    final open = <String, int>{};
    final intervals = <int, List<List<int>>>{};
    for (final m in msgs) {
      if (m.type == 'note_on') {
        open['${m.channel}/${m.data1}'] = m.absTick;
      } else if (m.type == 'note_off') {
        final key = '${m.channel}/${m.data1}';
        if (open.containsKey(key)) {
          intervals.putIfAbsent(m.channel, () => []).add([open.remove(key)!, m.absTick]);
        }
      }
    }
    for (final ivs in intervals.values) {
      ivs.sort((a, b) => a[0].compareTo(b[0]));
      for (var i = 0; i + 1 < ivs.length; i++) {
        expect(ivs[i + 1][0], greaterThanOrEqualTo(ivs[i][1]),
            reason: 'overlapping notes on a channel');
      }
    }
  });

  test('channel 9 never used', () {
    for (final m in buildMidi()) {
      if (m.type == 'note_on' || m.type == 'note_off') {
        expect(m.channel, isNot(9));
      }
    }
  });

  test('cc11 swell emitted', () {
    final cc11 = buildMidi().where((m) => m.type == 'control_change' && m.data1 == 11).toList();
    expect(cc11, isNotEmpty);
    expect(cc11.any((m) => m.data2 < 127), isTrue, reason: 'swell should dip expression below full');
  });

  test('program change on used channels', () {
    final msgs = buildMidi();
    final progs = msgs.where((m) => m.type == 'program_change').map((m) => m.channel).toSet();
    final notes = msgs.where((m) => m.type == 'note_on').map((m) => m.channel).toSet();
    expect(notes.difference(progs), isEmpty, reason: 'every channel that plays notes needs a program_change');
  });
}
