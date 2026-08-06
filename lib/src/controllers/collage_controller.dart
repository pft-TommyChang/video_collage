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

  void _assignClipToSlot(String instanceId, int slotIndex) {
    final displacedId = _slotAssignments[slotIndex];
    _slotAssignments.removeWhere(
      (assignedSlotIndex, assignedId) =>
          assignedSlotIndex != slotIndex && assignedId == instanceId,
    );
    _slotAssignments[slotIndex] = instanceId;

    if (displacedId != null &&
        displacedId != instanceId &&
        !_slotAssignments.containsValue(displacedId)) {
      _slotAssignments[_nextAvailableSlot(reservedSlotIndex: slotIndex)] =
          displacedId;
    }
  }

  void _replaceClipInSlot(String instanceId, int slotIndex) {
    _slotAssignments.removeWhere(
      (assignedSlotIndex, assignedId) =>
          assignedSlotIndex != slotIndex && assignedId == instanceId,
    );
    _slotAssignments[slotIndex] = instanceId;
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

  void _backfillVisibleSlotsFromOverflow() {
    final emptyVisibleSlots = <int>[
      for (var slotIndex = 0; slotIndex < _gridCapacity; slotIndex += 1)
        if (!_slotAssignments.containsKey(slotIndex)) slotIndex,
    ];
    if (emptyVisibleSlots.isEmpty) {
      return;
    }

    final overflowIds = <String>[];
    final seenIds = <String>{};
    final sortedOverflowEntries =
        _slotAssignments.entries
            .where((entry) => entry.key >= _gridCapacity)
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in sortedOverflowEntries) {
      if (seenIds.add(entry.value) &&
          _clips.any((clip) => clip.id == entry.value)) {
        overflowIds.add(entry.value);
      }
    }

    final assignedIds = _slotAssignments.values.toSet();
    for (final clip in _clips) {
      if (seenIds.add(clip.id) && !assignedIds.contains(clip.id)) {
        overflowIds.add(clip.id);
      }
    }

    final fillCount = math.min(emptyVisibleSlots.length, overflowIds.length);
    for (var index = 0; index < fillCount; index += 1) {
      final id = overflowIds[index];
      _slotAssignments.removeWhere((_, assignedId) => assignedId == id);
      _slotAssignments[emptyVisibleSlots[index]] = id;
    }
  }

  double _clipAspectRatio(VideoClipInfo clip) {
    if (clip.width > 0 && clip.height > 0) {
      return clip.width / clip.height;
    }
    final controller = _controllers[clip.id];
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
    final id = _slotAssignments[slotIndex];
    if (id == null) {
      return null;
    }
    for (final clip in _clips) {
      if (clip.id == id) {
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
            viewport: _clipViewports[clip.id] ?? const ClipViewport(),
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
      _editingViewportClipId = clip.id;
      _statusMessage =
          'Adjust framing • Drag to pan • Slider to zoom • '
          'Done or click outside to exit';
    });
  }

  void _finishViewportEditing() {
    if (_editingViewportClipId == null) {
      return;
    }
    _updateState(() {
      _editingViewportClipId = null;
      _statusMessage = 'Framing updated.';
    });
  }

  void _updateClipViewport(String instanceId, ClipViewport viewport) {
    _updateState(() {
      if (viewport.isDefault) {
        _clipViewports.remove(instanceId);
      } else {
        _clipViewports[instanceId] = viewport;
      }
    });
  }

  void _resetClipViewport(String instanceId) {
    _updateState(() {
      _clipViewports.remove(instanceId);
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
