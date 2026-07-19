// Unit tests for parseTempoInput — the pure parse/validate step behind the
// tap-to-enter tempo dialog on the BPM chip. Range-clamping (e.g. 500 -> 300,
// 10 -> 30) is intentionally NOT tested here: that is controller.setBpm's job,
// covered by its own clamp to Config.minBpm/maxBpm. This helper only turns free
// text into a positive number (or null so the dialog can ignore it).

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/screens/player_screen.dart';

void main() {
  test('parses a plain integer', () {
    expect(parseTempoInput('81'), 81);
  });

  test('trims surrounding whitespace', () {
    expect(parseTempoInput(' 120 '), 120);
  });

  test('parses a decimal', () {
    expect(parseTempoInput('88.5'), 88.5);
  });

  test('accepts out-of-range values (clamping is setBpm\'s job)', () {
    expect(parseTempoInput('500'), 500);
    expect(parseTempoInput('10'), 10);
  });

  test('rejects empty and non-numeric input', () {
    expect(parseTempoInput(''), isNull);
    expect(parseTempoInput('   '), isNull);
    expect(parseTempoInput('abc'), isNull);
    expect(parseTempoInput('12x'), isNull);
  });

  test('rejects non-positive input', () {
    expect(parseTempoInput('0'), isNull);
    expect(parseTempoInput('-5'), isNull);
  });
}
