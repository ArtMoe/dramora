import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/models/hg_announcement.dart';
import 'package:guomu/hg/services/hg_announcement_service.dart';

const _feed = {
  'schema_version': 1,
  'updated_at': '2026-11-26T20:00:00Z',
  'announcements': [
    {
      'id': 'welcome-dramora',
      'type': 'notice',
      'priority': 'normal',
      'title': '欢迎使用果幕',
      'body': '这是公告正文。',
      'published_at': '2026-11-26T19:00:00Z',
      'expires_at': null,
      'action': {'label': '查看项目', 'url': 'https://github.com/DearLicy/dramora'},
    },
  ],
};

void main() {
  test('parses and sorts a valid announcement feed', () {
    final feed = HgAnnouncementFeed.fromJson(Map<String, dynamic>.from(_feed));
    expect(feed.announcements, hasLength(1));
    expect(feed.announcements.single.type, HgAnnouncementType.notice);
    expect(feed.announcements.single.action?.label, '查看项目');
    expect(
      feed.announcements.single.isActiveAt(DateTime.utc(2026, 11, 26, 21)),
      isTrue,
    );
  });

  test('decodes GitHub contents API base64 responses', () {
    final raw = jsonEncode(_feed);
    final wrapper = jsonEncode({
      'encoding': 'base64',
      'content': base64Encode(utf8.encode(raw)),
    });
    final feed = HgAnnouncementController.decodeRemoteFeed(wrapper);
    expect(feed.announcements.single.title, '欢迎使用果幕');
  });

  test('rejects insecure action links and duplicate ids', () {
    final insecure = Map<String, dynamic>.from(_feed);
    insecure['announcements'] = [
      {
        ...(_feed['announcements'] as List).first as Map<String, dynamic>,
        'action': {'label': '打开', 'url': 'http://example.com'},
      },
    ];
    expect(
      () => HgAnnouncementFeed.fromJson(insecure),
      throwsA(isA<FormatException>()),
    );

    final duplicate = Map<String, dynamic>.from(_feed);
    final item = (_feed['announcements'] as List).first;
    duplicate['announcements'] = [item, item];
    expect(
      () => HgAnnouncementFeed.fromJson(duplicate),
      throwsA(isA<FormatException>()),
    );
  });

  test('future and expired announcements are not active', () {
    final announcement = HgAnnouncement.fromJson(
      Map<String, dynamic>.from((_feed['announcements'] as List).first as Map),
    );
    expect(announcement.isActiveAt(DateTime.utc(2026, 11, 26, 18)), isFalse);
    expect(announcement.isActiveAt(DateTime.utc(2026, 11, 27)), isTrue);
  });
}
