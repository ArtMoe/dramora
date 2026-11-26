import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/hg_download_models.dart';
import 'hg_live_activity_service.dart';

/// 本机通知只在用户设备上产生，不依赖果幕服务端。
abstract final class HgNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

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
    await _plugin.initialize(settings);
    _initialized = true;
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
}
