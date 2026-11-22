import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Coordinates one process-wide screen wake lock from player state.
///
/// Video controllers are prefetched around the current episode. Switching the
/// lock directly from individual controllers lets an inactive prefetch release
/// the lock while the visible episode is still playing. This coordinator keeps
/// the rule explicit: only an active player in the foreground may hold the
/// screen awake.
abstract final class HgWakeLockService {
  static bool _playbackActive = false;
  static bool _applicationActive = true;
  static bool? _applied;
  static Future<void> _tail = Future<void>.value();

  @visibleForTesting
  static Future<void> Function({required bool enable})? toggleForTesting;

  static bool get requested => _playbackActive && _applicationActive;

  static Future<void> update({
    required bool playing,
    required bool applicationActive,
  }) {
    _playbackActive = playing;
    _applicationActive = applicationActive;
    return _sync();
  }

  static Future<void> release() =>
      update(playing: false, applicationActive: false);

  static Future<void> _sync() {
    _tail = _tail.catchError((Object _) {}).then((_) async {
      final next = requested;
      if (_applied == next) return;
      try {
        final toggle = toggleForTesting ?? WakelockPlus.toggle;
        await toggle(enable: next);
        _applied = next;
      } catch (error) {
        // A container or platform without a wake lock must never interrupt
        // video playback, but the state remains unapplied so a later lifecycle
        // event can retry.
        debugPrint('Guomu wake lock skipped: $error');
      }
    });
    return _tail;
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _tail.catchError((Object _) {});
    _playbackActive = false;
    _applicationActive = true;
    _applied = null;
    _tail = Future<void>.value();
    toggleForTesting = null;
  }
}
