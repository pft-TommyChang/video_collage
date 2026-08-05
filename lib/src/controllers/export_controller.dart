part of '../video_collage_app.dart';

extension _ExportController on _VideoCollageScreenState {
  Future<void> _showVideoMergeTool() async {
    _updateState(() => _isVideoMergeDialogOpen = true);
    String? outputPath;
    try {
      outputPath = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => VideoMergeDialog(
          exportService: _exportService,
          dialogService: _dialogService,
          initialVideos: _clips
              .where((clip) => clip.isVideo)
              .toList(growable: false),
          initialDirectory: _lastExportDirectory.isEmpty
              ? null
              : _lastExportDirectory,
          initialFitMode: _mergeFitMode,
          initialFrameRateMode: _mergeFrameRateMode,
          onSettingsChanged: (fitMode, frameRateMode) {
            _mergeFitMode = fitMode;
            _mergeFrameRateMode = frameRateMode;
            _scheduleSettingsSave();
          },
        ),
      );
    } finally {
      if (mounted) {
        _updateState(() => _isVideoMergeDialogOpen = false);
      }
    }
    if (!mounted || outputPath == null) {
      return;
    }
    final completedPath = outputPath;
    _updateState(() {
      _lastExportDirectory = p.dirname(completedPath);
      _statusMessage = 'Video merge complete: $completedPath';
    });
    await _persistSettings();
  }

  Future<void> _export() async {
    if (_clips.isEmpty) {
      _updateState(() {
        _statusMessage = 'Add media before exporting.';
      });
      return;
    }

    final options = _options;
    final slotClips = _slotClipsForExport();
    final exportFormat = exportFormatForClips(slotClips);
    if (!_isValidOutputResolution(options.outputWidth, options.outputHeight)) {
      _updateState(() {
        _statusMessage = _outputResolutionRangeMessage;
      });
      return;
    }

    final savePath = await _dialogService.pickSavePath(
      format: exportFormat,
      suggestedName: _suggestedExportFileName(exportFormat),
      initialDirectory: _lastExportDirectory.isEmpty
          ? null
          : _lastExportDirectory,
    );
    if (savePath == null || savePath.isEmpty) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Export cancelled.';
      });
      return;
    }

    var completedSuccessfully = false;
    _updateState(() {
      _cancelExportCompletionTimer();
      _isExporting = true;
      _showExportComplete = false;
      _exportProgress = 0;
      _statusMessage = exportFormat == ExportFormat.jpg
          ? 'Exporting collage image...'
          : 'Exporting collage video...';
    });

    try {
      await _exportService.exportCollage(
        slotClips: slotClips,
        options: options,
        outputPath: savePath,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          final percent = (progress.progress * 100).round().clamp(0, 100);
          final speedText = progress.speed == null || progress.speed! <= 0
              ? ''
              : ' • ${progress.speed!.toStringAsFixed(2)}x';
          _updateState(() {
            _exportProgress = progress.progress;
            _statusMessage = exportFormat == ExportFormat.jpg
                ? 'Exporting collage image... $percent%'
                : 'Exporting collage video... $percent% • ${formatDuration(progress.processed)} / ${formatDuration(progress.total)}$speedText';
          });
        },
      );
      if (!mounted) {
        return;
      }
      await _recordExportHistory(savePath, exportFormat);
      if (!mounted) {
        return;
      }
      final exportDirectory = p.dirname(savePath);
      _updateState(() {
        _lastExportDirectory = exportDirectory;
        _showExportComplete = true;
        _exportProgress = 1;
        _statusMessage = 'Export complete: $savePath';
      });
      completedSuccessfully = true;
      await _persistSettings();
    } on VideoExportException catch (error) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _showExportComplete = false;
        _statusMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _showExportComplete = false;
        _statusMessage = 'Export failed: $error';
      });
    } finally {
      if (mounted) {
        _updateState(() {
          _isExporting = false;
          if (!completedSuccessfully) {
            _exportProgress = 0;
          }
        });
        if (completedSuccessfully) {
          _scheduleExportButtonReset();
        }
      }
    }
  }

  Future<void> _handleExportButtonPressed() async {
    if (!_isExporting) {
      await _export();
      return;
    }

    _updateState(() {
      _statusMessage = 'Stopping export...';
    });
    await _exportService.cancelActiveExport();
  }
}
