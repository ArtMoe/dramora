import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/widgets/hg_video_controller_native.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _PlayerPlatform extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  Completer<void>? seekCompletion;
  bool delayInitialize = false;
  bool disposed = false;
  Duration position = Duration.zero;

  void initializeVideo() => events.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 100),
      size: const Size(1080, 1920),
    ),
  );

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (!delayInitialize) initializeVideo();
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;
  @override
  Future<void> dispose(int playerId) async => disposed = true;
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> seekTo(int playerId, Duration target) async {
    await seekCompletion?.future;
    position = target;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PlayerPlatform platform;
  late VideoPlayerPlatform previous;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _PlayerPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    await platform.events.close();
    VideoPlayerPlatform.instance = previous;
  });

  test(
    'near the end does not skip; completion fires once and rearms after seek',
    () async {
      var ended = 0;
      final controller = HgVideoController(
        url: 'https://example.test/video.m3u8',
        headers: {},
        onEnded: () => ended++,
      );
      await controller.initialize();
      await controller.seekTo(const Duration(milliseconds: 99850));
      expect(ended, 0);
      platform.events.add(VideoEvent(eventType: VideoEventType.completed));
      await Future<void>.delayed(Duration.zero);
      expect(ended, 1);
      platform.events.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
      await Future<void>.delayed(Duration.zero);
      expect(ended, 1);
      await controller.seekTo(const Duration(seconds: 40));
      platform.events.add(VideoEvent(eventType: VideoEventType.completed));
      await Future<void>.delayed(Duration.zero);
      expect(ended, 2);
      controller.dispose();
    },
  );

  test('buffer state and containing buffered range are exposed', () async {
    final controller = HgVideoController(
      url: 'https://example.test/video',
      headers: {},
    );
    await controller.initialize();
    await controller.seekTo(const Duration(seconds: 35));
    platform.events.add(
      VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered: [
          DurationRange(Duration.zero, const Duration(seconds: 20)),
          DurationRange(
            const Duration(seconds: 30),
            const Duration(seconds: 50),
          ),
        ],
      ),
    );
    platform.events.add(VideoEvent(eventType: VideoEventType.bufferingStart));
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBuffering, isTrue);
    expect(controller.bufferedPosition, const Duration(seconds: 50));
    platform.events.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBuffering, isFalse);
    controller.dispose();
  });

  test(
    'leaving while initialization is pending releases native player',
    () async {
      platform.delayInitialize = true;
      final controller = HgVideoController(
        url: 'https://example.test/video',
        headers: {},
      );
      final initialized = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      await initialized;
      await Future<void>.delayed(Duration.zero);
      expect(platform.disposed, isTrue);
      expect(controller.isReady, isFalse);
    },
  );
}
