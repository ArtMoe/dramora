import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/services/hg_live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.guomu.huangguo/liveactivity');
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
      calls.add(call);
      if (call.method == 'prepareArtwork') return '/cache/cover-12.jpg';
      if (call.method == 'showOrUpdate') {
        activeCreations++;
        if (activeCreations > peakCreations) peakCreations = activeCreations;
        try {
          await creationGate?.future;
        } finally {
          activeCreations--;
        }
      }
      return null;
    });
  });

  tearDown(() async {
    creationGate?.complete();
    await HgLiveActivityService.resetForTesting();
    messenger.setMockMethodCallHandler(native, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Map<String, Object?> getData(MethodCall call) =>
      (call.arguments as Map).cast<String, Object?>();

  test(
    'empty cover and non-finite progress stay safe primitive values',
    () async {
      await update(progress: double.nan);
      final create = calls.singleWhere((call) => call.method == 'showOrUpdate');
      final data = getData(create);
      expect(data['coverBytes'], isNull);
      expect(data['progress'], 0.0);
      expect(data['episodeLabel'], '观看至 1/6 集');
      expect(data['activityKey'], 'guomu-now-playing');
    },
  );

  test('cover download failure still creates a text activity', () async {
    HgLiveActivityService.coverLoaderForTesting = (_) async =>
        throw StateError('cover unavailable');
    await update(cover: 'https://example.test/unavailable.jpg');
    final creates = calls
        .where((call) => call.method == 'showOrUpdate')
        .toList();
    expect(creates, hasLength(1));
    expect(getData(creates.single)['coverBytes'], isNull);
  });

  test('decoded cover is loaded once and sent as bytes', () async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF9sAAAAASUVORK5CYII=',
    );
    var downloads = 0;
    HgLiveActivityService.coverLoaderForTesting = (_) async {
      downloads++;
      return bytes;
    };
    await update(cover: 'https://example.test/cover.png');
    await update(cover: 'https://example.test/cover.png', episode: 2);
    expect(downloads, 1);
    for (final call in calls.where((call) => call.method == 'showOrUpdate')) {
      expect(getData(call)['coverBytes'], bytes);
    }
  });

  test('prepareArtworkPath returns a local notification attachment', () async {
    HgLiveActivityService
        .coverLoaderForTesting = (_) async => Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF9sAAAAASUVORK5CYII=',
      ),
    );
    final path = await HgLiveActivityService.prepareArtworkPath(
      videoId: 12,
      cover: 'https://example.test/cover.png',
    );
    expect(path, '/cache/cover-12.jpg');
    expect(calls.any((call) => call.method == 'prepareArtwork'), isTrue);
  });

  test('unavailable ActivityKit skips native updates', () async {
    available = false;
    await update();
    expect(calls, isEmpty);
  });

  test(
    'concurrent updates serialize without overlapping ActivityKit calls',
    () async {
      creationGate = Completer<void>();
      final first = update();
      final second = update(episode: 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        calls.where((call) => call.method == 'showOrUpdate'),
        hasLength(1),
      );
      creationGate!.complete();
      creationGate = null;
      await Future.wait([first, second]);
      expect(peakCreations, 1);
      expect(
        calls
            .where((call) => call.method == 'showOrUpdate')
            .map((call) => getData(call)['episode']),
        [1, 2],
      );
    },
  );

  test('ending playback activity uses native keyed cleanup', () async {
    await update();
    await HgLiveActivityService.end();
    expect(calls.where((call) => call.method == 'end'), isNotEmpty);
    expect(getData(calls.last)['activityKey'], 'guomu-now-playing');
  });
}
