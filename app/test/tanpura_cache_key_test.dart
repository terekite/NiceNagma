// TanpuraRequest cache key: stable for identical inputs, distinct when any
// tuning-affecting field changes (so a Sa/first-string change re-renders).

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/services/tanpura_renderer.dart';

void main() {
  const base = TanpuraRequest(sa: 'D', firstStringSwar: 'P');

  test('identical inputs -> identical key', () {
    const same = TanpuraRequest(sa: 'D', firstStringSwar: 'P');
    expect(base.cacheKey(), same.cacheKey());
  });

  test('key changes with Sa', () {
    const other = TanpuraRequest(sa: 'E', firstStringSwar: 'P');
    expect(base.cacheKey(), isNot(other.cacheKey()));
  });

  test('key changes with first-string tuning', () {
    const other = TanpuraRequest(sa: 'D', firstStringSwar: 'm');
    expect(base.cacheKey(), isNot(other.cacheKey()));
  });

  test('key changes with seed / cycle params', () {
    expect(
        base.cacheKey(),
        isNot(const TanpuraRequest(sa: 'D', firstStringSwar: 'P', seed: 1)
            .cacheKey()));
    expect(
        base.cacheKey(),
        isNot(const TanpuraRequest(sa: 'D', firstStringSwar: 'P', cycleCount: 12)
            .cacheKey()));
    expect(
        base.cacheKey(),
        isNot(const TanpuraRequest(
                sa: 'D', firstStringSwar: 'P', cycleLengthS: 5.0)
            .cacheKey()));
  });

  test('key is a 24-char hex digest', () {
    expect(base.cacheKey().length, 24);
    expect(RegExp(r'^[0-9a-f]{24}$').hasMatch(base.cacheKey()), isTrue);
  });
}
