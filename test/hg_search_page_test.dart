import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/auth/app_controllers.dart';
import 'package:guomu/hg/models/hg_models.dart';
import 'package:guomu/hg/pages/detail_page.dart';
import 'package:guomu/hg/pages/search_page.dart';
import 'package:guomu/hg/theme/hg_theme.dart';
import 'package:guomu/hg/utils/hg_download_manager.dart';
import 'package:guomu/hg/utils/hg_local_history.dart';
import 'package:guomu/hg/widgets/hg_components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

HgPage<HgVideoCard> _page(List<int> ids, {int page = 1, int pages = 1}) =>
    HgPage(
      items: [
        for (final id in ids) HgVideoCard(id: id, title: '短剧$id', cover: ''),
      ],
      pagination: HgPagination(page: page, pages: pages),
    );

class _SearchApi extends HgApi {
  _SearchApi() : super(baseUrl: 'https://example.test');
  final requests = <(String, int)>[];
  final pending = <Completer<HgPage<HgVideoCard>>>[];
  final suggestions = <String, Completer<List<String>>>{};
  final recommendations = Completer<HgPage<HgVideoCard>>();

  @override
  Future<List<String>> hotSearchWords() async => ['都市'];
  @override
  Future<List<String>> hotSearchTags() async => ['逆袭'];
  @override
  Future<HgPage<HgVideoCard>> homeRecommendationsPage({
    int page = 1,
    int size = 20,
  }) => recommendations.future;
  @override
  Future<List<String>> searchSuggestions(String keyword) =>
      (suggestions[keyword] ??= Completer<List<String>>()).future;
  @override
  Future<HgPage<HgVideoCard>> search(
    String keyword, {
    int page = 1,
    int size = 20,
  }) {
    requests.add((keyword, page));
    final result = Completer<HgPage<HgVideoCard>>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<HgVideoDetail> video(int id) async =>
      HgVideoDetail.fromJson({'id': id, 'title': '短剧$id', 'cover': ''});
}

Future<void> _mount(
  WidgetTester tester,
  _SearchApi api, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = AuthController(api, prefs);
  final downloads = HgDownloadManager(api, prefs);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<HgApi>.value(value: api),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: downloads),
      ],
      child: MaterialApp(
        theme: buildHgTheme(dark ? Brightness.dark : Brightness.light),
        home: const SearchPage(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

List<int> _shown(WidgetTester tester) => tester
    .widgetList<HgVideoGridCard>(find.byType(HgVideoGridCard))
    .map((card) => card.video.id)
    .toList();

void main() {
  testWidgets('newer search wins over a late response for a previous query', (
    tester,
  ) async {
    HgLocalHistory.resetQueueForTesting();
    final api = _SearchApi();
    await _mount(tester, api);
    await _submit(tester, '旧关键词');
    await _submit(tester, '新关键词');
    api.pending[1].complete(_page([2]));
    await tester.pump();
    expect(_shown(tester), [2]);
    api.pending[0].complete(_page([1]));
    await tester.pump();
    expect(_shown(tester), [2]);
    expect(find.text('「新关键词」的搜索结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clearing an in-flight search ignores its late error and keeps input focus',
    (tester) async {
      final api = _SearchApi();
      await _mount(tester, api);
      await _submit(tester, '待返回');
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      api.pending.single.completeError(Exception('late failure'));
      await tester.pump();
      expect(find.byType(HgErrorState), findsNothing);
      expect(find.byType(HgLoading), findsNothing);
      expect(_shown(tester), isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing a submitted query shows readable dark suggestions and ignores late suggestions after submit',
    (tester) async {
      final api = _SearchApi();
      await _mount(tester, api, dark: true);
      await _submit(tester, '已提交');
      api.pending.single.complete(_page([1]));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '新');
      await tester.pump(const Duration(milliseconds: 300));
      api.suggestions['新']!.complete(['新联想词']);
      await tester.pump();
      await tester.pump();
      final suggestion = tester.widget<Text>(find.text('新联想词'));
      expect(
        suggestion.style!.color,
        buildHgTheme(Brightness.dark).colorScheme.onSurface,
      );
      await tester.enterText(find.byType(TextField), '新词');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      api.suggestions['新词']!.complete(['过期联想词']);
      api.pending.last.complete(_page([2]));
      await tester.pump();
      expect(find.text('过期联想词'), findsNothing);
      expect(_shown(tester), [2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination failure keeps results and retries the same page without duplicate cards',
    (tester) async {
      final api = _SearchApi();
      await _mount(tester, api);
      await _submit(tester, '都市');
      api.pending.single.complete(
        _page(List.generate(8, (i) => i + 1), pages: 2),
      );
      await tester.pump();
      expect(find.text('已经到底了'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1800));
      await tester.pump();
      expect(api.requests.last, ('都市', 2));
      api.pending.last.completeError(Exception('timeout'));
      await tester.pump();
      expect(find.byType(HgErrorState), findsNothing);
      expect(find.byType(HgVideoGridCard), findsWidgets);
      final retry = find.text('加载中断，点此重试');
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pump();
      expect(api.requests, [('都市', 1), ('都市', 2), ('都市', 2)]);
      api.pending.last.complete(_page([8, 9], page: 2, pages: 2));
      await tester.pump();
      expect(find.text('加载中断，点此重试'), findsNothing);
      final shown = _shown(tester);
      expect(shown.where((id) => id == 8).length, 1);
      expect(shown, contains(9));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('已经到底了'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a short first page automatically fetches the next page', (
    tester,
  ) async {
    final api = _SearchApi();
    await _mount(tester, api);
    await _submit(tester, '短列表');
    api.pending.single.complete(_page([1], pages: 2));
    await tester.pump();
    expect(api.requests, [('短列表', 1), ('短列表', 2)]);
    api.pending.last.complete(_page([2], page: 2, pages: 2));
    await tester.pump();
    expect(_shown(tester), [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late pagination response cannot append to a different query', (
    tester,
  ) async {
    final api = _SearchApi();
    await _mount(tester, api);
    await _submit(tester, '旧列表');
    api.pending.single.complete(
      _page(List.generate(8, (i) => i + 1), pages: 2),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1800));
    await tester.pump();
    final oldPage = api.pending.last;
    expect(api.requests.last, ('旧列表', 2));
    await _submit(tester, '新列表');
    api.pending.last.complete(_page([30]));
    await tester.pump();
    oldPage.complete(_page([9], page: 2, pages: 2));
    await tester.pump();
    expect(_shown(tester), [30]);
    expect(find.text('「新列表」的搜索结果'), findsOneWidget);
    expect(
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .offset,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recommendation opens detail with its matching neighboring feed',
    (tester) async {
      final api = _SearchApi();
      await _mount(tester, api);
      api.recommendations.complete(_page([11, 12, 13]));
      await tester.pump();
      final card = find.byType(HgVideoRailCard).at(1);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      HgLocalHistory.resetQueueForTesting();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final detail = tester.widget<DramaDetailPage>(
        find.byType(DramaDetailPage),
      );
      expect(detail.videoId, 12);
      expect(detail.feedIds, [11, 12, 13]);
      expect(detail.feedIndex, 1);
      expect(find.byType(HgLoading), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search bar stays visible and returning from detail restores scroll and results',
    (tester) async {
      final api = _SearchApi();
      await _mount(tester, api);
      await _submit(tester, '长列表');
      api.pending.single.complete(_page(List.generate(24, (i) => i + 1)));
      await tester.pump();
      final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(400));
      expect(tester.getTopLeft(find.byType(TextField)).dy, fieldTop);
      final card = find.byType(HgVideoGridCard).at(4);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final beforeDetail = scroll.offset;
      HgLocalHistory.resetQueueForTesting();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final detail = tester.widget<DramaDetailPage>(
        find.byType(DramaDetailPage),
      );
      expect(detail.feedIds.length, 24);
      expect(find.byType(HgLoading), findsNothing);
      Navigator.of(tester.element(find.byType(DramaDetailPage))).pop();
      await tester.pumpAndSettle();
      expect(scroll.offset, beforeDetail);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '长列表',
      );
      expect(api.requests, [('长列表', 1)]);
      await tester.enterText(find.byType(TextField), '下一个');
      await tester.pump();
      expect(scroll.offset, 0);
      await tester.pump(const Duration(milliseconds: 300));
      api.suggestions['下一个']!.complete(['下一个联想']);
      await tester.pump();
      await tester.pump();
      expect(find.text('下一个联想'), findsOneWidget);
      expect(tester.getTopLeft(find.text('下一个联想')).dy, lessThan(160));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hot words appear without waiting for recommendations', (
    tester,
  ) async {
    final api = _SearchApi();
    await _mount(tester, api);
    expect(find.text('大家都在搜'), findsOneWidget);
    expect(find.text('都市'), findsOneWidget);
    expect(api.recommendations.isCompleted, isFalse);
    expect(find.byType(HgLoading), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('recommendation rail supports text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildHgTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) => Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: HgVideoRailCard.heightFor(context, width: 134),
                    child: HgVideoRailCard(
                      video: const HgVideoCard(id: 1, title: '短剧标题', cover: ''),
                      onTap: () {},
                      width: 134,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('短剧标题'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'grid cards show episode information once and omit empty heat counts',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 280,
              child: HgVideoGridCard(
                video: const HgVideoCard(
                  id: 1,
                  title: '短剧',
                  cover: '',
                  episodeCount: 12,
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('更新至 12 集'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
