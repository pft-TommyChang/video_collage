part of '../video_collage_app.dart';

extension _AppController on _VideoCollageScreenState {
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      _updateState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    } catch (_) {
      // Keep the header usable if package metadata is unavailable.
    }
  }

  Future<Object?> _handleMediaOpenMethodCall(MethodCall call) async {
    if (call.method != 'mediaFilesOpened') {
      throw MissingPluginException('Unknown method ${call.method}');
    }
    await _consumeOpenedMediaFiles();
    return null;
  }

  Future<void> _consumeOpenedMediaFiles() async {
    if (_isConsumingOpenedMedia) {
      _shouldConsumeOpenedMediaAgain = true;
      return;
    }

    _isConsumingOpenedMedia = true;
    try {
      do {
        _shouldConsumeOpenedMediaAgain = false;
        final openedPaths = await _VideoCollageScreenState._mediaOpenChannel
            .invokeListMethod<String>('consumePendingMediaFiles');
        if (!mounted || openedPaths == null || openedPaths.isEmpty) {
          continue;
        }

        final supportedPaths = openedPaths
            .where(_isSupportedMediaPath)
            .toList(growable: false);
        if (supportedPaths.isEmpty) {
          _updateState(() {
            _statusMessage = 'The opened files are not supported media.';
          });
          continue;
        }

        final importedCount = await _importExternalMedia(supportedPaths);
        if (importedCount > 0 && mounted) {
          _autoLayout();
        }
      } while (_shouldConsumeOpenedMediaAgain);
    } on MissingPluginException {
      // The channel only exists in the macOS app.
    } on PlatformException catch (error) {
      if (mounted) {
        _updateState(() {
          _statusMessage =
              'Unable to import opened media: ${error.message ?? error.code}';
        });
      }
    } finally {
      _isConsumingOpenedMedia = false;
    }
  }
}
