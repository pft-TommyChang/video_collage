import 'dart:io';

import 'package:flutter/services.dart';

class C2paViewerException implements Exception {
  const C2paViewerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class C2paViewerService {
  const C2paViewerService();

  static const MethodChannel _channel = MethodChannel(
    'video_collage/c2pa_viewer',
  );

  Future<void> open(String mediaPath) async {
    if (!Platform.isMacOS) {
      throw const C2paViewerException(
        'Perfect C2PA integration is currently available on macOS.',
      );
    }
    try {
      await _channel.invokeMethod<void>('openMedia', <String, String>{
        'path': mediaPath,
      });
    } on PlatformException catch (error) {
      throw C2paViewerException(
        error.code == 'viewer-not-installed'
            ? 'Perfect C2PA is not installed. Install it to inspect Content Credentials.'
            : error.message ?? 'Unable to open Perfect C2PA.',
      );
    } on MissingPluginException {
      throw const C2paViewerException(
        'Perfect C2PA integration is unavailable in this build.',
      );
    }
  }
}
