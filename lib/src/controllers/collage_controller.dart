part of '../video_collage_app.dart';

extension _CollageController on _VideoCollageScreenState {
  int _nextAvailableSlot({int? reservedSlotIndex}) {
    var candidate = 0;
    while (_slotAssignments.containsKey(candidate) ||
        candidate == reservedSlotIndex) {
      candidate++;
    }
    return candidate;
  }

  void _assignPathToSlot(String path, int slotIndex) {
    final displacedPath = _slotAssignments[slotIndex];
    _slotAssignments.removeWhere(
      (assignedSlotIndex, assignedPath) =>
          assignedSlotIndex != slotIndex && assignedPath == path,
    );
    _slotAssignments[slotIndex] = path;

    if (displacedPath != null &&
        displacedPath != path &&
        !_slotAssignments.containsValue(displacedPath)) {
      _slotAssignments[_nextAvailableSlot(reservedSlotIndex: slotIndex)] =
          displacedPath;
    }
  }

  void _replacePathInSlot(String path, int slotIndex) {
    _slotAssignments.removeWhere(
      (assignedSlotIndex, assignedPath) =>
          assignedSlotIndex != slotIndex && assignedPath == path,
    );
    _slotAssignments[slotIndex] = path;
  }

  int? _firstEmptyVisibleSlot() {
    for (var slotIndex = 0; slotIndex < _gridCapacity; slotIndex += 1) {
      if (!_slotAssignments.containsKey(slotIndex)) {
        return slotIndex;
      }
    }
    return null;
  }

  int _nextOverflowSlot() {
    var slotIndex = _gridCapacity;
    while (_slotAssignments.containsKey(slotIndex)) {
      slotIndex += 1;
    }
    return slotIndex;
  }

  void _compactSlotAssignments() {
    if (_slotAssignments.isEmpty) {
      return;
    }

    final sortedEntries = _slotAssignments.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));

    _slotAssignments
      ..clear()
      ..addEntries(
        sortedEntries.indexed.map(
          (entry) => MapEntry(entry.$1, entry.$2.value),
        ),
      );
  }

  void _backfillVisibleSlotsFromOverflow() {
    final emptyVisibleSlots = <int>[
      for (var slotIndex = 0; slotIndex < _gridCapacity; slotIndex += 1)
        if (!_slotAssignments.containsKey(slotIndex)) slotIndex,
    ];
    if (emptyVisibleSlots.isEmpty) {
      return;
    }

    final overflowPaths = <String>[];
    final seenPaths = <String>{};
    final sortedOverflowEntries =
        _slotAssignments.entries
            .where((entry) => entry.key >= _gridCapacity)
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in sortedOverflowEntries) {
      if (seenPaths.add(entry.value) &&
          _clips.any((clip) => clip.path == entry.value)) {
        overflowPaths.add(entry.value);
      }
    }

    final assignedPaths = _slotAssignments.values.toSet();
    for (final clip in _clips) {
      if (seenPaths.add(clip.path) && !assignedPaths.contains(clip.path)) {
        overflowPaths.add(clip.path);
      }
    }

    final fillCount = math.min(emptyVisibleSlots.length, overflowPaths.length);
    for (var index = 0; index < fillCount; index += 1) {
      final path = overflowPaths[index];
      _slotAssignments.removeWhere((_, assignedPath) => assignedPath == path);
      _slotAssignments[emptyVisibleSlots[index]] = path;
    }
  }

  double _clipAspectRatio(VideoClipInfo clip) {
    if (clip.width > 0 && clip.height > 0) {
      return clip.width / clip.height;
    }
    final controller = _controllers[clip.path];
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      if (size.width > 0 && size.height > 0) {
        return size.width / size.height;
      }
    }
    return 1.0;
  }

  _AutoLayoutOrientation _orientationForAspect(double aspect) {
    if (aspect < 0.9) {
      return _AutoLayoutOrientation.portrait;
    }
    if (aspect > 1.1) {
      return _AutoLayoutOrientation.landscape;
    }
    return _AutoLayoutOrientation.square;
  }

  _AutoLayoutOrientation _dominantOrientation(List<double> clipAspects) {
    var portraitCount = 0;
    var squareCount = 0;
    var landscapeCount = 0;

    for (final aspect in clipAspects) {
      switch (_orientationForAspect(aspect)) {
        case _AutoLayoutOrientation.portrait:
          portraitCount++;
          break;
        case _AutoLayoutOrientation.square:
          squareCount++;
          break;
        case _AutoLayoutOrientation.landscape:
          landscapeCount++;
          break;
      }
    }

    if (portraitCount >= squareCount && portraitCount >= landscapeCount) {
      return _AutoLayoutOrientation.portrait;
    }
    if (landscapeCount >= squareCount) {
      return _AutoLayoutOrientation.landscape;
    }
    return _AutoLayoutOrientation.square;
  }

  _AutoLayoutChoice _evaluateAutoLayoutChoice({
    required int rows,
    required int columns,
    required AspectRatioPreset aspectPreset,
    required List<double> clipAspects,
    required _AutoLayoutOrientation dominantOrientation,
    required int clipCount,
  }) {
    final tileAspect = aspectPreset.value * rows / columns;
    final visibleFraction =
        clipAspects.fold<double>(0, (total, clipAspect) {
          return total +
              math.min(tileAspect / clipAspect, clipAspect / tileAspect);
        }) /
        clipAspects.length;

    return _AutoLayoutChoice(
      rows: rows,
      columns: columns,
      aspectPreset: aspectPreset,
      emptySlots: rows * columns - clipCount,
      averageVisibleFraction: visibleFraction,
      orientationMatches:
          _orientationForAspect(tileAspect) == dominantOrientation,
    );
  }

  VideoClipInfo? _clipForSlot(int slotIndex) {
    final path = _slotAssignments[slotIndex];
    if (path == null) {
      return null;
    }
    for (final clip in _clips) {
      if (clip.path == path) {
        return clip;
      }
    }
    return null;
  }

  List<CollageSlotClip> _slotClipsForExport() {
    final entries = <CollageSlotClip>[];
    final sortedSlots = _slotAssignments.keys.toList()..sort();
    for (final slotIndex in sortedSlots) {
      if (slotIndex >= _gridCapacity) {
        continue;
      }
      final clip = _clipForSlot(slotIndex);
      if (clip != null) {
        entries.add(
          CollageSlotClip(
            slotIndex: slotIndex,
            clip: clip,
            viewport: _clipViewports[clip.path] ?? const ClipViewport(),
          ),
        );
      }
    }
    return entries;
  }

  void _startViewportEditing(VideoClipInfo clip) {
    if (_selectedFitMode != ClipFitMode.cropCenter) {
      _showToast('Switch Fit to Crop to adjust framing');
      return;
    }
    _updateState(() {
      _editingViewportClipPath = clip.path;
      _statusMessage =
          'Adjust framing • Drag to pan • Slider to zoom • '
          'Done or click outside to exit';
    });
  }

  void _finishViewportEditing() {
    if (_editingViewportClipPath == null) {
      return;
    }
    _updateState(() {
      _editingViewportClipPath = null;
      _statusMessage = 'Framing updated.';
    });
  }

  void _updateClipViewport(String path, ClipViewport viewport) {
    _updateState(() {
      if (viewport.isDefault) {
        _clipViewports.remove(path);
      } else {
        _clipViewports[path] = viewport;
      }
    });
  }

  void _resetClipViewport(String path) {
    _updateState(() {
      _clipViewports.remove(path);
      _statusMessage = 'Framing reset.';
    });
  }

  List<CollageSlotClip> _sequentialVideoSlotClips() {
    return _slotClipsForExport()
        .where(
          (entry) => entry.clip.isVideo && entry.clip.duration > Duration.zero,
        )
        .toList(growable: false);
  }
}
