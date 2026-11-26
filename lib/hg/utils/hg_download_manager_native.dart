import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/hg_api.dart';
import '../services/hg_background_execution_service.dart';
import '../services/hg_live_activity_service.dart';
import '../services/hg_notification_service.dart';
import '../services/hg_settings.dart';
import '../models/hg_download_models.dart';
import '../models/hg_models.dart';
import 'hg_hls_downloader_native.dart';
import '../widgets/secure_cover.dart';

class HgDownloadManager extends ChangeNotifier {
  HgDownloadManager(this._api, this._prefs);

  static const _storageKey = 'guomu.downloads.v1';
  final HgApi _api;
  final SharedPreferences _prefs;
  final List<HgDownloadTask> _tasks = [];
  final Set<int> _queuedVideoIds = <int>{};
  final Map<int, Future<String>> _coverJobs = <int, Future<String>>{};
  Future<void> _queue = Future<void>.value();
  bool _restored = false;
  Future<void>? _restoring;
  bool _resuming = false;
  int _activeBackgroundJobs = 0;

  Future<void> Function(HgDownloadTask task, int newEpisode)? onUpdateFound;
  Future<void> Function(HgDownloadTask task)? onDownloadCompleted;

  List<HgDownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get autoUpdateDefault =>
      _prefs.getBool(HgSettingsKeys.autoUpdateDownloads) ?? true;

  HgDownloadTask? taskFor(int videoId) {
    for (final task in _tasks) {
      if (task.videoId == videoId) return task;
    }
    return null;
  }

  bool isEpisodeDownloaded(int videoId, int episode) {
    return taskFor(videoId)?.episodes.containsKey(episode) ?? false;
  }

  Future<void> restore() {
    if (_restored) return Future<void>.value();
    return _restoring ??= _restore();
  }

  Future<void> _restore() async {
    // localPlaylist may be called from a player's initState. Notify only after
    // that build has finished, and let concurrent callers await the same load.
    await Future<void>.value();
    final restored = HgDownloadTask.decodeList(_prefs.getString(_storageKey));
    final interrupted = <HgDownloadTask>[];
    for (final task in restored) {
      final episodes = <int, HgDownloadedEpisode>{};
      for (final episode in task.episodes.values) {
        if (await File(episode.manifestPath).exists()) {
          episodes[episode.number] = episode;
        }
      }
      var localCover = task.localCover;
      if (localCover.isNotEmpty && !await File(localCover).exists()) {
        localCover = '';
      }
      var normalized = task.copyWith(
        episodes: episodes,
        speedBytesPerSecond: 0,
        localCover: localCover,
      );
      if (normalized.isDownloading) {
        normalized = normalized.copyWith(state: '等待恢复');
        interrupted.add(normalized);
      }
      _tasks.add(normalized);
      if (normalized.localCover.isEmpty && normalized.cover.isNotEmpty) {
        unawaited(_ensureLocalCover(normalized.videoId, normalized.cover));
      }
    }
    _restored = true;
    notifyListeners();
    if (interrupted.isNotEmpty) {
      unawaited(_resumeInterrupted(interrupted));
    }
  }

  Future<void> _resumeInterrupted(List<HgDownloadTask> interrupted) async {
    if (_resuming) return;
    _resuming = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      for (final task in interrupted) {
        if (taskFor(task.videoId) == null) continue;
        try {
          final detail = await _api.video(task.videoId);
          await startDramaDownload(
            detail,
            autoUpdate: task.autoUpdate,
            downloadNow: true,
          );
        } catch (error) {
          final current = taskFor(task.videoId);
          if (current != null) {
            _upsert(
              current.copyWith(
                state: '已暂停',
                speedBytesPerSecond: 0,
                lastError: error.toString(),
                updatedAt: DateTime.now().toIso8601String(),
              ),
            );
          }
        }
      }
    } finally {
      _resuming = false;
    }
  }

  Future<void> startDramaDownload(
    HgVideoDetail detail, {
    bool? autoUpdate,
    bool downloadNow = true,
  }) async {
    await restore();
    final existing = taskFor(detail.id);
    final shouldAutoUpdate =
        autoUpdate ?? existing?.autoUpdate ?? autoUpdateDefault;
    final initial =
        existing ??
        HgDownloadTask(
          videoId: detail.id,
          title: detail.title,
          cover: detail.cover,
          localCover: existing?.localCover ?? '',
          tags: detail.tags,
          totalEpisodes: _episodeCount(detail),
          autoUpdate: shouldAutoUpdate,
          lastKnownEpisode: _episodeCount(detail),
          updatedAt: DateTime.now().toIso8601String(),
        );
    final task = initial.copyWith(
      title: detail.title,
      cover: detail.cover,
      tags: detail.tags,
      totalEpisodes: _episodeCount(detail),
      autoUpdate: shouldAutoUpdate,
      tracking: true,
      state: downloadNow ? '排队中' : '追更中',
      progress: initial.episodes.length / _episodeCount(detail).clamp(1, 99999),
      receivedBytes: initial.downloadedBytes,
      totalBytes: initial.downloadedBytes,
      speedBytesPerSecond: 0,
      lastError: '',
      lastKnownEpisode: _episodeCount(detail),
      updatedAt: DateTime.now().toIso8601String(),
    );
    _upsert(task);
    await _persist();
    if (task.localCover.isEmpty && task.cover.isNotEmpty) {
      unawaited(_ensureLocalCover(detail.id, detail.cover));
    }
    if (downloadNow) {
      _enqueueDownload(detail);
    }
  }

  Future<void> resumeDownload(int videoId) async {
    await restore();
    final task = taskFor(videoId);
    if (task == null) return;
    final detail = await _api.video(videoId);
    await startDramaDownload(
      detail,
      autoUpdate: task.autoUpdate,
      downloadNow: true,
    );
  }

  Future<void> setAutoUpdate(int videoId, bool value) async {
    await restore();
    final task = taskFor(videoId);
    if (task == null) return;
    _upsert(task.copyWith(autoUpdate: value, tracking: true));
    await _persist();
  }

  Future<void> toggleTracking(int videoId, bool value) async {
    await restore();
    final task = taskFor(videoId);
    if (task == null) return;
    _upsert(task.copyWith(tracking: value));
    await _persist();
  }

  Future<void> checkForUpdates() async {
    await restore();
    final candidates = _tasks
        .where((task) => task.tracking)
        .toList(growable: false);
    for (final task in candidates) {
      try {
        final detail = await _api.video(task.videoId);
        final count = _episodeCount(detail);
        final previous = task.lastKnownEpisode;
        if (count > previous) {
          final updated = task.copyWith(
            title: detail.title,
            cover: detail.cover,
            tags: detail.tags,
            totalEpisodes: count,
            lastKnownEpisode: count,
            state: task.autoUpdate ? '检查更新' : '有新剧集',
            updatedAt: DateTime.now().toIso8601String(),
          );
          _upsert(updated);
          await _persist();
          await onUpdateFound?.call(updated, count - previous);
          if (task.autoUpdate) {
            unawaited(startDramaDownload(detail));
          }
        }
      } catch (_) {
        // 单部剧更新检查失败不影响其他剧。
      }
    }
  }

  Future<String?> localPlaylist(int videoId, int episode) async {
    await restore();
    final task = taskFor(videoId);
    final item = task?.episodes[episode];
    if (item == null) return null;
    return await File(item.manifestPath).exists() ? item.manifestPath : null;
  }

  Future<int> sizeBytes() async {
    await restore();
    var total = 0;
    for (final task in _tasks) {
      total += task.downloadedBytes;
    }
    return total;
  }

  Future<void> remove(int videoId) async {
    await restore();
    final removedCover = taskFor(videoId)?.localCover ?? '';
    _tasks.removeWhere((task) => task.videoId == videoId);
    await _deleteDirectory(await _dramaDirectory(videoId));
    await _deleteCover(videoId, removedCover);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    await restore();
    final dir = await _downloadRoot();
    if (await dir.exists()) await dir.delete(recursive: true);
    await _deleteDirectory(await _coverRoot());
    _tasks.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _downloadAll(HgVideoDetail detail) async {
    final task = taskFor(detail.id);
    if (task == null) return;
    await _beginDownloadBackgroundWork();
    try {
      final episodes = _episodes(detail);
      if (episodes.isEmpty) return;
      final directory = await _dramaDirectory(detail.id);
      var completed = task.episodes;
      var lastNotificationPercent = -1;
      final firstEpisode = episodes.first.number;
      unawaited(
        HgLiveActivityService.showDownload(
          videoId: detail.id,
          title: detail.title,
          cover: detail.cover,
          tags: detail.tags,
          episode: firstEpisode,
          totalEpisodes: episodes.length,
          progress: task.progress,
          detail: '准备缓存',
          deepLink: 'guomu://video/${detail.id}',
        ),
      );
      unawaited(
        HgNotificationService.showDownloadProgress(
          task,
          episode: firstEpisode,
          totalEpisodes: episodes.length,
          progress: task.progress,
          state: '准备缓存',
          speed: '等待网络',
          alert: true,
        ),
      );
      for (final episode in episodes) {
        if (taskFor(detail.id) == null) return;
        if (taskFor(detail.id)?.episodes.containsKey(episode.number) ?? false) {
          continue;
        }
        final episodeDir = Directory('${directory.path}/${episode.number}');
        if (await episodeDir.exists()) {
          await episodeDir.delete(recursive: true);
        }
        final completedBytes = completed.values.fold<int>(
          0,
          (sum, item) => sum + item.bytes,
        );
        _upsert(
          taskFor(detail.id)!.copyWith(
            state: '下载中 · 第 ${episode.number}/${episodes.length} 集',
            lastError: '',
            receivedBytes: completedBytes,
            totalBytes: completedBytes,
            speedBytesPerSecond: 0,
            progress: completed.length / episodes.length.clamp(1, 99999),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );
        try {
          final info = await _api.playback(detail.id, episode.number);
          final mediaHeaders = <String, String>{
            ...hgMediaHeaders(),
            if (info.cdnAuthKey.isNotEmpty) info.cdnAuthKey: info.cdnAuthValue,
            if (info.cdnApp.isNotEmpty) 'x-cdn-app': info.cdnApp,
          };
          final dio = Dio();
          final preferHevc =
              !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS) &&
              info.hevcUrl.isNotEmpty;
          var lastSpeedBytes = 0;
          var lastSpeedAt = DateTime.now();
          var lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);
          var lastPersistAt = DateTime.now();
          var speed = 0;

          void onProgress(HgDownloadProgressSnapshot progress) {
            final now = DateTime.now();
            final speedElapsed = now.difference(lastSpeedAt).inMilliseconds;
            if (speedElapsed >= 500) {
              final delta = progress.receivedBytes - lastSpeedBytes;
              speed = delta <= 0 ? 0 : (delta * 1000 / speedElapsed).round();
              lastSpeedBytes = progress.receivedBytes;
              lastSpeedAt = now;
            }
            final uiElapsed = now.difference(lastUiAt).inMilliseconds;
            if (uiElapsed < 220 &&
                progress.completedSegments < progress.totalSegments) {
              return;
            }
            lastUiAt = now;
            final current = taskFor(detail.id);
            if (current == null) return;
            final episodeFraction = progress.fraction;
            final overallProgress =
                (completed.length + episodeFraction) /
                episodes.length.clamp(1, 99999);
            final speedText = speed > 0 ? '${_formatBytes(speed)}/s' : '正在下载';
            _upsert(
              current.copyWith(
                state: '下载中 · 第 ${episode.number}/${episodes.length} 集',
                receivedBytes: completedBytes + progress.receivedBytes,
                totalBytes: completedBytes + progress.totalBytes,
                speedBytesPerSecond: speed,
                progress: overallProgress,
                updatedAt: now.toIso8601String(),
              ),
            );
            unawaited(
              HgLiveActivityService.showDownload(
                videoId: detail.id,
                title: detail.title,
                cover: detail.cover,
                tags: detail.tags,
                episode: episode.number,
                totalEpisodes: episodes.length,
                progress: overallProgress,
                detail:
                    '$speedText · ${progress.completedSegments}/${progress.totalSegments} 分片',
                deepLink: 'guomu://video/${detail.id}',
              ),
            );
            final percent = (overallProgress * 100).floor();
            if (percent >= lastNotificationPercent + 5 ||
                progress.completedSegments >= progress.totalSegments) {
              lastNotificationPercent = percent;
              unawaited(
                HgNotificationService.showDownloadProgress(
                  current,
                  episode: episode.number,
                  totalEpisodes: episodes.length,
                  progress: overallProgress,
                  state: '下载中',
                  speed: speedText,
                ),
              );
            }
            if (now.difference(lastPersistAt).inSeconds >= 5) {
              lastPersistAt = now;
              unawaited(_persist());
            }
          }

          late final HgDownloadedPlaylist downloaded;
          try {
            downloaded = await HgHlsDownloader.download(
              dio: dio,
              playlistUrl: preferHevc ? info.hevcUrl : info.videoUrl,
              directory: episodeDir,
              headers: mediaHeaders,
              onProgress: onProgress,
            );
          } catch (_) {
            if (!preferHevc) rethrow;
            if (await episodeDir.exists()) {
              await episodeDir.delete(recursive: true);
            }
            downloaded = await HgHlsDownloader.download(
              dio: dio,
              playlistUrl: info.videoUrl,
              directory: episodeDir,
              headers: mediaHeaders,
              onProgress: onProgress,
            );
          } finally {
            dio.close(force: true);
          }
          if (taskFor(detail.id) == null) {
            if (await episodeDir.exists()) {
              await episodeDir.delete(recursive: true);
            }
            return;
          }
          completed = {
            ...completed,
            episode.number: HgDownloadedEpisode(
              number: episode.number,
              directory: downloaded.directory,
              manifestPath: downloaded.manifestPath,
              bytes: downloaded.bytes,
              updatedAt: DateTime.now().toIso8601String(),
            ),
          };
          final completedTotal = completed.values.fold<int>(
            0,
            (sum, item) => sum + item.bytes,
          );
          _upsert(
            taskFor(detail.id)!.copyWith(
              episodes: completed,
              progress: completed.length / episodes.length.clamp(1, 99999),
              state: completed.length >= episodes.length ? '已缓存' : '下载中',
              receivedBytes: completedTotal,
              totalBytes: completedTotal,
              speedBytesPerSecond: 0,
              updatedAt: DateTime.now().toIso8601String(),
            ),
          );
          await _persist();
        } catch (error) {
          if (await episodeDir.exists()) {
            await episodeDir.delete(recursive: true);
          }
          final current = taskFor(detail.id);
          if (current != null) {
            _upsert(
              current.copyWith(
                state: '已暂停',
                lastError: error.toString(),
                receivedBytes: completed.values.fold<int>(
                  0,
                  (sum, item) => sum + item.bytes,
                ),
                totalBytes: 0,
                speedBytesPerSecond: 0,
                updatedAt: DateTime.now().toIso8601String(),
              ),
            );
          }
          await _persist();
          break;
        }
      }
      final current = taskFor(detail.id);
      if (current != null) {
        final finished = current.copyWith(
          totalEpisodes: episodes.length,
          progress: completed.length / episodes.length.clamp(1, 99999),
          state: current.state == '已暂停'
              ? '已暂停'
              : completed.length >= episodes.length
              ? '已缓存'
              : '部分缓存',
          speedBytesPerSecond: 0,
          updatedAt: DateTime.now().toIso8601String(),
        );
        _upsert(finished);
        await _persist();
        if (finished.isComplete) await onDownloadCompleted?.call(finished);
      }
    } finally {
      await HgLiveActivityService.endDownload(detail.id);
      unawaited(HgNotificationService.clearDownloadProgress(detail.id));
      await _endDownloadBackgroundWork();
    }
  }

  Future<void> _beginDownloadBackgroundWork() async {
    _activeBackgroundJobs++;
    if (_activeBackgroundJobs == 1) {
      await HgBackgroundExecutionService.setDownloadActive(true);
    }
  }

  Future<void> _endDownloadBackgroundWork() async {
    if (_activeBackgroundJobs > 0) _activeBackgroundJobs--;
    if (_activeBackgroundJobs == 0) {
      await HgBackgroundExecutionService.setDownloadActive(false);
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _enqueueDownload(HgVideoDetail detail) {
    if (!_queuedVideoIds.add(detail.id)) return;
    _enqueue(() async {
      try {
        await _downloadAll(detail);
      } finally {
        _queuedVideoIds.remove(detail.id);
      }
    });
  }

  void _enqueue(Future<void> Function() action) {
    _queue = _queue.catchError((Object _) {}).then((_) => action());
  }

  void _upsert(HgDownloadTask task) {
    final index = _tasks.indexWhere((item) => item.videoId == task.videoId);
    if (index < 0) {
      _tasks.add(task);
    } else {
      _tasks[index] = task;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _storageKey,
      jsonEncode(_tasks.map((task) => task.toJson()).toList()),
    );
  }

  Future<Directory> _downloadRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/guomu/downloads');
  }

  Future<Directory> _coverRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/guomu/covers');
  }

  Future<String> _ensureLocalCover(int videoId, String cover) {
    final active = _coverJobs[videoId];
    if (active != null) return active;
    final job = _cacheCover(videoId, cover).whenComplete(() {
      _coverJobs.remove(videoId);
    });
    _coverJobs[videoId] = job;
    return job;
  }

  Future<String> _cacheCover(int videoId, String cover) async {
    final current = taskFor(videoId);
    if (current == null || cover.trim().isEmpty) return '';
    if (current.localCover.isNotEmpty &&
        await File(current.localCover).exists()) {
      return current.localCover;
    }
    try {
      final bytes = await HgCoverRepository.instance
          .load(cover)
          .timeout(const Duration(seconds: 20));
      if (bytes.isEmpty) return '';
      final directory = await _coverRoot();
      await directory.create(recursive: true);
      final file = File('${directory.path}/cover-$videoId.jpg');
      await file.writeAsBytes(bytes, flush: true);
      final latest = taskFor(videoId);
      if (latest != null) {
        _upsert(latest.copyWith(localCover: file.path));
        await _persist();
      }
      return file.path;
    } catch (_) {
      return '';
    }
  }

  Future<void> _deleteCover(int videoId, [String path = '']) async {
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final fallback = File('${(await _coverRoot()).path}/cover-$videoId.jpg');
    if (await fallback.exists()) await fallback.delete();
  }

  Future<Directory> _dramaDirectory(int videoId) async {
    return Directory('${(await _downloadRoot()).path}/$videoId');
  }

  Future<void> _deleteDirectory(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static int _episodeCount(HgVideoDetail detail) {
    if (detail.episodes.isNotEmpty) return detail.episodes.length;
    return detail.totalEpisodes > 0
        ? detail.totalEpisodes
        : detail.episodeCount;
  }

  static List<HgEpisode> _episodes(HgVideoDetail detail) {
    if (detail.episodes.isNotEmpty) return detail.episodes;
    final count = _episodeCount(detail);
    return List.generate(
      count.clamp(0, 999),
      (index) => HgEpisode(number: index + 1, title: '${index + 1}'),
      growable: false,
    );
  }
}
