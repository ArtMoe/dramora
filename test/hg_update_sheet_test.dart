import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/pages/update_sheet.dart';
import 'package:guomu/hg/theme/hg_theme.dart';
import 'package:guomu/hg/utils/hg_update_service.dart';

const _result = HgUpdateCheckResult(
  currentVersion: '1.0.0',
  release: HgReleaseUpdate(
    tagName: 'v9.0.0',
    title: '新版本',
    body: '修复播放与连接问题',
    htmlUrl: 'https://github.com/DearLicy/guomu/releases/latest',
    publishedAt: '',
    assets: [
      HgReleaseAsset(
        name: 'new.apk',
        downloadUrl: 'https://github.com/a.apk',
        size: 100,
        apiUrl: 'https://api.github.com/repos/DearLicy/guomu/releases/assets/1',
      ),
    ],
  ),
);

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'Android update shows progress and automatically opens installer at $size',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const channel = MethodChannel('com.guomu.huangguo/update');
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final completed = Completer<String>();
        void Function(int, int)? progress;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildHgTheme(Brightness.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showHgUpdateResultSheet(
                    context,
                    _result,
                    download:
                        (
                          asset, {
                          CancelToken? cancelToken,
                          void Function(int, int)? onProgress,
                        }) {
                          progress = onProgress;
                          return completed.future;
                        },
                  ),
                  child: const Text('更新'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('更新'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下载并安装'));
        await tester.pump();
        progress!(50, 100);
        await tester.pump();
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          0.5,
        );
        expect(find.text('取消下载'), findsOneWidget);
        completed.complete('/cache/guomu-updates/new.apk');
        await tester.pump();
        await tester.pump();
        expect(calls.single.method, 'installApk');
        expect(find.text('打开安装程序'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('iOS update explains manual installation', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showHgUpdateResultSheet(context, _result),
              child: const Text('更新'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.text('前往手动更新'), findsOneWidget);
    expect(find.textContaining('iOS 需要手动更新'), findsOneWidget);
    expect(find.text('下载并安装'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
