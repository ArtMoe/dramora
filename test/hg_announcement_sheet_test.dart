import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/models/hg_announcement.dart';
import 'package:guomu/hg/pages/announcement_sheet.dart';
import 'package:guomu/hg/pages/announcements_page.dart';
import 'package:guomu/hg/services/hg_announcement_service.dart';
import 'package:guomu/hg/theme/hg_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

HgAnnouncement _announcement() => HgAnnouncement.fromJson({
  'id': 'announcement-1',
  'type': 'notice',
  'priority': 'important',
  'title': '欢迎使用果幕',
  'body': '果幕公告中心正式启用。\n\n以后新项目与活动会在这里发布。',
  'published_at': '2020-01-01T00:00:00Z',
  'expires_at': null,
  'action': null,
});

void main() {
  testWidgets('announcement sheet returns both reminder decisions', (
    tester,
  ) async {
    HgAnnouncementDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHgTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                decision = await showHgAnnouncementSheet(
                  context,
                  _announcement(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用果幕'), findsOneWidget);
    expect(find.text('今日不再提醒'), findsOneWidget);
    expect(find.text('下次再通知我'), findsOneWidget);

    await tester.tap(find.text('今日不再提醒'));
    await tester.pumpAndSettle();
    expect(decision, HgAnnouncementDecision.today);
  });

  testWidgets('handled announcement only offers close', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHgTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHgAnnouncementSheet(
                context,
                _announcement(),
                handled: true,
              ),
              child: const Text('open handled'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open handled'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('今日不再提醒'), findsNothing);
  });

  testWidgets(
    'announcement center updates unread state after acknowledgement',
    (tester) async {
      final feed = {
        'schema_version': 1,
        'updated_at': '2026-11-26T20:00:00Z',
        'announcements': [_announcement().toJson()],
      };
      SharedPreferences.setMockInitialValues({
        HgAnnouncementController.cacheKey: jsonEncode(feed),
        HgAnnouncementController.lastCheckedKey: DateTime.now()
            .toUtc()
            .toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = HgAnnouncementController(
        prefs,
        fetcher: (_) async => null,
      );
      await controller.bootstrap();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: buildHgTheme(Brightness.light),
            home: const AnnouncementsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未读'), findsOneWidget);

      await tester.tap(find.text('欢迎使用果幕'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下次再通知我'));
      await tester.pumpAndSettle();
      expect(find.text('已读'), findsOneWidget);
    },
  );
}
