import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/theme/hg_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Chinese button labels retain bundled fallback in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildHgTheme(brightness),
            home: Scaffold(
              body: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.star_border_rounded),
                    label: const Text('追剧'),
                  ),
                  FilledButton(onPressed: () {}, child: const Text('立即播放')),
                  TextButton(onPressed: () {}, child: const Text('先看看界面')),
                ],
              ),
            ),
          ),
        );
        for (final label in ['追剧', '立即播放', '先看看界面']) {
          final richText = tester.widget<RichText>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          );
          expect(
            richText.text.style!.fontFamilyFallback,
            contains('GuomuCJK'),
            reason: '$label needs Chinese glyphs when system fonts are absent',
          );
        }
      },
    );
  }
}
