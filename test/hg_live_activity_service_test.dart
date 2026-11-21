import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/services/hg_live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.guomu.huangguo/liveactivity');
  const plugin = MethodChannel('live_activities');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  bool available = true;
  Completer<void>? creationGate;
  var activeCreations = 0;
  var peakCreations = 0;

  Future<void> update({
    String cover = '',
    int episode = 1,
    double progress = 0.5,
  }) => HgLiveActivityService.showOrUpdate(
    videoId: 12,
    title: '测试短剧',
    cover: cover,
    tags: const ['都市'],
    episode: episode,
    totalEpisodes: 6,
    progress: progress,
    deepLink: 'guomu://video/12',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    available = true;
    activeCreations = 0;
    peakCreations = 0;
    creationGate = null;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'isAvailable') return available;
      if (call.method == 'prepareCover') return '';
      throw PlatformException(code: 'unexpected_native_method');
    });
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'areActivitiesSupported':
        case 'areActivitiesEnabled':
          return true;
        case 'createOrUpdateActivity':
          activeCreations++;
          if (activeCreations > peakCreations) peakCreations = activeCreations;
          try {
            await creationGate?.future;
          } finally {
            activeCreations--;
          }
          return 'native-activity-id';
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    creationGate?.complete();
    await HgLiveActivityService.resetForTesting();
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(plugin, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Map<Object?, Object?> getData(MethodCall call) =>
      (call.arguments as Map)['data'] as Map;

  test('empty cover never crosses native channel as null', () async {
    await update(progress: double.nan);
    final create = calls.singleWhere(
      (call) => call.method == 'createOrUpdateActivity',
    );
    final data = getData(create);
    expect(data['cover'], '');
    expect(data['progress'], 0.0);
    expect(data['episodeLabel'], '观看至 1/6 集');
    expect(
      data.values,
      everyElement(anyOf(isA<String>(), isA<int>(), isA<double>())),
    );
    expect((create.arguments as Map)['removeWhenAppIsKilled'], isFalse);
  });

  test(
    'cover download failure still creates safe text activity once',
    () async {
      HgLiveActivityService.coverLoaderForTesting = (_) async =>
          throw StateError('cover unavailable');
      await update(cover: 'https://example.test/unavailable.jpg');
      final creates = calls
          .where((call) => call.method == 'createOrUpdateActivity')
          .toList();
      expect(creates, hasLength(1));
      expect(getData(creates.single)['cover'], '');
    },
  );

  test('decoded cover becomes a local string path and is reused', () async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF9sAAAAASUVORK5CYII=',
    );
    var downloads = 0;
    var preparations = 0;
    HgLiveActivityService.coverLoaderForTesting = (_) async {
      downloads++;
      return bytes;
    };
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'isAvailable') return true;
      preparations++;
      expect((call.arguments as Map)['bytes'], bytes);
      return '/shared/GuomuActivityCovers/cover-12.jpg';
    });
    await update(cover: 'https://example.test/cover.png');
    await update(cover: 'https://example.test/cover.png', episode: 2);
    expect(downloads, 1);
    expect(preparations, 1);
    for (final call in calls.where(
      (call) => call.method == 'createOrUpdateActivity',
    )) {
      expect(
        getData(call)['cover'],
        '/shared/GuomuActivityCovers/cover-12.jpg',
      );
    }
  });

  test(
    'missing App Group or extension skips plugin and preserves playback',
    () async {
      available = false;
      await update();
      expect(calls, isEmpty);
    },
  );

  test(
    'unavailable native bridge does not throw or initialize plugin',
    () async {
      messenger.setMockMethodCallHandler(
        native,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await update();
      expect(calls, isEmpty);
    },
  );

  test('concurrent updates serialize and initialize once', () async {
    creationGate = Completer<void>();
    final first = update();
    final second = update(episode: 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      calls.where((call) => call.method == 'createOrUpdateActivity'),
      hasLength(1),
    );
    creationGate!.complete();
    creationGate = null;
    await Future.wait([first, second]);
    expect(peakCreations, 1);
    expect(calls.where((call) => call.method == 'init'), hasLength(1));
    expect(
      calls
          .where((call) => call.method == 'createOrUpdateActivity')
          .map((call) => getData(call)['episode']),
      [1, 2],
    );
  });

  test(
    'ending activity cancels queued recreation and uses native cleanup',
    () async {
      creationGate = Completer<void>();
      final first = update();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final queued = update(episode: 2);
      final ending = HgLiveActivityService.end();
      creationGate!.complete();
      creationGate = null;
      await Future.wait([first, queued, ending]);
      expect(
        calls.where((call) => call.method == 'createOrUpdateActivity'),
        hasLength(1),
      );
      expect(calls.last.method, 'endAllActivities');
    },
  );
}
