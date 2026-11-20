import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_persistent_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('reads and migrates a valid v1 content cache entry', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = DateTime.now()
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    await prefs.setString(
      'guomu.content.cache.v1.home:overview',
      jsonEncode({
        'expires_at': expiresAt,
        'data': {'title': '缓存内容'},
      }),
    );

    final cache = HgPersistentCache(prefs);
    final result = await cache.read('home:overview');

    expect(result?.data['title'], '缓存内容');
    expect(prefs.getString('guomu.content.cache.v1.home:overview'), isNull);
    expect(prefs.getString('guomu.content.cache.v2.home:overview'), isNotNull);
  });

  test(
    'removes malformed legacy entries instead of returning stale data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guomu.content.cache.v1.broken', '{bad json');

      final cache = HgPersistentCache(prefs);

      expect(await cache.read('broken'), isNull);
      expect(prefs.getString('guomu.content.cache.v1.broken'), isNull);
    },
  );
}
