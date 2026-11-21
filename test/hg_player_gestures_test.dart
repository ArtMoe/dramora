import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/utils/hg_player_gestures.dart';

void main() {
  test('horizontal seek maps drag distance across the full episode', () {
    expect(
      hgHorizontalSeekTarget(
        start: const Duration(seconds: 30),
        duration: const Duration(seconds: 120),
        deltaPixels: 100,
        width: 400,
      ),
      const Duration(seconds: 60),
    );
    expect(
      hgHorizontalSeekTarget(
        start: const Duration(seconds: 30),
        duration: const Duration(seconds: 120),
        deltaPixels: -100,
        width: 400,
      ),
      Duration.zero,
    );
  });

  test('horizontal seek clamps both boundaries and invalid geometry', () {
    expect(
      hgHorizontalSeekTarget(
        start: const Duration(seconds: 90),
        duration: const Duration(seconds: 120),
        deltaPixels: 1000,
        width: 400,
      ),
      const Duration(seconds: 120),
    );
    expect(
      hgHorizontalSeekTarget(
        start: const Duration(milliseconds: 500),
        duration: const Duration(seconds: 1),
        deltaPixels: 0,
        width: 0,
      ),
      const Duration(milliseconds: 500),
    );
    expect(
      hgHorizontalSeekTarget(
        start: Duration.zero,
        duration: Duration.zero,
        deltaPixels: 30,
        width: 100,
      ),
      Duration.zero,
    );
  });
}
