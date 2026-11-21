import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/auth/app_controllers.dart';
import 'package:guomu/hg/pages/settings_page.dart';
import 'package:guomu/hg/theme/hg_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('official generated source arrays support changing domain families', () {
    final sources = parseHgPublisherSources(
      "var subdomains=['thu', // comment\n'pku']; var urls=['new-example.cc/'];",
    );
    expect(sources, [
      'https://thu.new-example.cc',
      'https://pku.new-example.cc',
    ]);
    expect(
      parseHgPublisherSources(
        "var subdomains=['../bad'];var urls=['127.0.0.1/'];",
      ),
      isEmpty,
    );
  });

  for (final size in [const Size(320, 700), const Size(844, 390)]) {
    testWidgets('source editor supports selection and manual input at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = HgApi(baseUrl: 'https://example.test');
      final source = SourceController(
        prefs,
        probeSource: (address) async => HgSourceProbeResult(
          baseUrl: address,
          available: true,
          latency: const Duration(milliseconds: 50),
        ),
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<HgApi>.value(value: api),
            ChangeNotifierProvider.value(value: source),
          ],
          child: MaterialApp(
            theme: buildHgTheme(Brightness.dark),
            home: const Scaffold(body: HgSourceEditorSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接与数据源'), findsOneWidget);
      expect(find.text('当前连接'), findsOneWidget);
      await tester.tap(find.text('自动选择最佳线路'));
      await tester.pumpAndSettle();
      expect(source.automaticSelection, isFalse);
      final add = find.text('添加自定义地址');
      await tester.scrollUntilVisible(
        add,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      await tester.ensureVisible(input);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'https://new.example.cc');
      final confirm = find.text('验证并添加');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(source.sources, contains('https://new.example.cc'));
      expect(tester.takeException(), isNull);
    });
  }
}
