import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'src/video_collage_app.dart';

void main(List<String> arguments) {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  VideoPlayerMediaKit.ensureInitialized(macOS: true, windows: true);
  _installKnownFlutterDesktopWorkarounds();
  final c2paLaunch = parseC2paLaunchArguments(arguments);
  runApp(
    VideoCollageApp(
      deferFirstFrameUntilSettingsRestored: true,
      c2paLaunchMode: c2paLaunch.enabled,
      initialC2paPath: c2paLaunch.path,
    ),
  );
}

void _installKnownFlutterDesktopWorkarounds() {
  final previousOnError = FlutterError.onError;
  var duplicateKeyAssertionReported = false;

  FlutterError.onError = (FlutterErrorDetails details) {
    final exceptionText = details.exceptionAsString();
    final isDuplicateKeyAssertion = exceptionText.contains(
      'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed.',
    );

    if (isDuplicateKeyAssertion) {
      if (!duplicateKeyAssertionReported) {
        duplicateKeyAssertionReported = true;
        debugPrint(
          'Ignored known Flutter desktop keyboard assertion: duplicate KeyDownEvent state mismatch.',
        );
      }
      return;
    }

    if (previousOnError != null) {
      previousOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}
