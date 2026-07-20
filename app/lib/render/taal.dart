// Taal definitions for the render pipeline.
//
// Dart port of core/src/nagma_core/taal.py. This is the render-side model
// (matra marks, vibhag structure) used by the parser/compiler. The display-only
// UI copy lives in lib/taal.dart; keep them consistent but separate.
//
// A taal is a sequence of vibhags (measures); each vibhag has a matra count and
// a clap type (taali/khaali/sam). Sam is matra 0.

class Vibhag {
  final int length; // number of matras in this vibhag
  final String clap; // 'taali' | 'khaali' | 'sam'
  const Vibhag({required this.length, required this.clap});
}

class Taal {
  final String name;
  final List<Vibhag> vibhags;
  // Rupak's cycle starts ON a khaali: matra 0 is the origin (sam) for timing
  // and the velocity swell, but is *displayed* as an open (khaali) beat. The
  // engine still treats matra 0 as 'sam'; only the UI reads this flag.
  final bool samIsKhaali;
  const Taal({
    required this.name,
    required this.vibhags,
    this.samIsKhaali = false,
  });

  int get matraCount => vibhags.fold(0, (a, v) => a + v.length);

  List<int> get vibhagLengths => vibhags.map((v) => v.length).toList();

  /// Per-matra structural label: 'sam' | 'taali' | 'khaali' | 'plain'.
  /// The first matra of each vibhag carries its clap; the rest are 'plain'.
  /// Matra 0 is always 'sam'.
  List<String> matraMarks() {
    final marks = <String>[];
    for (final v in vibhags) {
      marks.add(v.clap);
      for (var i = 1; i < v.length; i++) {
        marks.add('plain');
      }
    }
    return marks;
  }
}

/// Teentaal: 16 matras, 4 vibhags of 4. Taali on 1/5/13, khaali on 9
/// (0-based: sam=0, taali=4, khaali=8, taali=12).
const Taal teentaal = Taal(
  name: 'teentaal',
  vibhags: [
    Vibhag(length: 4, clap: 'sam'),
    Vibhag(length: 4, clap: 'taali'),
    Vibhag(length: 4, clap: 'khaali'),
    Vibhag(length: 4, clap: 'taali'),
  ],
);

// --- Additional taals (standard thekas; see core/.../taal.py for 0-based marks).

/// Dadra: 6 matras, 3+3. sam=0, khaali=3.
const Taal dadra = Taal(
  name: 'dadra',
  vibhags: [
    Vibhag(length: 3, clap: 'sam'),
    Vibhag(length: 3, clap: 'khaali'),
  ],
);

/// Rupak: 7 matras, 3+2+2. Sam is a khaali (open); taali on 4 and 6.
const Taal rupak = Taal(
  name: 'rupak',
  vibhags: [
    Vibhag(length: 3, clap: 'sam'),
    Vibhag(length: 2, clap: 'taali'),
    Vibhag(length: 2, clap: 'taali'),
  ],
  samIsKhaali: true,
);

/// Jhaptaal: 10 matras, 2+3+2+3. sam=0, taali=2, khaali=5, taali=7.
const Taal jhaptaal = Taal(
  name: 'jhaptaal',
  vibhags: [
    Vibhag(length: 2, clap: 'sam'),
    Vibhag(length: 3, clap: 'taali'),
    Vibhag(length: 2, clap: 'khaali'),
    Vibhag(length: 3, clap: 'taali'),
  ],
);

/// Ektaal: 12 matras, 6x2. sam=0, khaali=2, taali=4, khaali=6, taali=8, taali=10.
const Taal ektaal = Taal(
  name: 'ektaal',
  vibhags: [
    Vibhag(length: 2, clap: 'sam'),
    Vibhag(length: 2, clap: 'khaali'),
    Vibhag(length: 2, clap: 'taali'),
    Vibhag(length: 2, clap: 'khaali'),
    Vibhag(length: 2, clap: 'taali'),
    Vibhag(length: 2, clap: 'taali'),
  ],
);

/// Dhamar: 14 matras, 5+2+3+4. sam=0, taali=5, khaali=7, taali=10.
const Taal dhamar = Taal(
  name: 'dhamar',
  vibhags: [
    Vibhag(length: 5, clap: 'sam'),
    Vibhag(length: 2, clap: 'taali'),
    Vibhag(length: 3, clap: 'khaali'),
    Vibhag(length: 4, clap: 'taali'),
  ],
);

/// Pancham Sawari: 15 matras, 3+4+4+4. sam=0, taali=3, khaali=7, taali=11.
const Taal panchamSawari = Taal(
  name: 'pancham_sawari',
  vibhags: [
    Vibhag(length: 3, clap: 'sam'),
    Vibhag(length: 4, clap: 'taali'),
    Vibhag(length: 4, clap: 'khaali'),
    Vibhag(length: 4, clap: 'taali'),
  ],
);

const Map<String, Taal> _taals = {
  'teentaal': teentaal,
  'dadra': dadra,
  'rupak': rupak,
  'jhaptaal': jhaptaal,
  'ektaal': ektaal,
  'dhamar': dhamar,
  'pancham_sawari': panchamSawari,
};

Taal getTaal(String name) {
  final t = _taals[name];
  if (t == null) {
    final avail = _taals.keys.toList()..sort();
    throw ArgumentError("Unknown taal '$name'. Available: ${avail.join(', ')}");
  }
  return t;
}
