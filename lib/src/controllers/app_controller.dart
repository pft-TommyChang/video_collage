part of '../video_collage_app.dart';

extension _AppController on _VideoCollageScreenState {
  Future<void> _refreshC2paTrustListInBackground() async {
    try {
      final didUpdate = await _exportService.refreshC2paTrustList();
      if (!didUpdate || !mounted) {
        return;
      }

      final clips = _clips
          .map((clip) => (id: clip.id, path: clip.path))
          .toList(growable: false);
      for (final clip in clips) {
        await _refreshClipAiMetadata(clip.id, clip.path);
      }
    } catch (error) {
      debugPrint('Background C2PA trust list update failed: $error');
    }
  }

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

  Future<void> _checkForUpdatesInBackground() async {
    if (_isCheckingForUpdates) {
      return;
    }

    _isCheckingForUpdates = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final release = await widget.updateService.fetchLatestRelease();
      if (!mounted) {
        return;
      }

      final hasUpdate = GitHubUpdateService.isNewerVersion(
        currentVersion: packageInfo.version,
        releaseTag: release.tagName,
      );
      if (hasUpdate) {
        _updateState(() {
          _availableUpdate = release;
        });
      }
    } catch (error) {
      debugPrint('Background update check failed: $error');
    } finally {
      _isCheckingForUpdates = false;
    }
  }

  Future<void> _openReleasePage() async {
    final pageUrl =
        _availableUpdate?.pageUrl ??
        Uri.https(
          'github.com',
          '/${widget.updateService.owner}/${widget.updateService.repository}/releases',
        );
    try {
      final didLaunch = await launchUrl(
        pageUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!didLaunch && mounted) {
        _showToast('Unable to open the GitHub Release page.');
      }
    } catch (_) {
      if (mounted) {
        _showToast('Unable to open the GitHub Release page.');
      }
    }
  }
}
