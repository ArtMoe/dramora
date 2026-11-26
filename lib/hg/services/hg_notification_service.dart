import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/hg_download_models.dart';
import 'hg_live_activity_service.dart';

typedef HgNotificationTapHandler = Future<void> Function(String payload);

/// 本机通知只在用户设备上产生，不依赖果幕服务端。
abstract final class HgNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final List<String> _pendingPayloads = <String>[];
  static bool _initialized = false;
  static HgNotificationTapHandler? _tapHandler;

  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    const android = AndroidInitializationSettings('ic_notification');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.trim() ?? '';
        if (payload.isNotEmpty) unawaited(_dispatchPayload(payload));
      },
    );
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final payload =
          launchDetails?.notificationResponse?.payload?.trim() ?? '';
      if (launchDetails?.didNotificationLaunchApp == true &&
          payload.isNotEmpty) {
        await _dispatchPayload(payload);
      }
    } catch (error) {
      debugPrint('Guomu notification launch payload skipped: $error');
    }
    _initialized = true;
  }

  static void setTapHandler(HgNotificationTapHandler? handler) {
    _tapHandler = handler;
    if (handler == null || _pendingPayloads.isEmpty) return;
    final pending = List<String>.from(_pendingPayloads);
    _pendingPayloads.clear();
    for (final payload in pending) {
      unawaited(_dispatchPayload(payload));
    }
  }

  static Future<void> _dispatchPayload(String payload) async {
    final handler = _tapHandler;
    if (handler == null) {
      if (!_pendingPayloads.contains(payload)) _pendingPayloads.add(payload);
      return;
    }
    try {
      await handler(payload);
    } catch (error) {
      debugPrint('Guomu notification payload handling skipped: $error');
    }
  }

  static Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    await initialize();
    final notification = await Permission.notification.request();
    return notification.isGranted || notification.isLimited;
  }

  static Future<void> showDramaUpdate(
    HgDownloadTask task,
    int newEpisodes,
  ) async {
    if (kIsWeb) return;
    await initialize();
    final countText = newEpisodes > 1 ? '$newEpisodes 集' : '1 集';
    await _plugin.show(
      task.videoId,
      '${task.title} 更新了',
      '已更新 $countText${task.autoUpdate ? '，正在自动缓存新剧集' : '，打开果幕即可继续观看'}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'guomu_updates',
          '追更提醒',
          channelDescription: '追剧更新与离线缓存提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          threadIdentifier: 'guomu_updates',
        ),
      ),
      payload: 'drama:${task.videoId}',
    );
  }

  static Future<void> showOfflineReady(HgDownloadTask task) async {
    if (kIsWeb) return;
    await initialize();
    final artworkPath = await HgLiveActivityService.prepareArtworkPath(
      videoId: task.videoId,
      cover: task.cover,
    );
    await _plugin.show(
      task.videoId + 100000,
      '${task.title} 已缓存',
      '已完成 ${task.episodes.length} 集，断网也能继续观看',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'guomu_downloads',
          '离线缓存',
          channelDescription: '短剧下载完成提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: 'guomu_downloads',
          attachments: artworkPath.isEmpty
              ? null
              : [DarwinNotificationAttachment(artworkPath)],
        ),
      ),
      payload: 'download:${task.videoId}',
    );
  }

  static Future<void> showAnnouncement({
    required String id,
    required String title,
    required String body,
    required bool important,
  }) async {
    if (kIsWeb) return;
    await initialize();
    final preview = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    await _plugin.show(
      _announcementNotificationId(id),
      title,
      preview.length > 140 ? '${preview.substring(0, 140)}…' : preview,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'guomu_announcements',
          '公告与活动',
          channelDescription: '新版本、新项目、活动与维护公告',
          importance: important
              ? Importance.high
              : Importance.defaultImportance,
          priority: important ? Priority.high : Priority.defaultPriority,
          onlyAlertOnce: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentList: true,
          presentBanner: true,
          presentSound: important,
          threadIdentifier: 'guomu_announcements',
          interruptionLevel: important
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
      payload: 'announcement:$id',
    );
  }

  static Future<void> showDownloadProgress(
    HgDownloadTask task, {
    required int episode,
    required int totalEpisodes,
    required double progress,
    required String state,
    required String speed,
    bool alert = false,
  }) async {
    if (kIsWeb) return;
    await initialize();
    final artworkPath = await HgLiveActivityService.prepareArtworkPath(
      videoId: task.videoId,
      cover: task.cover,
    );
    final percentage = (progress.clamp(0.0, 1.0) * 100).round();
    await _plugin.show(
      task.videoId + 200000,
      '${task.title} · 正在缓存',
      totalEpisodes > 0
          ? '第 $episode/$totalEpisodes 集 · $percentage% · $speed'
          : '$percentage% · $speed',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'guomu_downloads_progress',
          '离线缓存进度',
          channelDescription: '显示短剧缓存进度、集数与实时网速',
          importance: alert ? Importance.low : Importance.min,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: percentage,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: alert,
          presentList: true,
          presentBanner: alert,
          presentSound: alert,
          threadIdentifier: 'guomu_downloads_progress',
          subtitle: state,
          attachments: artworkPath.isEmpty
              ? null
              : [DarwinNotificationAttachment(artworkPath)],
        ),
      ),
      payload: 'download:${task.videoId}',
    );
  }

  static Future<void> clearDownloadProgress(int videoId) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(videoId + 200000);
  }

  static int _announcementNotificationId(String id) {
    var hash = 0x811C9DC5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 300000000 + (hash % 800000000);
  }
}
