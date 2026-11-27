import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/auth/app_controllers.dart';
import 'package:guomu/hg/models/hg_models.dart';
import 'package:guomu/hg/models/hg_download_models.dart';
import 'package:guomu/hg/pages/detail_page.dart';
import 'package:guomu/hg/theme/hg_theme.dart';
import 'package:guomu/hg/utils/hg_download_manager.dart';
import 'package:guomu/hg/utils/hg_local_history.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DetailApi extends HgApi {
  _DetailApi() : super(baseUrl: 'https://example.test');

  @override
  Future<HgVideoDetail> video(int id) async => HgVideoDetail.fromJson({
    'id': id,
    'title': '界面回归短剧',
    'cover': '',
    'total_episodes': 1,
    'episodes': [
      {'ep_num': 1},
    ],
  });
}

class _OfflineDetailApi extends HgApi {
  _OfflineDetailApi() : super(baseUrl: 'https://example.test');

  @override
  Future<HgVideoDetail> video(int id) async {
    throw Exception('offline');
  }
}

void main() {
  testWidgets('detail action dock fits a narrow phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _DetailApi();
    final auth = AuthController(api, prefs);
    final downloads = HgDownloadManager(api, prefs);
    HgLocalHistory.resetQueueForTesting();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HgApi>.value(value: api),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider<HgDownloadManager>.value(value: downloads),
        ],
        child: MaterialApp(
          theme: buildHgTheme(Brightness.light),
          home: const DramaDetailPage(videoId: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(const ValueKey('hg-detail-action-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('hg-detail-follow')), findsOneWidget);
    expect(find.byKey(const ValueKey('hg-detail-play')), findsOneWidget);
    expect(find.text('立即播放 · 第 1 集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached drama detail and play action remain available offline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _OfflineDetailApi();
    final auth = AuthController(api, prefs);
    final downloads = HgDownloadManager(api, prefs);
    HgLocalHistory.resetQueueForTesting();
    const task = HgDownloadTask(
      videoId: 9,
      title: '离线缓存短剧',
      cover: '',
      totalEpisodes: 2,
      state: '已缓存',
      episodes: {
        1: HgDownloadedEpisode(
          number: 1,
          directory: '',
          manifestPath: '',
          bytes: 1,
          updatedAt: '',
        ),
        2: HgDownloadedEpisode(
          number: 2,
          directory: '',
          manifestPath: '',
          bytes: 1,
          updatedAt: '',
        ),
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HgApi>.value(value: api),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider<HgDownloadManager>.value(value: downloads),
        ],
        child: MaterialApp(
          theme: buildHgTheme(Brightness.dark),
          home: const DramaDetailPage(videoId: 9, downloadTask: task),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('离线缓存短剧'), findsWidgets);
    final play = tester.widget<FilledButton>(
      find.byKey(const ValueKey('hg-detail-play')),
    );
    expect(play.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
