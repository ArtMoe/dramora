import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/models/hg_download_models.dart';
import 'package:guomu/hg/pages/downloads_page.dart';
import 'package:guomu/hg/theme/hg_theme.dart';
import 'package:guomu/hg/utils/hg_download_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends HgApi {
  _FakeApi() : super(baseUrl: 'https://example.test');
}

class _PreviewDownloads extends HgDownloadManager {
  _PreviewDownloads(this.api, SharedPreferences prefs, this._previewTasks)
    : super(api, prefs);

  final _FakeApi api;
  final List<HgDownloadTask> _previewTasks;
  int resumeCalls = 0;
  int removeCalls = 0;

  @override
  List<HgDownloadTask> get tasks => _previewTasks;

  @override
  HgDownloadTask? taskFor(int videoId) {
    for (final task in _previewTasks) {
      if (task.videoId == videoId) return task;
    }
    return null;
  }

  @override
  Future<void> restore() async {}

  @override
  Future<void> resumeDownload(int videoId) async {
    resumeCalls++;
  }

  @override
  Future<void> remove(int videoId) async {
    removeCalls++;
  }
}

Future<_PreviewDownloads> _managerFor(HgDownloadTask task) {
  return _managerForTasks([task]);
}

Future<_PreviewDownloads> _managerForTasks(List<HgDownloadTask> tasks) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return _PreviewDownloads(_FakeApi(), prefs, tasks);
}

Widget _host(HgDownloadManager manager, HgApi api) {
  return MultiProvider(
    providers: [
      Provider<HgApi>.value(value: api),
      ChangeNotifierProvider<HgDownloadManager>.value(value: manager),
    ],
    child: MaterialApp(
      theme: buildHgTheme(Brightness.light),
      home: const DownloadsPage(),
    ),
  );
}

void main() {
  testWidgets(
    'active download shows current bytes, speed and smooth progress',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const mib = 1024 * 1024;
      final manager = await _managerFor(
        const HgDownloadTask(
          videoId: 10586,
          title: '蜜桃臀',
          cover: '',
          state: '下载中 · 第 1/6 集',
          totalEpisodes: 6,
          progress: 0.1,
          receivedBytes: 20 * mib,
          totalBytes: 500 * mib,
          speedBytesPerSecond: 100 * 1024,
        ),
      );
      addTearDown(manager.dispose);
      await tester.pumpWidget(_host(manager, manager.api));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('100.0 KB/s'), findsOneWidget);
      expect(find.text('本集 20.0 MB / 500.0 MB'), findsOneWidget);
      expect(find.textContaining('剩余 1 小时'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, closeTo(0.1, 0.001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paused download exposes an explicit resume action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = await _managerFor(
      const HgDownloadTask(
        videoId: 11734,
        title: '寄生帚',
        cover: '',
        state: '已暂停',
        totalEpisodes: 6,
        lastError: 'network',
      ),
    );
    addTearDown(manager.dispose);

    await tester.pumpWidget(_host(manager, manager.api));
    await tester.pump();

    expect(find.text('已暂停 · 可继续下载'), findsOneWidget);
    final resume = find.byKey(const ValueKey('hg-download-resume-11734'));
    expect(resume, findsOneWidget);
    await tester.tap(resume);
    await tester.pump();
    expect(manager.resumeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('downloaded tab shows completed tasks and swipe reveals delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = await _managerFor(
      const HgDownloadTask(
        videoId: 20001,
        title: '已下载短剧',
        cover: 'https://example.test/cover.jpg',
        localCover: '/documents/guomu/covers/cover-20001.jpg',
        state: '已缓存',
        totalEpisodes: 1,
        episodes: {
          1: HgDownloadedEpisode(
            number: 1,
            directory: '/documents/guomu/downloads/20001/1',
            manifestPath: '/documents/guomu/downloads/20001/1/index.m3u8',
            bytes: 1024,
            updatedAt: '2026-11-26T00:00:00Z',
          ),
        },
      ),
    );
    addTearDown(manager.dispose);
    await tester.pumpWidget(_host(manager, manager.api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('已下载'));
    await tester.pumpAndSettle();
    expect(find.text('已下载短剧'), findsOneWidget);

    final swipe = find.byKey(const ValueKey('hg-download-swipe-20001'));
    await tester.drag(swipe, const Offset(-100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hg-download-delete-20001')));
    await tester.pump();
    expect(manager.removeCalls, 1);
  });
}
