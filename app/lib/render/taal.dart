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
  const Taal({required this.name, required this.vibhags});

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

const Map<String, Taal> _taals = {'teentaal': teentaal};

Taal getTaal(String name) {
  final t = _taals[name];
  if (t == null) {
    final avail = _taals.keys.toList()..sort();
    throw ArgumentError("Unknown taal '$name'. Available: ${avail.join(', ')}");
  }
  return t;
}
