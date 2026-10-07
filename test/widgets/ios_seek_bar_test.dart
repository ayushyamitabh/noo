import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/viewer/media_video_preview.dart';
import 'package:video_player/video_player.dart';
import 'noo/noo_test_utils.dart';

class _Controller extends VideoPlayerController {
  _Controller() : super.networkUrl(Uri.parse('https://example.com/video.mp4'));
  Duration? sought;
  @override
  Future<void> seekTo(Duration position) async {
    sought = position;
    value = value.copyWith(position: position);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }
}

void main() {
  setUpNooTests();
  for (final playing in [false, true]) {
    testWidgets('iOS scrubbing preserves playing=$playing', (tester) async {
      final controller = _Controller();
      controller.value = VideoPlayerValue(
        duration: const Duration(seconds: 60),
        position: const Duration(seconds: 15),
        isInitialized: true,
        isPlaying: playing,
      );
      await pumpNoo(
        tester,
        IosSeekBar(controller: controller, color: CupertinoColors.white),
      );
      final slider = tester.widget<CupertinoSlider>(
        find.byType(CupertinoSlider),
      );
      expect(slider.value, 0.25);
      slider.onChangeStart!(0.25);
      expect(controller.value.isPlaying, false);
      slider.onChanged!(0.5);
      await tester.pump();
      expect(controller.sought, const Duration(seconds: 30));
      slider.onChangeEnd!(0.5);
      await tester.pump();
      expect(controller.value.isPlaying, playing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });
  }
  testWidgets('iOS scrubber disables seeking before duration is available', (
    tester,
  ) async {
    final controller = _Controller();
    await pumpNoo(
      tester,
      IosSeekBar(controller: controller, color: CupertinoColors.white),
    );
    expect(
      tester.widget<CupertinoSlider>(find.byType(CupertinoSlider)).onChanged,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
  });
}
