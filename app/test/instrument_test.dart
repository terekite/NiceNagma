// Sarangi is a selectable melodic instrument alongside the harmonium. These are
// pure-Dart checks (no device/platform channels): the instrument is offered in the
// config and it participates in the render cache key, so switching instruments is a
// genuine re-render (never a replay of the other instrument's cached loop).

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/config.dart';
import 'package:nicenagma/services/render_client.dart'; // re-exports RenderRequest

void main() {
  test('config offers harmonium and sarangi', () {
    expect(Config.instruments, contains('harmonium'));
    expect(Config.instruments, contains('sarangi'));
    // the default must be one of the offered instruments
    expect(Config.instruments, contains(Config.defaultInstrument));
  });

  RenderRequest req(String instrument) => RenderRequest(
        nagmaText: Config.defaultNagma,
        bpm: Config.defaultBpm,
        sa: Config.defaultSa,
        instrument: instrument,
      );

  test('instrument is part of the render request payload', () {
    expect(req('sarangi').toJson()['instrument'], 'sarangi');
  });

  test('changing instrument changes the cache key (forces a re-render)', () {
    final harmonium = req('harmonium').cacheKey();
    final sarangi = req('sarangi').cacheKey();
    expect(harmonium, isNot(equals(sarangi)));
  });

  test('same instrument + params yields a stable cache key (cache hit)', () {
    expect(req('sarangi').cacheKey(), equals(req('sarangi').cacheKey()));
  });
}
