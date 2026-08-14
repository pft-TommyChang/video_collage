part of '../video_collage_app.dart';

typedef _PendingExternalReplacement = ({
  String id,
  String path,
  int? slotIndex,
  VideoClipInfo? replacedClip,
  String? inheritedLabel,
});

extension _MediaController on _VideoCollageScreenState {
  Future<void> _pickMedia() async {
    _updateState(() {
      _isImporting = true;
      _statusMessage = 'Selecting media...';
    });

    try {
      final selections = await _dialogService.pickMedia();
      final pendingClips = <({String id, PickedMediaFile selection})>[
        for (final selection in selections)
          (id: _newClipInstanceId(), selection: selection),
      ];

      if (pendingClips.isNotEmpty && mounted) {
        _updateState(() {
          for (final pending in pendingClips) {
            final initialClip = pending.selection.clipInfo;
            _clips.add(
              (initialClip ??
                      _placeholderClip(
                        pending.selection.path,
                        instanceId: pending.id,
                      ))
                  .copyWith(instanceId: pending.id),
            );
            _loadingClipIds.add(pending.id);
            _clipErrors.remove(pending.id);
            _slotAssignments[_nextAvailableSlot()] = pending.id;
          }
          _statusMessage =
              'Queued ${pendingClips.length} media item(s) for import.';
        });
      }

      for (final pending in pendingClips) {
        unawaited(
          _loadClip(
            pending.selection.path,
            instanceId: pending.id,
            initialClip: pending.selection.clipInfo,
          ),
        );
      }

      if (!mounted) {
        return;
      }

      _updateState(() {
        _statusMessage = pendingClips.isEmpty
            ? 'No media was selected.'
            : 'Added ${pendingClips.length} media item(s). Initializing previews...';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'File dialog failed: ${error.message ?? error.code}';
      });
    } on VideoExportException catch (error) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Unable to load media: $error';
      });
    } finally {
      if (mounted) {
        _updateState(() {
          _isImporting = false;
        });
      }
    }
  }

  void _removeClip(VideoClipInfo clip) {
    _controllers.remove(clip.id)?.dispose();
    _updateState(() {
      _removeClipState(clip.id);
      if (_controllers.isEmpty) {
        _isPreviewPlaying = false;
      }
      _statusMessage = 'Removed ${clip.name}.';
    });
    unawaited(_syncPreviewPlaybackMode());
  }

  void _removeClipState(String instanceId) {
    _clips.removeWhere((clip) => clip.id == instanceId);
    _slotAssignments.removeWhere((_, id) => id == instanceId);
    _clipViewports.remove(instanceId);
    _loadingClipIds.remove(instanceId);
    _clipErrors.remove(instanceId);
    if (_editingViewportClipId == instanceId) {
      _editingViewportClipId = null;
    }
  }

  void _clearClips() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _parallelPreviewTimer?.cancel();
    _parallelPreviewTimer = null;
    _parallelPreviewElapsed = Duration.zero;
    _parallelPreviewStartedAt = null;
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = null;
    _sequentialPreviewElapsed = Duration.zero;
    _sequentialPreviewStartedAt = null;
    _updateState(() {
      _clips.clear();
      _slotAssignments.clear();
      _clipViewports.clear();
      _loadingClipIds.clear();
      _clipErrors.clear();
      _isPreviewPlaying = false;
      _activeSequentialClipId = null;
      _editingViewportClipId = null;
      _statusMessage = 'Cleared all media.';
    });
  }

  Future<void> _confirmClearClips() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset media?'),
          content: const Text(
            'This will remove all loaded media from the current collage.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldClear == true && mounted) {
      _clearClips();
    }
  }

  Future<void> _confirmResetAll() async {
    final action = await showDialog<_ResetEverythingAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('What would you like to reset?'),
          content: const Text(
            'Export history and exported files will be kept.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_ResetEverythingAction.settingsOnly),
              child: const Text('Reset Settings Only'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_ResetEverythingAction.settingsAndMedia),
              child: const Text('Reset Settings + Media'),
            ),
          ],
        );
      },
    );

    if (action != null && mounted) {
      await _resetAll(
        removeMedia: action == _ResetEverythingAction.settingsAndMedia,
      );
    }
  }

  Future<void> _resetAll({required bool removeMedia}) async {
    if (removeMedia) {
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
    }
    _parallelPreviewTimer?.cancel();
    _parallelPreviewTimer = null;
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = null;
    final defaultSize = _sizeFromPreset(
      _defaultAspectPreset,
      _defaultResolutionPreset,
    );

    _updateState(() {
      if (removeMedia) {
        _clips.clear();
        _slotAssignments.clear();
        _loadingClipIds.clear();
        _clipErrors.clear();
      }
      _clipViewports.clear();
      _editingViewportClipId = null;
      _selectedAspect = _defaultAspectPreset;
      _selectedResolution = _defaultResolutionPreset;
      _selectedBorderColor = _defaultBorderColor;
      _selectedBackgroundColor = _defaultBackgroundColor;
      _borderImagePath = null;
      _selectedPlayMode = _defaultPlayMode;
      _selectedAudioMode = _defaultAudioMode;
      _selectedDurationMode = _defaultDurationMode;
      _selectedFitMode = _defaultFitMode;
      _mergeFitMode = ClipFitMode.cropCenter;
      _mergeFrameRateMode = VideoMergeFrameRateMode.firstVideo;
      _rows = _defaultRows;
      _columns = _defaultColumns;
      _isMediaSectionCollapsed = false;
      _isLayoutSectionCollapsed = false;
      _isLabelSectionCollapsed = false;
      _isOutputSectionCollapsed = false;
      _borderThickness = _defaultBorderThickness;
      _tileCornerRadius = _defaultTileCornerRadius;
      _clipLabelFontSize = _defaultClipLabelFontSize;
      _clipLabelPadding = _defaultClipLabelPadding;
      _includeClipLabelsInOutput = _defaultIncludeClipLabelsInOutput;
      _clipLabelDisplayMode = _defaultClipLabelDisplayMode;
      _clipLabelAlignment = _defaultClipLabelAlignment;
      _clipLabelVisualStyle = _defaultClipLabelVisualStyle;
      _appendDateTimeToExportName = _defaultAppendDateTimeToExportName;
      _lastExportDirectory = '';
      _setAppliedResolution(
        width: defaultSize.$1,
        height: defaultSize.$2,
        preset: _defaultResolutionPreset,
      );
      _isPreviewPlaying = false;
      _isPreviewMuted = false;
      _showExportComplete = false;
      _exportProgress = 0;
      _lastPreviewProgressSecond = null;
      _parallelPreviewElapsed = Duration.zero;
      _parallelPreviewStartedAt = null;
      _sequentialPreviewElapsed = Duration.zero;
      _sequentialPreviewStartedAt = null;
      _activeSequentialClipId = null;
      _externalDropHoverSlotIndex = null;
      if (!removeMedia) {
        _backfillVisibleSlotsFromOverflow();
      }
      _statusMessage = removeMedia
          ? 'Settings reset and all media removed.'
          : 'Settings reset. Loaded media kept.';
    });
    _scheduleSettingsSave();
    await _syncPreviewPlaybackMode();
  }

  void _resetLayoutDefaults() {
    final size = _sizeFromPreset(
      _defaultAspectPreset,
      _effectiveResolutionForSizing,
    );
    _setStateAndSave(() {
      _selectedAspect = _defaultAspectPreset;
      _rows = _defaultRows;
      _columns = _defaultColumns;
      _borderThickness = _defaultBorderThickness;
      _tileCornerRadius = _defaultTileCornerRadius;
      _selectedBorderColor = _defaultBorderColor;
      _selectedBackgroundColor = _defaultBackgroundColor;
      _borderImagePath = null;
      _selectedFitMode = _defaultFitMode;
      _setAppliedResolution(width: size.$1, height: size.$2);
      _backfillVisibleSlotsFromOverflow();
      _statusMessage = 'Layout reset to defaults.';
    });
  }

  void _resetLabelDefaults() {
    _setStateAndSave(() {
      _clipLabelFontSize = _defaultClipLabelFontSize;
      _clipLabelPadding = _defaultClipLabelPadding;
      _includeClipLabelsInOutput = _defaultIncludeClipLabelsInOutput;
      _clipLabelDisplayMode = _defaultClipLabelDisplayMode;
      _clipLabelAlignment = _defaultClipLabelAlignment;
      _clipLabelVisualStyle = _defaultClipLabelVisualStyle;
      _statusMessage = 'Label settings reset to defaults.';
    });
  }

  Future<void> _resetOutputDefaults() async {
    final size = _sizeFromPreset(_selectedAspect, _defaultResolutionPreset);
    _setStateAndSave(() {
      _selectedPlayMode = _defaultPlayMode;
      _selectedAudioMode = _defaultAudioMode;
      _selectedDurationMode = _defaultDurationMode;
      _appendDateTimeToExportName = _defaultAppendDateTimeToExportName;
      _setAppliedResolution(
        width: size.$1,
        height: size.$2,
        preset: _defaultResolutionPreset,
      );
      _activeSequentialClipId = null;
      _statusMessage = 'Output reset to defaults.';
    });

    _parallelPreviewElapsed = Duration.zero;
    _parallelPreviewStartedAt = null;
    _parallelPreviewTimer?.cancel();
    _parallelPreviewTimer = null;
    _sequentialPreviewElapsed = Duration.zero;
    _sequentialPreviewStartedAt = null;
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = null;
    await _syncPreviewPlaybackMode();
  }

  void _applyResolutionPreset(ResolutionPreset preset) {
    if (preset == _customResolutionPreset) {
      _setStateAndSave(() {
        _selectedResolution = _customResolutionPreset;
      });
      return;
    }

    final size = _sizeFromPreset(_selectedAspect, preset);
    _setStateAndSave(() {
      _setAppliedResolution(width: size.$1, height: size.$2, preset: preset);
    });
  }

  void _applyCustomResolution() {
    final parsedSize = _parseResolutionDraft();
    if (parsedSize == null) {
      _updateState(() {
        _statusMessage = _outputResolutionRangeMessage;
      });
      return;
    }

    _setStateAndSave(() {
      _setAppliedResolution(
        width: parsedSize.$1,
        height: parsedSize.$2,
        preset: _customResolutionPreset,
      );
      _statusMessage = 'Custom resolution applied.';
    });
  }

  Future<void> _handlePlayModeSelected(PlayMode mode) async {
    final wasSequential = _isSequentialPlayMode;
    _setStateAndSave(() {
      _selectedPlayMode = mode;
      if (mode != PlayMode.sequential) {
        _activeSequentialClipId = null;
      }
    });

    if (mode == PlayMode.sequential && !wasSequential) {
      _parallelPreviewElapsed = Duration.zero;
      _parallelPreviewStartedAt = null;
      _parallelPreviewTimer?.cancel();
      _parallelPreviewTimer = null;
      _sequentialPreviewElapsed = Duration.zero;
      _sequentialPreviewStartedAt = _isPreviewPlaying ? DateTime.now() : null;
      if (_isPreviewPlaying) {
        _startSequentialPreviewTicker();
      }
    }

    if (mode != PlayMode.sequential) {
      _parallelPreviewElapsed = Duration.zero;
      _parallelPreviewStartedAt = _isPreviewPlaying ? DateTime.now() : null;
      _parallelPreviewTimer?.cancel();
      _parallelPreviewTimer = null;
      if (_isPreviewPlaying) {
        _startParallelPreviewTicker();
      }
      _sequentialPreviewElapsed = Duration.zero;
      _sequentialPreviewStartedAt = null;
      _sequentialPreviewTimer?.cancel();
      _sequentialPreviewTimer = null;
    }

    await _syncPreviewPlaybackMode();
  }

  void _applyAspectPreset(AspectRatioPreset preset) {
    final size = _sizeFromPreset(preset, _effectiveResolutionForSizing);
    _setStateAndSave(() {
      _selectedAspect = preset;
      _setAppliedResolution(width: size.$1, height: size.$2);
    });
  }

  void _autoLayout({_AutoLayoutMode mode = _AutoLayoutMode.automatic}) {
    if (_clips.isEmpty) {
      return;
    }

    final consideredClips = _clips
        .take(_maxGridCapacity)
        .toList(growable: false);
    final clipAspects = consideredClips
        .map(_clipAspectRatio)
        .where((aspect) => aspect > 0)
        .toList(growable: false);
    if (clipAspects.isEmpty) {
      return;
    }

    final clipCount = consideredClips.length;
    final dominantOrientation = _dominantOrientation(clipAspects);
    _AutoLayoutChoice? bestChoice;

    final rowEnd = mode == _AutoLayoutMode.horizontalStrip
        ? 1
        : _maxGridDimension;
    final columnEnd = mode == _AutoLayoutMode.verticalStack
        ? 1
        : _maxGridDimension;

    for (var rows = 1; rows <= rowEnd; rows++) {
      for (var columns = 1; columns <= columnEnd; columns++) {
        final capacity = rows * columns;
        if (capacity < clipCount) {
          continue;
        }
        for (final aspectPreset in _aspectPresets) {
          final choice = _evaluateAutoLayoutChoice(
            rows: rows,
            columns: columns,
            aspectPreset: aspectPreset,
            clipAspects: clipAspects,
            dominantOrientation: dominantOrientation,
            clipCount: clipCount,
          );
          final currentBest = bestChoice;
          if (currentBest == null || choice.isBetterThan(currentBest)) {
            bestChoice = choice;
          }
        }
      }
    }

    if (bestChoice == null) {
      final modeName = switch (mode) {
        _AutoLayoutMode.automatic => 'Auto Layout',
        _AutoLayoutMode.verticalStack => 'Vertical Auto',
        _AutoLayoutMode.horizontalStrip => 'Horizontal Auto',
      };
      _updateState(() {
        _statusMessage =
            '$modeName supports up to $_maxGridDimension media items.';
      });
      return;
    }

    final resolvedChoice = bestChoice;
    final size = _sizeFromPreset(
      resolvedChoice.aspectPreset,
      _effectiveResolutionForSizing,
    );
    _setStateAndSave(() {
      _rows = resolvedChoice.rows;
      _columns = resolvedChoice.columns;
      _selectedAspect = resolvedChoice.aspectPreset;
      _setAppliedResolution(width: size.$1, height: size.$2);
      _backfillVisibleSlotsFromOverflow();
      final modeName = switch (mode) {
        _AutoLayoutMode.automatic => 'Auto layout',
        _AutoLayoutMode.verticalStack => 'Vertical Auto',
        _AutoLayoutMode.horizontalStrip => 'Horizontal Auto',
      };
      _statusMessage =
          '$modeName picked ${resolvedChoice.rows}×${resolvedChoice.columns} • ${resolvedChoice.aspectPreset.label}.';
    });
  }

  Future<void> _openVideoTrimmer(VideoClipInfo clip) async {
    if (!clip.isVideo ||
        _loadingClipIds.contains(clip.id) ||
        _clipErrors.containsKey(clip.id) ||
        clip.fullDuration <= Duration.zero) {
      return;
    }

    if (_isPreviewPlaying) {
      await _setPreviewPlayback(false);
    }
    final controller = _controllers[clip.id];
    await controller?.pause();
    if (!mounted) {
      return;
    }

    final result = await showDialog<VideoTrimResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          VideoTrimmerDialog(clip: clip, exportService: _exportService),
    );
    if (result == null || !mounted) {
      await _syncPreviewPlaybackMode();
      return;
    }

    final index = _clips.indexWhere((candidate) => candidate.id == clip.id);
    if (index < 0) {
      return;
    }
    final trimmedDuration = result.end - result.start;
    _updateState(() {
      final current = _clips[index];
      _clips[index] = current.copyWith(
        duration: trimmedDuration,
        sourceDuration: current.fullDuration,
        trimStart: result.start,
      );
      _parallelPreviewElapsed = Duration.zero;
      _parallelPreviewStartedAt = null;
      _sequentialPreviewElapsed = Duration.zero;
      _sequentialPreviewStartedAt = null;
      _activeSequentialClipId = null;
      _statusMessage = _clips[index].isTrimmed
          ? 'Trimmed ${current.name} to ${formatDuration(trimmedDuration)}.'
          : 'Reset trim for ${current.name}.';
    });
    await controller?.seekTo(result.start);
    await _syncPreviewPlaybackMode();
  }

  Future<void> _toggleClipActive(VideoClipInfo clip) async {
    if (_isClipVisibleInGrid(clip.id)) {
      _updateState(() {
        _slotAssignments.removeWhere((_, id) => id == clip.id);
        _slotAssignments[_nextOverflowSlot()] = clip.id;
        _statusMessage = 'Marked ${clip.name} as non-active.';
      });
      await _syncPreviewPlaybackMode();
      return;
    }

    final emptySlot = _firstEmptyVisibleSlot();
    if (emptySlot == null) {
      if (mounted) {
        _updateState(() {
          _statusMessage = 'No empty slots available.';
        });
      }
      _showToast('Grid is full.');
      return;
    }

    _updateState(() {
      _assignClipToSlot(clip.id, emptySlot);
      _statusMessage = 'Added ${clip.name} to slot ${emptySlot + 1}.';
    });
    await _syncPreviewPlaybackMode();
  }

  void _moveOrSwapPreviewSlot(int fromSlotIndex, int toSlotIndex) {
    if (fromSlotIndex == toSlotIndex) {
      return;
    }

    final sourceId = _slotAssignments[fromSlotIndex];
    if (sourceId == null) {
      return;
    }

    _updateState(() {
      final targetId = _slotAssignments[toSlotIndex];
      _slotAssignments.remove(fromSlotIndex);

      if (targetId == null) {
        _slotAssignments[toSlotIndex] = sourceId;
        _backfillVisibleSlotsFromOverflow();
        _statusMessage = 'Moved clip to slot ${toSlotIndex + 1}.';
        return;
      }

      _slotAssignments[toSlotIndex] = sourceId;
      _slotAssignments[fromSlotIndex] = targetId;
      _statusMessage =
          'Swapped slot ${fromSlotIndex + 1} with slot ${toSlotIndex + 1}.';
    });
    unawaited(_syncPreviewPlaybackMode());
  }

  Future<void> _replaceSlotsFromExternalDrop(
    int startSlotIndex,
    List<String> paths,
  ) async {
    if (!mounted || paths.isEmpty || _gridCapacity == 0) {
      return;
    }

    final assignedCount = math.min(paths.length, _gridCapacity);
    final pending = <_PendingExternalReplacement>[
      for (final (index, path) in paths.indexed)
        _pendingExternalReplacement(
          path: path,
          slotIndex: index < assignedCount
              ? (startSlotIndex + index) % _gridCapacity
              : null,
        ),
    ];

    for (final item in pending) {
      final replacedClip = item.replacedClip;
      if (replacedClip != null) {
        _controllers.remove(replacedClip.id)?.dispose();
      }
    }

    _updateState(() {
      for (final item in pending) {
        final replacedClip = item.replacedClip;
        if (replacedClip != null) {
          _removeClipState(replacedClip.id);
        }
        _queueExternalClipState(
          id: item.id,
          path: item.path,
          slotIndex: item.slotIndex,
          label: item.inheritedLabel,
        );
      }

      final candidateCount = paths.length - assignedCount;
      _statusMessage = candidateCount == 0
          ? 'Replacing $assignedCount slot(s) from slot ${startSlotIndex + 1}.'
          : 'Replacing $assignedCount slot(s) from slot ${startSlotIndex + 1}; '
                '$candidateCount kept in Media.';
    });

    for (final item in pending) {
      await _loadClip(item.path, instanceId: item.id);
    }
  }

  _PendingExternalReplacement _pendingExternalReplacement({
    required String path,
    required int? slotIndex,
  }) {
    final replacedClip = slotIndex == null ? null : _clipForSlot(slotIndex);
    final hasCustomLabel =
        replacedClip != null &&
        replacedClip.name != _defaultClipNameForPath(replacedClip.path);
    return (
      id: _newClipInstanceId(),
      path: path,
      slotIndex: slotIndex,
      replacedClip: replacedClip,
      inheritedLabel: hasCustomLabel ? replacedClip.name : null,
    );
  }

  void _queueExternalClipState({
    required String id,
    required String path,
    required int? slotIndex,
    String? label,
  }) {
    final placeholder = _placeholderClip(path, instanceId: id);
    _clips.add(label == null ? placeholder : placeholder.copyWith(name: label));
    if (slotIndex != null) {
      _replaceClipInSlot(id, slotIndex);
    }
    _loadingClipIds.add(id);
    _clipErrors.remove(id);
  }

  Future<void> _handleExternalDrop(
    List<DropItem> items, {
    required int? preferredSlotIndex,
    Offset? globalPosition,
  }) async {
    final supportedPaths = _supportedMediaDropPaths(items);
    if (supportedPaths.isEmpty) {
      return;
    }

    final slotIndex = globalPosition == null
        ? preferredSlotIndex
        : _slotIndexForGlobalDropPosition(globalPosition) ?? preferredSlotIndex;
    if (mounted && _externalDropHoverSlotIndex != null) {
      _updateState(() {
        _externalDropHoverSlotIndex = null;
      });
    }

    if (slotIndex != null || supportedPaths.length > 1) {
      await _replaceSlotsFromExternalDrop(slotIndex ?? 0, supportedPaths);
      return;
    }

    await _importExternalMedia(supportedPaths);
  }

  Future<int> _importExternalMedia(List<String> paths) async {
    final pendingClips = <({String id, String path})>[
      for (final path in paths)
        if (path.isNotEmpty) (id: _newClipInstanceId(), path: path),
    ];

    final emptyVisibleSlotCount = Iterable<int>.generate(
      _gridCapacity,
    ).where((slotIndex) => !_slotAssignments.containsKey(slotIndex)).length;

    if (!mounted) {
      return 0;
    }

    if (pendingClips.isEmpty) {
      _updateState(() {
        _statusMessage = 'No media was added.';
      });
      return 0;
    }

    _updateState(() {
      for (final pending in pendingClips) {
        _queueExternalClipState(
          id: pending.id,
          path: pending.path,
          slotIndex: _nextAvailableSlot(),
        );
      }
      final assignedVisibleCount = math.min(
        pendingClips.length,
        emptyVisibleSlotCount,
      );
      _statusMessage = assignedVisibleCount == pendingClips.length
          ? 'Queued ${pendingClips.length} media item(s) into empty slots.'
          : 'Queued ${pendingClips.length} media item(s). '
                '$assignedVisibleCount assigned to empty slot(s), '
                '${pendingClips.length - assignedVisibleCount} kept in Media.';
    });

    for (final pending in pendingClips) {
      await _loadClip(pending.path, instanceId: pending.id);
    }
    return pendingClips.length;
  }

  List<String> _supportedMediaDropPaths(List<DropItem> items) {
    final paths = <String>[];
    for (final item in items) {
      if (item is DropItemDirectory) {
        continue;
      }
      if (_isSupportedMediaPath(item.path)) {
        paths.add(item.path);
      }
    }
    return paths;
  }

  bool _isSupportedVideoPath(String path) {
    return _supportedVideoExtensions.contains(p.extension(path).toLowerCase());
  }

  bool _isSupportedPhotoPath(String path) {
    return _supportedPhotoExtensions.contains(p.extension(path).toLowerCase());
  }

  bool _isSupportedMediaPath(String path) {
    return _isSupportedVideoPath(path) || _isSupportedPhotoPath(path);
  }

  Future<void> _pickMediaForSlot(int slotIndex) async {
    final path = await _dialogService.pickSingleMedia();
    if (path == null || path.isEmpty) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'No media was selected.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    final instanceId = _newClipInstanceId();
    _updateState(() {
      _clips.add(_placeholderClip(path, instanceId: instanceId));
      _assignClipToSlot(instanceId, slotIndex);
      _loadingClipIds.add(instanceId);
      _clipErrors.remove(instanceId);
      _statusMessage = 'Queued 1 media item for slot ${slotIndex + 1}.';
    });

    unawaited(_loadClip(path, instanceId: instanceId));
  }

  Future<void> _setPreviewPlayback(bool shouldPlay) async {
    final parallelPausePosition = !shouldPlay && !_isSequentialPlayMode
        ? _currentParallelPreviewElapsed()
        : null;
    final sequentialPausePosition = !shouldPlay && _isSequentialPlayMode
        ? _currentSequentialPreviewElapsed()
        : null;

    _updateState(() {
      if (parallelPausePosition != null) {
        _parallelPreviewElapsed = parallelPausePosition;
        _parallelPreviewStartedAt = null;
      }
      if (sequentialPausePosition != null) {
        _sequentialPreviewElapsed = sequentialPausePosition;
        _sequentialPreviewStartedAt = null;
      }
      _isPreviewPlaying = shouldPlay;
      _statusMessage = shouldPlay
          ? 'Preview playback started.'
          : 'Preview playback paused.';
    });
    if (!shouldPlay) {
      _lastPreviewProgressSecond = null;
    }

    if (!_isSequentialPlayMode) {
      if (!shouldPlay) {
        _parallelPreviewTimer?.cancel();
        _parallelPreviewTimer = null;
        await _syncParallelPreviewControllers();
        return;
      }

      final totalDuration = exportDurationForClips(
        _slotClipsForExport(),
        _selectedDurationMode,
        PlayMode.parallel,
      );
      if (_parallelPreviewElapsed >= totalDuration) {
        _parallelPreviewElapsed = Duration.zero;
      }
      _parallelPreviewStartedAt = DateTime.now();
      _lastPreviewProgressSecond = null;
      _startParallelPreviewTicker();
      await _syncParallelPreviewControllers();
      return;
    }

    if (!shouldPlay) {
      _sequentialPreviewTimer?.cancel();
      _sequentialPreviewTimer = null;
      await _syncSequentialPreviewControllers();
      return;
    }

    final totalDuration = exportDurationForClips(
      _slotClipsForExport(),
      _selectedDurationMode,
      PlayMode.sequential,
    );
    if (_sequentialPreviewElapsed >= totalDuration) {
      _sequentialPreviewElapsed = Duration.zero;
    }
    _sequentialPreviewStartedAt = DateTime.now();
    _lastPreviewProgressSecond = null;
    _startSequentialPreviewTicker();
    await _syncSequentialPreviewControllers();
  }

  Future<void> _stopPreviewPlayback() async {
    _updateState(() {
      _isPreviewPlaying = false;
      _statusMessage = 'Preview playback stopped.';
    });

    _lastPreviewProgressSecond = null;
    _parallelPreviewTimer?.cancel();
    _parallelPreviewTimer = null;
    _parallelPreviewStartedAt = null;
    _parallelPreviewElapsed = Duration.zero;
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = null;
    _sequentialPreviewStartedAt = null;
    _sequentialPreviewElapsed = Duration.zero;
    _activeSequentialClipId = null;

    await _syncPreviewPlaybackMode();
  }

  Future<void> _togglePreviewMute() async {
    _updateState(() {
      _isPreviewMuted = !_isPreviewMuted;
      _statusMessage = _isPreviewMuted ? 'Preview muted.' : 'Preview unmuted.';
    });
    await _syncPreviewPlaybackMode();
  }

  Future<void> _syncPreviewPlaybackMode() async {
    if (!_isSequentialPlayMode) {
      await _syncParallelPreviewControllers();
      return;
    }
    await _syncSequentialPreviewControllers();
  }

  int _ensureEven(int value) {
    if (value <= 0) {
      return 2;
    }
    return value.isEven ? value : value + 1;
  }

  String _newClipInstanceId() => 'clip-${_nextClipInstanceNumber++}';

  VideoClipInfo _placeholderClip(String path, {String? instanceId}) {
    return VideoClipInfo(
      instanceId: instanceId ?? _newClipInstanceId(),
      path: path,
      name: _defaultClipNameForPath(path),
      duration: Duration.zero,
      width: 0,
      height: 0,
      hasAudio: false,
      mediaKind: _isSupportedPhotoPath(path)
          ? MediaKind.photo
          : MediaKind.video,
    );
  }

  Future<void> _loadClip(
    String path, {
    required String instanceId,
    VideoClipInfo? initialClip,
  }) async {
    if (_isSupportedPhotoPath(path)) {
      try {
        final clip = await _exportService.probeMedia(path);
        if (!mounted) {
          return;
        }

        _controllers.remove(instanceId)?.dispose();
        _updateState(() {
          _loadingClipIds.remove(instanceId);
          _clipErrors.remove(instanceId);
          final index = _clips.indexWhere((clip) => clip.id == instanceId);
          if (index >= 0) {
            _clips[index] = clip.copyWith(
              instanceId: instanceId,
              name: _clips[index].name,
            );
            _statusMessage = 'Loaded ${_clips[index].name}.';
          }
        });
        unawaited(_syncPreviewPlaybackMode());
        unawaited(_refreshClipAiMetadata(instanceId, path));
      } catch (error) {
        if (!mounted) {
          return;
        }
        _updateState(() {
          _loadingClipIds.remove(instanceId);
          _clipErrors[instanceId] = _previewErrorSummary(error);
          _statusMessage =
              'Preview failed for ${path.split(Platform.pathSeparator).last}.';
        });
      }
      return;
    }

    VideoPlayerController? controller;
    var probedClip = initialClip;
    try {
      if (probedClip == null) {
        try {
          probedClip = await _exportService.probeMedia(path);
          if (mounted) {
            _updateState(() {
              final index = _clips.indexWhere((clip) => clip.id == instanceId);
              if (index >= 0) {
                _clips[index] = probedClip!.copyWith(
                  instanceId: instanceId,
                  name: _clips[index].name,
                );
              }
            });
          }
        } catch (_) {}
      }

      controller = VideoPlayerController.file(File(path));
      await controller.initialize().timeout(_previewInitializationTimeout);
      await controller.setLooping(false);
      await controller.setVolume(0);
      await controller.pause();

      final initializedController = controller;
      final clip =
          probedClip ??
          (() {
            final value = initializedController.value;
            return VideoClipInfo(
              path: path,
              name: _defaultClipNameForPath(path),
              duration: value.duration,
              width: value.size.width.round(),
              height: value.size.height.round(),
              hasAudio: false,
              mediaKind: MediaKind.video,
            );
          })();

      if (!mounted) {
        controller.dispose();
        return;
      }
      if (!_clips.any((clip) => clip.id == instanceId)) {
        controller.dispose();
        return;
      }

      final previousController = _controllers[instanceId];
      _updateState(() {
        _controllers[instanceId] = initializedController;
        _loadingClipIds.remove(instanceId);
        _clipErrors.remove(instanceId);
        final index = _clips.indexWhere((clip) => clip.id == instanceId);
        if (index >= 0) {
          _clips[index] = clip.copyWith(
            instanceId: instanceId,
            name: _clips[index].name,
          );
          _statusMessage = 'Loaded ${_clips[index].name}.';
        }
      });
      if (!identical(previousController, controller)) {
        previousController?.dispose();
      }
      unawaited(_syncPreviewPlaybackMode());
      unawaited(_refreshClipAiMetadata(instanceId, path));
      controller = null;
    } catch (error) {
      controller?.dispose();
      if (!mounted) {
        return;
      }

      _updateState(() {
        _loadingClipIds.remove(instanceId);
        if (probedClip == null) {
          _clipErrors[instanceId] = _previewErrorSummary(error);
          _statusMessage =
              'Preview failed for ${path.split(Platform.pathSeparator).last}.';
          return;
        }
        _clipErrors.remove(instanceId);
        _statusMessage =
            'Loaded metadata for ${probedClip.name}, but preview failed.';
      });
      if (probedClip != null) {
        unawaited(_refreshClipAiMetadata(instanceId, path));
      }
    }
  }

  Future<void> _refreshClipAiMetadata(String instanceId, String path) async {
    try {
      final metadata = await _exportService.probeAiMetadata(path);
      if (!mounted) {
        return;
      }
      _updateState(() {
        final index = _clips.indexWhere(
          (clip) => clip.id == instanceId && clip.path == path,
        );
        if (index >= 0) {
          _clips[index] = _clips[index].copyWith(aiMetadata: metadata);
        }
      });
    } catch (_) {
      // Basic media information and preview remain available if C2PA fails.
    }
  }

  Future<void> _refreshClipMetadata(String instanceId) async {
    if (_loadingClipIds.contains(instanceId)) {
      return;
    }

    final existingIndex = _clips.indexWhere((clip) => clip.id == instanceId);
    if (existingIndex < 0) {
      return;
    }
    final path = _clips[existingIndex].path;

    try {
      final refreshed = await _exportService.probeMediaWithAiMetadata(path);
      if (!mounted) {
        return;
      }

      _updateState(() {
        final currentIndex = _clips.indexWhere((clip) => clip.id == instanceId);
        if (currentIndex < 0) {
          return;
        }
        final current = _clips[currentIndex];
        if (!current.isTrimmed) {
          _clips[currentIndex] = refreshed.copyWith(
            instanceId: instanceId,
            name: current.name,
          );
          return;
        }
        final sourceDuration = refreshed.duration;
        final trimStart = current.trimStart < sourceDuration
            ? current.trimStart
            : Duration.zero;
        final requestedEnd = current.trimEnd < sourceDuration
            ? current.trimEnd
            : sourceDuration;
        final trimmedDuration = requestedEnd > trimStart
            ? requestedEnd - trimStart
            : sourceDuration;
        _clips[currentIndex] = refreshed.copyWith(
          instanceId: instanceId,
          name: current.name,
          duration: trimmedDuration,
          sourceDuration: sourceDuration,
          trimStart: trimStart,
        );
      });
    } catch (_) {
      // Keep the existing metadata if refresh fails.
    }
  }

  Future<void> _editClipTitle(VideoClipInfo clip) async {
    final visibleSlotClips = _slotClipsForExport();
    final showTwoClipPresets =
        visibleSlotClips.length == 2 &&
        visibleSlotClips.any((entry) => entry.clip.id == clip.id);

    final result = await showDialog<_ClipLabelEditResult>(
      context: context,
      builder: (dialogContext) {
        return _ClipLabelEditDialog(
          clip: clip,
          initialLabel: clip.name,
          initialDisplayMode: _clipLabelDisplayMode,
          showTwoClipPresets: showTwoClipPresets,
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final selectedPreset = result.preset;
    final displayModeChanged = result.displayMode != _clipLabelDisplayMode;
    if (selectedPreset != null) {
      final latestVisibleSlotClips = _slotClipsForExport();
      if (latestVisibleSlotClips.length != 2) {
        if (displayModeChanged) {
          _setStateAndSave(() {
            _clipLabelDisplayMode = result.displayMode;
            _statusMessage =
                'Updated label display to ${result.displayMode.label}.';
          });
        }
        return;
      }

      _setStateAndSave(() {
        _clipLabelDisplayMode = result.displayMode;
        final presetLabels = <String>[
          selectedPreset.firstLabel,
          selectedPreset.secondLabel,
        ];
        for (var index = 0; index < latestVisibleSlotClips.length; index += 1) {
          final clipId = latestVisibleSlotClips[index].clip.id;
          final clipIndex = _clips.indexWhere((entry) => entry.id == clipId);
          if (clipIndex >= 0) {
            _clips[clipIndex] = _clips[clipIndex].copyWith(
              name: presetLabels[index],
            );
          }
        }
        final presetMessage =
            'Applied clip label preset: ${selectedPreset.firstLabel} / ${selectedPreset.secondLabel}.';
        _statusMessage = displayModeChanged
            ? '$presetMessage Display: ${result.displayMode.label}.'
            : presetMessage;
      });
      return;
    }

    final updatedName = result.name;
    if (updatedName == null) {
      return;
    }

    if (updatedName == clip.name && !displayModeChanged) {
      return;
    }

    _setStateAndSave(() {
      _clipLabelDisplayMode = result.displayMode;
      final index = _clips.indexWhere((entry) => entry.id == clip.id);
      final updateMessage = updatedName == clip.name
          ? null
          : 'Updated clip label to $updatedName.';
      final displayMessage = displayModeChanged
          ? 'Label display: ${result.displayMode.label}.'
          : null;
      if (index >= 0) {
        _clips[index] = _clips[index].copyWith(name: updatedName);
      }
      _statusMessage = [?updateMessage, ?displayMessage].join(' ');
    });
  }
}
