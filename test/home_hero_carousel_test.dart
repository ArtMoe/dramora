import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/models/hg_models.dart';
import 'package:guomu/hg/pages/home_page.dart';

HgHomeBanner _banner(int id, String title) =>
    HgHomeBanner(id: id, videoId: id, title: title, image: '', description: '');

Widget _host(List<HgHomeBanner> banners, {bool tickerEnabled = true}) {
  return MaterialApp(
    home: Scaffold(
      body: TickerMode(
        enabled: tickerEnabled,
        child: HomeHeroCarousel(banners: banners, onTap: (_) {}),
      ),
    ),
  );
}

void main() {
  testWidgets('carousel starts on the first aligned slide and advances', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([_banner(1, '第一张'), _banner(2, '第二张'), _banner(3, '第三张')]),
    );
    await tester.pump();
    expect(find.text('第一张').hitTestable(), findsOneWidget);
    expect(find.text('第二张').hitTestable(), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('第二张').hitTestable(), findsOneWidget);
  });

  testWidgets('carousel does not advance while its tab is offstage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([_banner(1, '第一张'), _banner(2, '第二张')], tickerEnabled: false),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('第一张').hitTestable(), findsOneWidget);
    expect(find.text('第二张').hitTestable(), findsNothing);
  });
}
