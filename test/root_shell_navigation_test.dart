import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/pages/root_shell.dart';
import 'package:guomu/hg/theme/hg_theme.dart';

const _items = [
  (Icons.home_outlined, Icons.home_rounded, '首页'),
  (Icons.grid_view_outlined, Icons.grid_view_rounded, '剧场'),
  (Icons.forum_outlined, Icons.forum_rounded, '吃瓜'),
  (Icons.emoji_events_outlined, Icons.emoji_events_rounded, '榜单'),
  (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
];

Widget _host({required int index, required ValueChanged<int> onSelected}) {
  return MaterialApp(
    theme: buildHgTheme(Brightness.light),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: HgAppBottomBar(
        index: index,
        items: _items,
        onSelected: onSelected,
      ),
    ),
  );
}

void main() {
  testWidgets('bottom navigation highlight wraps both icon and label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selected = 0;
    await tester.pumpWidget(
      _host(index: 0, onSelected: (value) => selected = value),
    );
    final firstSurface = tester.getRect(
      find.byKey(const ValueKey('hg-nav-surface-0')),
    );
    final firstLabel = tester.getRect(find.text('首页'));
    expect(firstSurface.left, lessThanOrEqualTo(firstLabel.left));
    expect(firstSurface.right, greaterThanOrEqualTo(firstLabel.right));
    expect(firstSurface.top, lessThanOrEqualTo(firstLabel.top));
    expect(firstSurface.bottom, greaterThanOrEqualTo(firstLabel.bottom));

    final firstDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('hg-nav-surface-0')),
                )
                .decoration
            as BoxDecoration;
    expect(firstDecoration.color, isNot(Colors.transparent));

    await tester.tap(find.byKey(const ValueKey('hg-nav-item-1')));
    expect(selected, 1);

    await tester.pumpWidget(_host(index: 1, onSelected: (_) {}));
    await tester.pump(const Duration(milliseconds: 250));
    final secondDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('hg-nav-surface-1')),
                )
                .decoration
            as BoxDecoration;
    expect(secondDecoration.color, isNot(Colors.transparent));
    final secondSurface = tester.getRect(
      find.byKey(const ValueKey('hg-nav-surface-1')),
    );
    final secondLabel = tester.getRect(find.text('剧场'));
    expect(secondSurface.contains(secondLabel.topLeft), isTrue);
    expect(secondSurface.contains(secondLabel.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });
}
