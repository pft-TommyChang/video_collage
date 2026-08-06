part of '../video_collage_app.dart';

extension _PreviewController on _VideoCollageScreenState {
  Duration _currentSequentialPreviewElapsed() {
    final startedAt = _sequentialPreviewStartedAt;
    if (!_isPreviewPlaying || startedAt == null) {
      return _sequentialPreviewElapsed;
    }
    return _sequentialPreviewElapsed + DateTime.now().difference(startedAt);
  }

  Duration _currentParallelPreviewElapsed() {
    final startedAt = _parallelPreviewStartedAt;
    if (!_isPreviewPlaying || startedAt == null) {
      return _parallelPreviewElapsed;
    }
    return _parallelPreviewElapsed + DateTime.now().difference(startedAt);
  }

  Duration _currentPreviewDisplayElapsed(Duration totalDuration) {
    if (totalDuration <= Duration.zero) {
      return Duration.zero;
    }
    final elapsed = _isSequentialPlayMode
        ? _currentSequentialPreviewElapsed()
        : _currentParallelPreviewElapsed();
    if (elapsed <= Duration.zero) {
      return Duration.zero;
    }
    if (elapsed >= totalDuration) {
      return totalDuration;
    }
    return elapsed;
  }

  void _refreshPreviewProgress(Duration elapsed) {
    if (!mounted || !_isPreviewPlaying) {
      return;
    }
    final elapsedSecond = elapsed.inSeconds;
    if (_lastPreviewProgressSecond == elapsedSecond) {
      return;
    }
    _lastPreviewProgressSecond = elapsedSecond;
    _updateState(() {});
  }

  Duration _lastFramePosition(VideoClipInfo clip) {
    final durationMs = clip.duration.inMilliseconds;
    if (durationMs <= 34) {
      return clip.trimStart;
    }
    return clip.trimStart + Duration(milliseconds: durationMs - 34);
  }

  Future<void> _seekControllerIfNeeded(
    VideoPlayerController controller,
    Duration target,
  ) async {
    final current = controller.value.position;
    if ((current - target).abs() < const Duration(milliseconds: 80)) {
      return;
    }
    await controller.seekTo(target);
  }

  Future<void> _setControllerLooping(
    VideoPlayerController controller,
    bool looping,
  ) async {
    if (controller.value.isLooping == looping) {
      return;
    }
    await controller.setLooping(looping);
  }

  Future<void> _setControllerVolume(
    VideoPlayerController controller,
    double volume,
  ) async {
    if ((controller.value.volume - volume).abs() < 0.001) {
      return;
    }
    await controller.setVolume(volume);
  }

  Future<void> _pauseController(VideoPlayerController controller) async {
    if (!controller.value.isPlaying) {
      return;
    }
    await controller.pause();
  }

  Future<void> _playControllerAt(
    VideoPlayerController controller,
    Duration target,
  ) async {
    // Let the native player decode continuously once playback has started.
    // Repeated seekTo calls flush its decoder and are especially expensive when
    // several preview tiles are visible at the same time.
    if (controller.value.isPlaying || controller.value.isBuffering) {
      return;
    }
    await _seekControllerIfNeeded(controller, target);
    await controller.play();
  }

  Future<void> _syncParallelPreviewControllers() async {
    if (_isSyncingParallelPreview || !mounted) {
      return;
    }
    _isSyncingParallelPreview = true;
    try {
      _sequentialPreviewTimer?.cancel();
      _sequentialPreviewTimer = null;
      _sequentialPreviewStartedAt = null;
      _sequentialPreviewElapsed = Duration.zero;
      if (_activeSequentialClipId != null && mounted) {
        _updateState(() {
          _activeSequentialClipId = null;
        });
      }

      final visibleSlotClips = _slotClipsForExport();
      final audibleClipIds = _previewAudibleClipIds(visibleSlotClips);
      final parallelClips = visibleSlotClips
          .where(
            (entry) =>
                entry.clip.isVideo && entry.clip.duration > Duration.zero,
          )
          .toList(growable: false);
      final visibleVideoIds = parallelClips
          .map((entry) => entry.clip.id)
          .toSet();

      if (parallelClips.isEmpty) {
        _parallelPreviewTimer?.cancel();
        _parallelPreviewTimer = null;
        _parallelPreviewStartedAt = null;
        _parallelPreviewElapsed = Duration.zero;
        if (_isPreviewPlaying && mounted) {
          _updateState(() {
            _isPreviewPlaying = false;
          });
        }
        await _pauseInactivePreviewControllers(const <String>{});
        return;
      }

      await _pauseInactivePreviewControllers(visibleVideoIds);

      final totalDuration = exportDurationForClips(
        parallelClips,
        _selectedDurationMode,
        PlayMode.parallel,
      );
      final elapsed = _currentParallelPreviewElapsed();
      _refreshPreviewProgress(elapsed);
      if (elapsed >= totalDuration) {
        _parallelPreviewTimer?.cancel();
        _parallelPreviewTimer = null;
        _parallelPreviewStartedAt = null;
        _parallelPreviewElapsed = totalDuration;
        _lastPreviewProgressSecond = null;
        if (mounted) {
          _updateState(() {
            _isPreviewPlaying = false;
            _statusMessage = 'Preview playback finished.';
          });
        }

        for (final entry in parallelClips) {
          final controller = _controllers[entry.clip.id];
          if (controller == null || !controller.value.isInitialized) {
            continue;
          }
          await _setControllerLooping(controller, false);
          await _setControllerVolume(controller, 0);
          await _pauseController(controller);
          final target = totalDuration >= entry.clip.duration
              ? _lastFramePosition(entry.clip)
              : entry.clip.trimStart + totalDuration;
          await _seekControllerIfNeeded(controller, target);
        }
        return;
      }

      for (final entry in parallelClips) {
        final controller = _controllers[entry.clip.id];
        if (controller == null || !controller.value.isInitialized) {
          continue;
        }
        final clip = entry.clip;
        final isClipFinished = elapsed >= clip.duration;
        final target = isClipFinished
            ? _lastFramePosition(clip)
            : clip.trimStart + elapsed;

        await _setControllerLooping(controller, false);
        await _setControllerVolume(
          controller,
          _previewVolumeForClip(
            clipId: clip.id,
            audibleClipIds: audibleClipIds,
          ),
        );
        if (_isPreviewPlaying && !isClipFinished) {
          await _playControllerAt(controller, target);
        } else {
          await _pauseController(controller);
          await _seekControllerIfNeeded(controller, target);
        }
      }
    } finally {
      _isSyncingParallelPreview = false;
    }
  }

  Future<void> _syncSequentialPreviewControllers() async {
    if (_isSyncingSequentialPreview || !mounted) {
      return;
    }
    _isSyncingSequentialPreview = true;
    try {
      final segments = _sequentialVideoSlotClips();
      final visibleVideoIds = segments.map((entry) => entry.clip.id).toSet();
      if (segments.isEmpty) {
        _sequentialPreviewTimer?.cancel();
        _sequentialPreviewTimer = null;
        _sequentialPreviewStartedAt = null;
        _sequentialPreviewElapsed = Duration.zero;
        if (_activeSequentialClipId != null || _isPreviewPlaying) {
          _updateState(() {
            _activeSequentialClipId = null;
            _isPreviewPlaying = false;
          });
        }
        for (final controller in _controllers.values) {
          if (!controller.value.isInitialized) {
            continue;
          }
          await _setControllerVolume(controller, 0);
          await _pauseController(controller);
        }
        return;
      }

      await _pauseInactivePreviewControllers(visibleVideoIds);

      final totalDuration = segments.fold(
        Duration.zero,
        (total, entry) => total + entry.clip.duration,
      );
      final elapsed = _currentSequentialPreviewElapsed();
      _refreshPreviewProgress(elapsed);
      if (elapsed >= totalDuration) {
        _sequentialPreviewTimer?.cancel();
        _sequentialPreviewTimer = null;
        _sequentialPreviewStartedAt = null;
        _sequentialPreviewElapsed = totalDuration;
        _lastPreviewProgressSecond = null;
        if (mounted) {
          _updateState(() {
            _activeSequentialClipId = null;
            _isPreviewPlaying = false;
            _statusMessage = 'Preview playback finished.';
          });
        }
        for (final entry in segments) {
          final controller = _controllers[entry.clip.id];
          if (controller == null || !controller.value.isInitialized) {
            continue;
          }
          await _setControllerLooping(controller, false);
          await _pauseController(controller);
          await _seekControllerIfNeeded(
            controller,
            _lastFramePosition(entry.clip),
          );
        }
        return;
      }

      var remaining = elapsed;
      var activeSegmentIndex = 0;
      while (activeSegmentIndex < segments.length &&
          remaining >= segments[activeSegmentIndex].clip.duration) {
        remaining -= segments[activeSegmentIndex].clip.duration;
        activeSegmentIndex++;
      }

      final activeEntry = segments[activeSegmentIndex];
      final activeClipId = activeEntry.clip.id;
      final activeOffset = remaining;
      final audibleClipIds = _sequentialPreviewAudibleClipIds(activeEntry.clip);
      final sequentialOrder = <String, int>{
        for (var index = 0; index < segments.length; index += 1)
          segments[index].clip.id: index,
      };

      final activeClipChanged = _activeSequentialClipId != activeClipId;
      if (activeClipChanged && mounted) {
        _updateState(() {
          _activeSequentialClipId = activeClipId;
        });
      }

      for (final clip in _slotClipsForExport()) {
        if (!clip.clip.isVideo) {
          continue;
        }
        final controller = _controllers[clip.clip.id];
        if (controller == null || !controller.value.isInitialized) {
          continue;
        }

        await _setControllerLooping(controller, false);
        await _setControllerVolume(
          controller,
          _previewVolumeForClip(
            clipId: clip.clip.id,
            audibleClipIds: audibleClipIds,
          ),
        );

        final clipOrder = sequentialOrder[clip.clip.id];
        if (clip.clip.id == activeClipId) {
          final target = clip.clip.trimStart + activeOffset;
          if (_isPreviewPlaying) {
            if (activeClipChanged) {
              await _pauseController(controller);
            }
            await _playControllerAt(controller, target);
          } else {
            await _pauseController(controller);
            await _seekControllerIfNeeded(controller, target);
          }
          continue;
        }

        await _pauseController(controller);
        if (clipOrder != null && clipOrder < activeSegmentIndex) {
          await _seekControllerIfNeeded(
            controller,
            _lastFramePosition(clip.clip),
          );
        } else {
          await _seekControllerIfNeeded(controller, clip.clip.trimStart);
        }
      }
    } finally {
      _isSyncingSequentialPreview = false;
    }
  }

  void _startSequentialPreviewTicker() {
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) {
        unawaited(_syncSequentialPreviewControllers());
      },
    );
  }

  Set<String> _previewAudibleClipIds(List<CollageSlotClip> slotClips) {
    if (_isPreviewMuted || slotClips.isEmpty) {
      return const <String>{};
    }

    switch (_selectedAudioMode) {
      case AudioMode.firstClip:
        final clip = slotClips.first.clip;
        return clip.hasAudio ? <String>{clip.id} : const <String>{};
      case AudioMode.mixAll:
        return slotClips
            .where((entry) => entry.clip.hasAudio)
            .map((entry) => entry.clip.id)
            .toSet();
      case AudioMode.longestClip:
        var longestEntry = slotClips.first;
        for (final entry in slotClips.skip(1)) {
          if (entry.clip.duration > longestEntry.clip.duration) {
            longestEntry = entry;
          }
        }
        return longestEntry.clip.hasAudio
            ? <String>{longestEntry.clip.id}
            : const <String>{};
      case AudioMode.mute:
        return const <String>{};
    }
  }

  Set<String> _sequentialPreviewAudibleClipIds(VideoClipInfo activeClip) {
    if (_isPreviewMuted ||
        _selectedAudioMode == AudioMode.mute ||
        !activeClip.hasAudio) {
      return const <String>{};
    }
    // Sequential export carries the audio of each active segment. Mirror that
    // behavior in preview instead of keeping only the first tile audible.
    return <String>{activeClip.id};
  }

  double _previewVolumeForClip({
    required String clipId,
    required Set<String> audibleClipIds,
  }) {
    if (!_isPreviewPlaying || !audibleClipIds.contains(clipId)) {
      return 0;
    }
    if (_selectedAudioMode == AudioMode.mixAll && audibleClipIds.isNotEmpty) {
      return 1 / audibleClipIds.length;
    }
    return 1;
  }

  Future<void> _pauseInactivePreviewControllers(
    Set<String> activeVisibleVideoIds,
  ) async {
    for (final entry in _controllers.entries) {
      final controller = entry.value;
      if (!controller.value.isInitialized ||
          activeVisibleVideoIds.contains(entry.key)) {
        continue;
      }
      await _setControllerVolume(controller, 0);
      await _pauseController(controller);
    }
  }

  void _startParallelPreviewTicker() {
    _parallelPreviewTimer?.cancel();
    _parallelPreviewTimer = Timer.periodic(const Duration(milliseconds: 120), (
      _,
    ) {
      unawaited(_syncParallelPreviewControllers());
    });
  }

  double _previewCellAspectRatio(ExportOptions options) {
    final border = options.scaledBorderThickness;
    final cellWidth =
        ((options.outputWidth - ((options.columns + 1) * border)) /
                options.columns)
            .clamp(1.0, double.infinity);
    final cellHeight =
        ((options.outputHeight - ((options.rows + 1) * border)) / options.rows)
            .clamp(1.0, double.infinity);
    return cellWidth / cellHeight;
  }

  int? _slotIndexForGlobalDropPosition(Offset globalPosition) {
    final previewGridContext = _previewGridKey.currentContext;
    final renderObject = previewGridContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    final gridSize = renderObject.size;
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > gridSize.width ||
        localPosition.dy > gridSize.height) {
      return null;
    }

    final spacing = _options.scaledBorderThickness;
    final cellWidth = ((gridSize.width - ((_columns - 1) * spacing)) / _columns)
        .clamp(1.0, double.infinity);
    final cellHeight = ((gridSize.height - ((_rows - 1) * spacing)) / _rows)
        .clamp(1.0, double.infinity);
    final strideX = cellWidth + spacing;
    final strideY = cellHeight + spacing;

    final column = (localPosition.dx / strideX).floor();
    final row = (localPosition.dy / strideY).floor();
    if (column < 0 || column >= _columns || row < 0 || row >= _rows) {
      return null;
    }

    final dxInCell = localPosition.dx - (column * strideX);
    final dyInCell = localPosition.dy - (row * strideY);
    if (dxInCell > cellWidth || dyInCell > cellHeight) {
      return null;
    }

    return (row * _columns) + column;
  }

  bool _isClipVisibleInGrid(String instanceId) {
    for (final entry in _slotAssignments.entries) {
      if (entry.value == instanceId && entry.key < _gridCapacity) {
        return true;
      }
    }
    return false;
  }
}
