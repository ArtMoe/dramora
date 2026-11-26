import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../widgets/secure_cover.dart';

/// Native ActivityKit bridge used by the playback and download experiences.
///
/// The previous implementation depended on the plugin's App Group/UserDefaults
/// transport. Sideloaded builds do not always receive that entitlement, which
/// left the Dynamic Island without artwork. This bridge sends the cover bytes
/// through the method channel and renders them from ActivityKit ContentState.
abstract final class HgLiveActivityService {
  static const _native = MethodChannel('com.guomu.huangguo/liveactivity');
  static final _covers = <String, Uint8List>{};
  static final _failedCoverAt = <String, DateTime>{};
  static Future<void>? _initializing;
  static Future<void> _updates = Future<void>.value();
  static bool _initialized = false;
  static final _generations = <String, int>{};

  @visibleForTesting
  static Future<Uint8List> Function(String url)? coverLoaderForTesting;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> initialize() async {
    if (!_supported || _initialized) return;
    await (_initializing ??= _initialize());
  }

  static Future<void> _initialize() async {
    try {
      final available = await _native.invokeMethod<bool>('isAvailable');
      _initialized = available == true;
    } catch (error) {
      debugPrint('Guomu live activity init skipped: $error');
    } finally {
      _initializing = null;
    }
  }

  static Future<Uint8List?> _coverBytes(String cover) async {
    if (cover.trim().isEmpty) return null;
    final failedAt = _failedCoverAt[cover];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(minutes: 1)) {
      return null;
    }
    final cached = _covers[cover];
    if (cached != null) return cached;
    try {
      final load = coverLoaderForTesting ?? HgCoverRepository.instance.load;
      final bytes = await load(cover).timeout(const Duration(seconds: 8));
      if (bytes.isEmpty) return null;
      _failedCoverAt.remove(cover);
      _covers[cover] = bytes;
      while (_covers.length > 8) {
        _covers.remove(_covers.keys.first);
      }
      return bytes;
    } catch (error) {
      _failedCoverAt[cover] = DateTime.now();
      debugPrint('Guomu live activity cover skipped: $error');
      return null;
    }
  }

  /// Produces a local JPEG used by Now Playing and notification attachments.
  static Future<String> prepareArtworkPath({
    required int videoId,
    required String cover,
  }) async {
    if (!_supported || cover.trim().isEmpty) return '';
    final bytes = await _coverBytes(cover);
    if (bytes == null || bytes.isEmpty) return '';
    try {
      final path = await _native.invokeMethod<String>('prepareArtwork', {
        'key': 'video-$videoId',
        'bytes': bytes,
      });
      return path?.trim() ?? '';
    } catch (error) {
      debugPrint('Guomu artwork preparation skipped: $error');
      return '';
    }
  }

  static Future<void> showOrUpdate({
    required int videoId,
    required String title,
    required String cover,
    required List<String> tags,
    required int episode,
    required int totalEpisodes,
    required double progress,
    required String deepLink,
  }) {
    return _enqueue({
      'activityKey': 'guomu-now-playing',
      'kind': 'playback',
      'title': title,
      'subtitle': tags.isEmpty ? '黄果短剧' : tags.take(2).join(' · '),
      'episode': episode,
      'totalEpisodes': totalEpisodes,
      'episodeLabel':
          '观看至 $episode${totalEpisodes > 0 ? '/$totalEpisodes' : ''} 集',
      'detail': '正在播放',
      'progress': progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0,
      'deepLink': deepLink,
      'cover': cover,
    });
  }

  static Future<void> showDownload({
    required int videoId,
    required String title,
    required String cover,
    required List<String> tags,
    required int episode,
    required int totalEpisodes,
    required double progress,
    required String detail,
    required String deepLink,
  }) {
    return _enqueue({
      'activityKey': 'guomu-download-$videoId',
      'kind': 'download',
      'title': title,
      'subtitle': tags.isEmpty ? '黄果短剧' : tags.take(2).join(' · '),
      'episode': episode,
      'totalEpisodes': totalEpisodes,
      'episodeLabel': totalEpisodes > 0
          ? '正在缓存 第 $episode/$totalEpisodes 集'
          : '正在缓存第 $episode 集',
      'detail': detail,
      'progress': progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0,
      'deepLink': deepLink,
      'cover': cover,
    });
  }

  static Future<void> _enqueue(Map<String, Object?> args) {
    if (!_supported) return Future<void>.value();
    final activityKey = args['activityKey']?.toString() ?? '';
    final generation = _generations[activityKey] ?? 0;
    _updates = _updates
        .catchError((Object _) {})
        .then((_) async {
          if (generation != (_generations[activityKey] ?? 0)) return;
          await initialize();
          if (!_initialized || generation != (_generations[activityKey] ?? 0)) {
            return;
          }
          final cover = args.remove('cover')?.toString() ?? '';
          final bytes = await _coverBytes(cover);
          if (generation != (_generations[activityKey] ?? 0)) return;
          await _native.invokeMethod<String>('showOrUpdate', {
            ...args,
            'coverBytes': bytes,
          });
        })
        .catchError((Object error) {
          debugPrint('Guomu live activity update skipped: $error');
        });
    return _updates;
  }

  static Future<void> end() => _end('guomu-now-playing');

  static Future<void> endDownload(int videoId) =>
      _end('guomu-download-$videoId');

  static Future<void> _end(String activityKey) {
    if (!_supported) return Future<void>.value();
    _generations[activityKey] = (_generations[activityKey] ?? 0) + 1;
    _updates = _updates
        .catchError((Object _) {})
        .then((_) async {
          await initialize();
          if (!_initialized) return;
          await _native.invokeMethod<void>('end', {'activityKey': activityKey});
        })
        .catchError((Object error) {
          debugPrint('Guomu live activity end skipped: $error');
        });
    return _updates;
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    if (_supported) {
      await _native
          .invokeMethod<void>('end', {'activityKey': ''})
          .catchError((Object _) {});
    }
    _generations.clear();
    _updates = Future<void>.value();
    _initialized = false;
    _initializing = null;
    _covers.clear();
    _failedCoverAt.clear();
    coverLoaderForTesting = null;
  }
}
