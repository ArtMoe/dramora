import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/auth/app_controllers.dart';
import 'package:guomu/hg/models/hg_models.dart';
import 'package:guomu/hg/pages/detail_page.dart';
import 'package:guomu/hg/pages/home_page.dart';
import 'package:guomu/hg/widgets/hg_components.dart';
import 'package:guomu/hg/widgets/hg_pressable.dart';
import 'package:guomu/hg/utils/hg_download_manager.dart';
import 'package:guomu/hg/widgets/secure_cover.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

HgVideoCard _card(int id) => HgVideoCard(id: id, title: '短剧$id', cover: '');
HgRankItem _rank(int id) => HgRankItem(
  rank: id,
  videoId: id,
  title: '短剧$id',
  cover: '',
  tags: const [],
  score: 9,
  categoryName: '',
  episodeCount: 12,
  isFinished: false,
  metricLabel: '热度',
  metricValue: 500,
);

class _HomeApi extends HgApi {
  _HomeApi() : super(baseUrl: 'https://example.test');

  @override
  Future<HgHomeData> home() async => HgHomeData(featured: [_card(1), _card(2)]);

  @override
  Future<HgPage<HgVideoCard>> feed({
    int page = 1,
    int size = 20,
    String sort = '',
  }) async => HgPage.fromJson({
    'items': [
      for (final id in [2, 3, 4]) {'id': id, 'title': '短剧$id', 'cover': ''},
    ],
  }, HgVideoCard.fromJson);

  @override
  Future<List<HgRankItem>> rank(String kind) async => [
    _rank(1),
    _rank(3),
    _rank(5),
    _rank(6),
  ];

  @override
  Future<HgPage<HgTopic>> topics({int page = 1, int size = 12}) async =>
      HgPage.fromJson({'items': []}, HgTopic.fromJson);

  @override
  Future<List<HgVideoCategory>> videoCategories() async => [];

  @override
  Future<HgVideoDetail> video(int id) async =>
      HgVideoDetail.fromJson({'id': id, 'title': '短剧$id', 'cover': ''});

  @override
  Future<void> prefetchVideoDetails(Iterable<int> ids, {int limit = 6}) async {}
}

void main() {
  for (final entry in [
    (id: 1, feed: [1, 2], tag: 'home-featured-1'),
    (id: 3, feed: [3, 4], tag: 'home-latest-3'),
    (id: 5, feed: [5, 6], tag: 'home-hot-5'),
  ]) {
    testWidgets(
      'home card ${entry.id} opens matching detail and section feed',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final api = _HomeApi();
        final auth = AuthController(api, await SharedPreferences.getInstance());
        final downloads = HgDownloadManager(
          api,
          await SharedPreferences.getInstance(),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<HgApi>.value(value: api),
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: downloads),
            ],
            child: const MaterialApp(home: Scaffold(body: HomePage())),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final cover = find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == entry.tag,
        );
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        for (
          var attempt = 0;
          cover.evaluate().isEmpty && attempt < 12;
          attempt++
        ) {
          await tester.drag(scrollable, const Offset(0, -220));
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(cover, findsOneWidget);
        await tester.ensureVisible(cover);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(
          find.ancestor(of: cover, matching: find.byType(HgInkWell)).first,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final detail = tester.widget<DramaDetailPage>(
          find.byType(DramaDetailPage),
        );
        expect(detail.videoId, entry.id);
        expect(detail.preloaded?.id, entry.id);
        expect(detail.feedIds, entry.feed);
        expect(detail.heroTag, entry.tag);
        expect(tester.takeException(), isNull);
        if (entry.id == 1) {
          await tester.tap(find.text('追剧'));
          await tester.pumpAndSettle();
          expect(find.text('登录黄果'), findsOneWidget);
          await tester.tapAt(const Offset(195, 80));
          await tester.pumpAndSettle();
          expect(find.text('登录黄果'), findsNothing);
          expect(find.byType(DramaDetailPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        Navigator.of(tester.element(find.byType(DramaDetailPage))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(DramaDetailPage), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('cover transitions respect reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: HgCoverImage(url: '', heroTag: 'reduced'),
        ),
      ),
    );
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('rail cover uses its matching transition tag', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HgVideoRailCard(
            video: _card(1),
            heroTag: 'rail-cover',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'rail-cover',
      ),
      findsOneWidget,
    );
  });
}
