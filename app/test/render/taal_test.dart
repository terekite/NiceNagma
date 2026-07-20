// Mirrors core/tests/test_taal.py — keeps the Dart taal port faithful to core.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/taal.dart';

const s = 'sam', t = 'taali', k = 'khaali', p = 'plain';

final expected = <String, Map<String, dynamic>>{
  'teentaal': {
    'matraCount': 16,
    'vibhagLengths': [4, 4, 4, 4],
    'marks': [s, p, p, p, t, p, p, p, k, p, p, p, t, p, p, p],
    'samIsKhaali': false,
  },
  'dadra': {
    'matraCount': 6,
    'vibhagLengths': [3, 3],
    'marks': [s, p, p, k, p, p],
    'samIsKhaali': false,
  },
  'rupak': {
    'matraCount': 7,
    'vibhagLengths': [3, 2, 2],
    'marks': [s, p, p, t, p, t, p],
    'samIsKhaali': true,
  },
  'jhaptaal': {
    'matraCount': 10,
    'vibhagLengths': [2, 3, 2, 3],
    'marks': [s, p, t, p, p, k, p, t, p, p],
    'samIsKhaali': false,
  },
  'ektaal': {
    'matraCount': 12,
    'vibhagLengths': [2, 2, 2, 2, 2, 2],
    'marks': [s, p, k, p, t, p, k, p, t, p, t, p],
    'samIsKhaali': false,
  },
  'dhamar': {
    'matraCount': 14,
    'vibhagLengths': [5, 2, 3, 4],
    'marks': [s, p, p, p, p, t, p, k, p, p, t, p, p, p],
    'samIsKhaali': false,
  },
  'pancham_sawari': {
    'matraCount': 15,
    'vibhagLengths': [3, 4, 4, 4],
    'marks': [s, p, p, t, p, p, p, k, p, p, p, t, p, p, p],
    'samIsKhaali': false,
  },
};

void main() {
  expected.forEach((name, exp) {
    test('taal structure: $name', () {
      final taal = getTaal(name);
      expect(taal.name, name);
      expect(taal.matraCount, exp['matraCount']);
      expect(taal.vibhagLengths, exp['vibhagLengths']);
      expect(taal.matraMarks(), exp['marks']);
      expect(taal.samIsKhaali, exp['samIsKhaali']);
      expect(taal.matraMarks().length, taal.matraCount);
    });

    test('matra 0 is always the sam origin: $name', () {
      // Even Rupak keeps matra 0 as 'sam' for the engine; the khaali is display.
      expect(getTaal(name).matraMarks()[0], 'sam');
    });
  });

  test('unknown taal throws', () {
    expect(() => getTaal('nonexistent'), throwsArgumentError);
  });
}
