import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hg_announcement.dart';

typedef HgAnnouncementFetcher = Future<String?> Function(String url);

/// GitHub 只负责发布公告文件；已安装客户端在启动、回到前台或后台任务中主动检查。
class HgAnnouncementController extends ChangeNotifier {
  HgAnnouncementController(this._prefs, {HgAnnouncementFetcher? fetcher})
    : _fetcher = fetcher ?? fetchRemoteText {
    _restoreLocalState();
  }

  static const cacheKey = 'guomu.announcements.cache.v1';
  static const lastCheckedKey = 'guomu.announcements.last_checked.v1';
  static const acknowledgedKey = 'guomu.announcements.acknowledged.v1';
  static const snoozedKey = 'guomu.announcements.snoozed.v1';
  static const notifiedKey = 'guomu.announcements.notified.v1';

  static const foregroundRefreshInterval = Duration(minutes: 30);

  static const _announcementApi = String.fromEnvironment(
    'HG_GITHUB_ANNOUNCEMENT_URL',
    defaultValue:
        'https://api.github.com/repos/DearLicy/dramora/contents/assets/data/announcements.json?ref=main',
  );

  static const _remoteUrls = [
    _announcementApi,
    'https://cdn.jsdelivr.net/gh/DearLicy/dramora@main/assets/data/announcements.json',
    'https://raw.githubusercontent.com/DearLicy/dramora/main/assets/data/announcements.json',
  ];

  final SharedPreferences _prefs;
  final HgAnnouncementFetcher _fetcher;

  HgAnnouncementFeed _feed = HgAnnouncementFeed.empty();
  DateTime? _lastCheckedAt;
  String? _lastError;
  bool _isRefreshing = false;
  bool _hasCachedFeed = false;
  Future<void>? _bootstrapFuture;
  Future<void>? _refreshFuture;
  final Set<String> _acknowledged = {};
  final Set<String> _notified = {};
  final Map<String, DateTime> _snoozedUntil = {};

  List<HgAnnouncement> get announcements => _feed.announcements;
  DateTime get updatedAt => _feed.updatedAt;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get lastError => _lastError;
  bool get isRefreshing => _isRefreshing;

  List<HgAnnouncement> get activeAnnouncements {
    final now = DateTime.now().toUtc();
    return _feed.announcements
        .where((announcement) => announcement.isActiveAt(now))
        .toList(growable: false);
  }

  List<HgAnnouncement> get unreadAnnouncements => activeAnnouncements
      .where((announcement) => !_acknowledged.contains(announcement.id))
      .toList(growable: false);

  int get unreadCount => unreadAnnouncements.length;

  HgAnnouncement? get nextEligible {
    final now = DateTime.now().toUtc();
    for (final announcement in _feed.announcements) {
      if (!announcement.isActiveAt(now)) continue;
      if (_acknowledged.contains(announcement.id)) continue;
      final snoozedUntil = _snoozedUntil[announcement.id];
      if (snoozedUntil != null && snoozedUntil.isAfter(now)) continue;
      return announcement;
    }
    return null;
  }

  HgAnnouncement? get nextForNotification {
    final now = DateTime.now().toUtc();
    for (final announcement in _feed.announcements) {
      if (!announcement.isActiveAt(now)) continue;
      if (_acknowledged.contains(announcement.id)) continue;
      if (_notified.contains(announcement.id)) continue;
      final snoozedUntil = _snoozedUntil[announcement.id];
      if (snoozedUntil != null && snoozedUntil.isAfter(now)) continue;
      return announcement;
    }
    return null;
  }

  HgAnnouncement? announcementById(String id) {
    for (final announcement in _feed.announcements) {
      if (announcement.id == id) return announcement;
    }
    return null;
  }

  bool isAcknowledged(String id) => _acknowledged.contains(id);

  bool isSnoozed(String id) {
    final until = _snoozedUntil[id];
    return until != null && until.isAfter(DateTime.now().toUtc());
  }

  DateTime? snoozedUntil(String id) => _snoozedUntil[id];

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _loadBundledFallback();
  }

  Future<void> refresh({bool force = false}) {
    final active = _refreshFuture;
    if (active != null) return active;
    if (!force && _lastCheckedAt != null) {
      final age = DateTime.now().toUtc().difference(_lastCheckedAt!);
      if (age < foregroundRefreshInterval) return Future<void>.value();
    }
    final future = _refreshRemote();
    _refreshFuture = future;
    return future.whenComplete(() => _refreshFuture = null);
  }

  Future<void> refreshIfStale({
    Duration interval = foregroundRefreshInterval,
  }) async {
    final last = _lastCheckedAt;
    if (last != null && DateTime.now().toUtc().difference(last) < interval) {
      return;
    }
    await refresh(force: true);
  }

  Future<void> snoozeToday(String id) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _snoozedUntil[id] = tomorrow.toUtc();
    await _persistSnoozed();
    notifyListeners();
  }

  Future<void> acknowledge(String id) async {
    _acknowledged.add(id);
    _snoozedUntil.remove(id);
    await Future.wait([_persistAcknowledged(), _persistSnoozed()]);
    notifyListeners();
  }

  Future<void> markNotified(String id) async {
    if (!_notified.add(id)) return;
    await _persistNotified();
    notifyListeners();
  }

  Future<void> _refreshRemote() async {
    await bootstrap();
    _isRefreshing = true;
    _lastError = null;
    notifyListeners();

    try {
      for (final url in _remoteUrls) {
        try {
          final raw = await _fetcher(url);
          if (raw == null || raw.trim().isEmpty) continue;
          final feed = decodeRemoteFeed(raw);
          _feed = feed;
          _hasCachedFeed = true;
          _lastCheckedAt = DateTime.now().toUtc();
          _lastError = null;
          await Future.wait([
            _prefs.setString(cacheKey, feed.toJsonString()),
            _prefs.setString(lastCheckedKey, _lastCheckedAt!.toIso8601String()),
          ]);
          return;
        } catch (_) {
          // 单个 GitHub 入口失败时继续尝试镜像。
        }
      }
      _lastError = '暂时无法获取远程公告';
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> _loadBundledFallback() async {
    if (_hasCachedFeed) return;
    try {
      final raw = await rootBundle.loadString('assets/data/announcements.json');
      _feed = HgAnnouncementFeed.fromJsonString(raw);
      _hasCachedFeed = true;
      notifyListeners();
    } catch (_) {
      _feed = HgAnnouncementFeed.empty();
    }
  }

  void _restoreLocalState() {
    final rawCache = _prefs.getString(cacheKey);
    if (rawCache != null && rawCache.trim().isNotEmpty) {
      try {
        _feed = HgAnnouncementFeed.fromJsonString(rawCache);
        _hasCachedFeed = true;
      } catch (_) {
        _feed = HgAnnouncementFeed.empty();
      }
    }
    _lastCheckedAt = DateTime.tryParse(
      _prefs.getString(lastCheckedKey) ?? '',
    )?.toUtc();
    _restoreStringSet(acknowledgedKey, _acknowledged);
    _restoreStringSet(notifiedKey, _notified);
    _restoreSnoozed();
  }

  void _restoreStringSet(String key, Set<String> target) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        target.addAll(decoded.map((item) => item.toString()));
      }
    } catch (_) {}
  }

  void _restoreSnoozed() {
    final raw = _prefs.getString(snoozedKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final until = DateTime.tryParse(entry.value?.toString() ?? '');
        if (until != null) _snoozedUntil[entry.key.toString()] = until.toUtc();
      }
    } catch (_) {}
  }

  Future<void> _persistAcknowledged() => _prefs.setString(
    acknowledgedKey,
    jsonEncode(_acknowledged.toList(growable: false)),
  );

  Future<void> _persistNotified() => _prefs.setString(
    notifiedKey,
    jsonEncode(_notified.toList(growable: false)),
  );

  Future<void> _persistSnoozed() => _prefs.setString(
    snoozedKey,
    jsonEncode({
      for (final entry in _snoozedUntil.entries)
        entry.key: entry.value.toIso8601String(),
    }),
  );

  static HgAnnouncementFeed decodeRemoteFeed(String raw) {
    var body = raw.trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map && decoded['content'] is String) {
      final encoding = decoded['encoding']?.toString().toLowerCase() ?? '';
      if (encoding == 'base64') {
        final encoded = (decoded['content'] as String).replaceAll(
          RegExp(r'\s+'),
          '',
        );
        body = utf8.decode(base64Decode(encoded));
      }
    }
    return HgAnnouncementFeed.fromJsonString(body);
  }

  static Future<String?> fetchRemoteText(String url) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final response = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Accept': url.contains('api.github.com')
              ? 'application/vnd.github.raw+json'
              : '*/*',
        },
      ),
    );
    return response.data;
  }
}
