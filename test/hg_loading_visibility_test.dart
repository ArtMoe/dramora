import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/widgets/hg_components.dart';

Widget _host({required bool tickerEnabled}) {
  return MaterialApp(
    home: TickerMode(
      enabled: tickerEnabled,
      child: const Scaffold(body: SingleChildScrollView(child: HgLoading())),
    ),
  );
}

void main() {
  testWidgets('loading shimmer renders in both active and offstage tabs', (
    tester,
  ) async {
    await tester.pumpWidget(_host(tickerEnabled: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HgLoading), findsOneWidget);

    await tester.pumpWidget(_host(tickerEnabled: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HgLoading), findsOneWidget);

    await tester.pumpWidget(_host(tickerEnabled: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
