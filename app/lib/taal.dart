// Taal structure for the UI. Mirrors core/src/nagma_core/taal.py — the app never
// imports core, so this is a small hand-kept copy of the taals the MVP ships.
// Sam is matra 0. Each taal carries its per-vibhag clap so the cycle wheel can
// render sam/taali/khaali dots for any division (not just Teentaal's 4x4).

enum Clap { sam, taali, khaali, plain }

class Taal {
  final String name;

  /// Human-facing label shown in the UI (the picker + the chip).
  final String label;

  final int matraCount;
  final List<int> vibhagLengths;

  /// Clap carried by the FIRST matra of each vibhag, in order. Length equals
  /// vibhagLengths.length. The remaining matras of a vibhag are Clap.plain.
  final List<Clap> vibhagClaps;

  /// Rupak: matra 0 is the origin (sam) for timing/wheel-sweep but is *displayed*
  /// as an open (khaali) dot. Purely a display flag; the engine treats it as sam.
  final bool samIsKhaali;

  const Taal({
    required this.name,
    required this.label,
    required this.matraCount,
    required this.vibhagLengths,
    required this.vibhagClaps,
    this.samIsKhaali = false,
  });

  /// Per-matra structural label; the first matra of each vibhag carries its clap.
  List<Clap> get matraMarks {
    final marks = <Clap>[];
    for (var i = 0; i < vibhagLengths.length; i++) {
      marks.add(i < vibhagClaps.length ? vibhagClaps[i] : Clap.plain);
      for (var j = 1; j < vibhagLengths[i]; j++) {
        marks.add(Clap.plain);
      }
    }
    return marks;
  }

  static const teentaal = Taal(
    name: 'teentaal',
    label: 'Teentaal',
    matraCount: 16,
    vibhagLengths: [4, 4, 4, 4],
    vibhagClaps: [Clap.sam, Clap.taali, Clap.khaali, Clap.taali],
  );

  static const dadra = Taal(
    name: 'dadra',
    label: 'Dadra',
    matraCount: 6,
    vibhagLengths: [3, 3],
    vibhagClaps: [Clap.sam, Clap.khaali],
  );

  static const rupak = Taal(
    name: 'rupak',
    label: 'Rupak',
    matraCount: 7,
    vibhagLengths: [3, 2, 2],
    vibhagClaps: [Clap.sam, Clap.taali, Clap.taali],
    samIsKhaali: true,
  );

  static const jhaptaal = Taal(
    name: 'jhaptaal',
    label: 'Jhaptaal',
    matraCount: 10,
    vibhagLengths: [2, 3, 2, 3],
    vibhagClaps: [Clap.sam, Clap.taali, Clap.khaali, Clap.taali],
  );

  static const ektaal = Taal(
    name: 'ektaal',
    label: 'Ektaal',
    matraCount: 12,
    vibhagLengths: [2, 2, 2, 2, 2, 2],
    vibhagClaps: [
      Clap.sam,
      Clap.khaali,
      Clap.taali,
      Clap.khaali,
      Clap.taali,
      Clap.taali,
    ],
  );

  static const dhamar = Taal(
    name: 'dhamar',
    label: 'Dhamar',
    matraCount: 14,
    vibhagLengths: [5, 2, 3, 4],
    vibhagClaps: [Clap.sam, Clap.taali, Clap.khaali, Clap.taali],
  );

  static const panchamSawari = Taal(
    name: 'pancham_sawari',
    label: 'Pancham Sawari',
    matraCount: 15,
    vibhagLengths: [3, 4, 4, 4],
    vibhagClaps: [Clap.sam, Clap.taali, Clap.khaali, Clap.taali],
  );

  /// All taals the MVP ships, in display order (teentaal first as the default).
  static const List<Taal> all = [
    teentaal,
    dadra,
    rupak,
    jhaptaal,
    ektaal,
    dhamar,
    panchamSawari,
  ];

  static final Map<String, Taal> _byName = {for (final t in all) t.name: t};

  static Taal byName(String name) => _byName[name] ?? teentaal;
}
