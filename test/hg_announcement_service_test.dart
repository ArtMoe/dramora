import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/services/hg_announcement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _feed({String id = 'announcement-1'}) => {
  'schema_version': 1,
  'updated_at': '2026-11-26T20:00:00Z',
  'announcements': [
    {
      'id': id,
      'type': 'notice',
      'priority': 'normal',
      'title': '公告标题',
      'body': '公告正文',
      'published_at': '2020-01-01T00:00:00Z',
      'expires_at': null,
      'action': null,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'falls back to a GitHub mirror and persists the successful feed',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final requested = <String>[];
      final controller = HgAnnouncementController(
        prefs,
        fetcher: (url) async {
          requested.add(url);
          if (url.contains('api.github.com')) throw Exception('blocked');
          return jsonEncode(_feed());
        },
      );

      await controller.refresh(force: true);

      expect(requested, hasLength(2));
      expect(controller.announcements.single.id, 'announcement-1');
      expect(controller.lastCheckedAt, isNotNull);
      expect(prefs.getString(HgAnnouncementController.cacheKey), isNotNull);
    },
  );

  test(
    'today snooze hides the current announcement and acknowledge persists',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = HgAnnouncementController(
        prefs,
        fetcher: (_) async => jsonEncode(_feed()),
      );
      await controller.refresh(force: true);

      expect(controller.nextEligible?.id, 'announcement-1');
      await controller.snoozeToday('announcement-1');
      expect(controller.nextEligible, isNull);
      await controller.acknowledge('announcement-1');
      expect(controller.isAcknowledged('announcement-1'), isTrue);
      expect(
        prefs.getString(HgAnnouncementController.acknowledgedKey),
        contains('announcement-1'),
      );
    },
  );

  test('notification dedupe is independent from in-app read state', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = HgAnnouncementController(
      prefs,
      fetcher: (_) async => jsonEncode(_feed()),
    );
    await controller.refresh(force: true);

    expect(controller.nextForNotification?.id, 'announcement-1');
    await controller.markNotified('announcement-1');
    expect(controller.nextForNotification, isNull);
    expect(controller.nextEligible?.id, 'announcement-1');
  });

  test('network failure preserves the last successful feed', () async {
    final cached = jsonEncode(_feed(id: 'cached-announcement'));
    SharedPreferences.setMockInitialValues({
      HgAnnouncementController.cacheKey: cached,
      HgAnnouncementController.lastCheckedKey: '2026-11-26T20:00:00Z',
    });
    final reloaded = await SharedPreferences.getInstance();
    final controller = HgAnnouncementController(
      reloaded,
      fetcher: (_) async => throw Exception('offline'),
    );

    await controller.refresh(force: true);

    expect(controller.announcements.single.id, 'cached-announcement');
    expect(controller.lastError, isNotNull);
  });
}
