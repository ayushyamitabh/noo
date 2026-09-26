// Host-side driver for integration_test/store_screenshots_test.dart (run via
// tool/screenshots.sh). Each time the test asks for a screenshot this saves
// a PNG named after it into $SCREENSHOT_DIR.
//
// These bytes are the Flutter surface only (no OS status bar) - an earlier
// version of this file tried to re-capture the screen with `adb exec-out
// screencap` for a "real" screenshot including it, but on Android,
// `onScreenshot` only fires once the whole test has finished (see
// `IntegrationTestWidgetsFlutterBinding`/`integrationDriver`'s source: the
// native platform channel hands screenshot bytes straight to `reportData`
// with no round trip to the driver, and the driver's first `requestData`
// call blocks until every `testWidgets` body in the file has returned) - so
// every `adb screencap` call was capturing the same final frame, regardless
// of which named screenshot it was meant to be. Saving these bytes directly
// is what actually gives each name its own distinct image.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outDir = Directory(
    Platform.environment['SCREENSHOT_DIR'] ?? 'store_listing/screenshots',
  )..createSync(recursive: true);

  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
          stdout.writeln('saved $name.png');
          return true;
        },
  );
}
