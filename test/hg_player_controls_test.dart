import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/widgets/hg_playback_feedback.dart';
import 'package:guomu/hg/widgets/hg_player_seek_bar.dart';

void main() {
  testWidgets('seek thumb stays at target until seek completes', (
    tester,
  ) async {
    var scrubbing = false;
    var seeking = false;
    var position = const Duration(seconds: 10);
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return HgPlayerSeekBar(
                position: position,
                duration: const Duration(seconds: 100),
                buffered: const Duration(seconds: 80),
                scrubbing: scrubbing,
                seeking: seeking,
                showTimeLabels: false,
                onScrubStart: (_) => rebuild(() => scrubbing = true),
                onScrubUpdate: (_) {},
                onScrubEnd: (_) => rebuild(() {
                  scrubbing = false;
                  seeking = true;
                }),
              );
            },
          ),
        ),
      ),
    );
    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(0.6);
    await tester.pump();
    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.6);
    slider.onChangeEnd!(0.6);
    await tester.pump();
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0.6);
    expect(slider.secondaryTrackValue, 0.8);
    expect(slider.onChanged, isNull);
    rebuild(() {
      seeking = false;
      position = const Duration(seconds: 60);
    });
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.6);
    rebuild(() => position = const Duration(seconds: 61));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.61);
  });

  testWidgets('buffering ignores brief stalls and cancels on dispose', (
    tester,
  ) async {
    Future<void> render(bool busy, {bool paused = false}) => tester.pumpWidget(
      MaterialApp(
        home: HgPlaybackFeedback(busy: busy, paused: paused),
      ),
    );
    await render(true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await render(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await render(true);
    await tester.pump(const Duration(milliseconds: 351));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await render(false, paused: true);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await render(true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
