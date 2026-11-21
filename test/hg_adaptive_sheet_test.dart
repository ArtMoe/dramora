import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/widgets/hg_adaptive_sheet.dart';

void main() {
  testWidgets('adaptive sheet expands and dismisses with drag gestures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showHgAdaptiveSheet<void>(
                  context,
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('sheet content'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet content'), findsOneWidget);

    final before = tester.getTopLeft(find.text('sheet content')).dy;
    await tester.drag(
      find.byKey(const ValueKey('hg-sheet-drag-handle')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('sheet content')).dy;
    expect(after, lessThan(before));

    await tester.drag(
      find.byKey(const ValueKey('hg-sheet-drag-handle')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet content'), findsNothing);
  });

  testWidgets('scrollable sheet content remains scrollable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showHgAdaptiveSheetBuilder<void>(
                  context,
                  childScrollable: true,
                  builder: (_) => ListView.builder(
                    itemCount: 30,
                    itemBuilder: (_, index) =>
                        ListTile(title: Text('row $index')),
                  ),
                ),
                child: const Text('open list'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open list'));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsOneWidget);

    await tester.drag(find.text('row 0'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsNothing);
    expect(find.text('row 5'), findsOneWidget);
  });

  testWidgets('dragging the handle expands instead of only moving the route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHgAdaptiveSheet<void>(
                context,
                child: const Text('content'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final before = tester.getRect(
      find.byKey(const ValueKey('hg-adaptive-sheet')),
    );
    await tester.dragFrom(
      Offset(before.center.dx, before.top + 24),
      const Offset(0, -230),
    );
    await tester.pumpAndSettle();
    final after = tester.getRect(
      find.byKey(const ValueKey('hg-adaptive-sheet')),
    );
    expect(after.height, greaterThan(before.height + 100));
    await tester.dragFrom(
      Offset(after.center.dx, after.top + 24),
      const Offset(0, 620),
    );
    await tester.pumpAndSettle();
    expect(find.text('content'), findsNothing);
  });

  testWidgets(
    'handle can resize empty sheets and cannot dismiss a required sheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHgAdaptiveSheet<void>(
                  context,
                  isDismissible: false,
                  enableDrag: true,
                  childScrollable: true,
                  child: const Text('required'),
                ),
                child: const Text('open required'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open required'));
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('hg-sheet-drag-handle'));
      final before = tester.getRect(
        find.byKey(const ValueKey('hg-adaptive-sheet')),
      );
      await tester.drag(handle, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('hg-adaptive-sheet'))).height,
        greaterThan(before.height + 100),
      );
      await tester.drag(handle, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.text('required'), findsOneWidget);
    },
  );

  testWidgets('keyboard inset is applied once at the shared sheet boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    EdgeInsets? childInsets;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHgAdaptiveSheetBuilder<void>(
                context,
                builder: (context) {
                  childInsets = MediaQuery.viewInsetsOf(context);
                  return const TextField();
                },
              ),
              child: const Text('open keyboard'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open keyboard'));
    await tester.pumpAndSettle();
    final before = tester.getRect(
      find.byKey(const ValueKey('hg-adaptive-sheet')),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final keyboard = tester.getRect(
      find.byKey(const ValueKey('hg-adaptive-sheet')),
    );
    expect(keyboard.bottom, closeTo(544, 1));
    expect(childInsets!.bottom, 0);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    final restored = tester.getRect(
      find.byKey(const ValueKey('hg-adaptive-sheet')),
    );
    expect(restored.bottom, closeTo(844, 1));
    expect(restored.height, closeTo(before.height, 1));
  });

  testWidgets('confirmation sheet returns explicit yes or no', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showHgConfirmSheet(
                    context,
                    title: '清除全部缓存？',
                    message: '会删除已下载的所有短剧文件。',
                    confirmLabel: '清除全部',
                    destructive: true,
                  );
                },
                child: const Text('confirm'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();
    expect(find.text('清除全部缓存？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hg-confirm-sheet-action')));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hg-confirm-sheet-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
