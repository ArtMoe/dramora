import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/pages/login_sheet.dart';
import 'package:guomu/hg/widgets/hg_adaptive_sheet.dart';

void main() {
  testWidgets('login sheet uses its drag handle instead of a close button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHgAdaptiveSheetBuilder<bool>(
                context,
                childScrollable: true,
                builder: (_) => const LoginSheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('登录黄果'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  });
}
