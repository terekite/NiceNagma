// Taal structure for the UI. Mirrors core/src/nagma_core/taal.py — the app never
// imports core, so this is a small hand-kept copy of the one taal the MVP ships.
// Sam is matra 0. Teentaal: 16 matras, taali on 1/5/13, khaali on 9 (0-based:
// sam=0, taali=4, khaali=8, taali=12).

enum Clap { sam, taali, khaali, plain }

class Taal {
  final String name;
  final int matraCount;
  final List<int> vibhagLengths;

  const Taal({
    required this.name,
    required this.matraCount,
    required this.vibhagLengths,
  });

  /// Per-matra structural label; the first matra of each vibhag carries its clap.
  List<Clap> get matraMarks {
    final marks = <Clap>[];
    // Teentaal claps per vibhag, in order.
    const claps = [Clap.sam, Clap.taali, Clap.khaali, Clap.taali];
    for (var i = 0; i < vibhagLengths.length; i++) {
      marks.add(i < claps.length ? claps[i] : Clap.taali);
      for (var j = 1; j < vibhagLengths[i]; j++) {
        marks.add(Clap.plain);
      }
    }
    return marks;
  }

  static const teentaal = Taal(
    name: 'teentaal',
    matraCount: 16,
    vibhagLengths: [4, 4, 4, 4],
  );

  static Taal byName(String name) {
    switch (name) {
      case 'teentaal':
        return teentaal;
      default:
        return teentaal;
    }
  }
}
