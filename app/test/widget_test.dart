// Unit tests for the audio-clock -> matra math (LoopPosition). This is the
// trickiest pure logic in the app and runs with no device/platform channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/services/loop_player.dart';

void main() {
  // A 4-avartan Teentaal super-loop: 16 matras/cycle. Pick 100 frames/matra ->
  // 1600 frames/avartan -> 6400 frames total, so the arithmetic is obvious.
  const avartans = 4;
  const matraCount = 16;
  const framesPerMatra = 100;
  const framesPerAvartan = framesPerMatra * matraCount; // 1600
  const loopFrames = framesPerAvartan * avartans; // 6400

  LoopPosition at(int frame) => LoopPosition(
        frame: frame,
        loopFrames: loopFrames,
        sampleRate: 44100,
        playing: true,
      );

  test('sam is matra 0, avartan 0, phase 0', () {
    final p = at(0);
    expect(p.matraIndex(avartans, matraCount), 0);
    expect(p.avartanIndex(avartans), 0);
    expect(p.avartanPhase(avartans, matraCount), 0);
  });

  test('matra advances within an avartan', () {
    // 150 frames in = 1.5 matras -> floor -> matra index 1.
    expect(at(150).matraIndex(avartans, matraCount), 1);
    // Last matra of the cycle (frame 1550 = matra 15.5).
    expect(at(1550).matraIndex(avartans, matraCount), 15);
  });

  test('avartan index tracks which cycle of the super-loop is playing', () {
    expect(at(0).avartanIndex(avartans), 0);
    expect(at(1700).avartanIndex(avartans), 1);
    expect(at(loopFrames - 1).avartanIndex(avartans), 3);
  });

  test('phase resets each avartan, matra is cycle-relative', () {
    // Frame 1700 -> 100 frames into avartan 1 -> phase 0.0625, matra 1.
    final p = at(1700);
    expect(p.avartanPhase(avartans, matraCount), closeTo(0.0625, 1e-9));
    expect(p.matraIndex(avartans, matraCount), 1);
  });

  test('matra index never exceeds the taal on boundary frames', () {
    expect(at(loopFrames - 1).matraIndex(avartans, matraCount), 15);
  });

  test('empty loop is safe (no divide-by-zero)', () {
    const p = LoopPosition(frame: 0, loopFrames: 0, sampleRate: 44100, playing: false);
    expect(p.matraIndex(avartans, matraCount), 0);
    expect(p.avartanPhase(avartans, matraCount), 0);
    expect(p.avartanIndex(avartans), 0);
  });
}
