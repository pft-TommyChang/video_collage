import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'services/desktop_file_service.dart';
import 'services/system_dialog_service.dart';
import 'services/video_export_service.dart';
import 'video_trimmer_dialog.dart';

const double _mergeDialogWidth = 760;
const double _mergeMaximumPreviewHeight = 400;
const double _mergeListHeight = 106;
const double _mergeThumbnailSize = 90;
const double _mergePlaybackControlsHeight = 36;
const double _mergeCompactButtonSize = 36;
const double _mergeAddButtonWidth = 44;
const double _mergeSaveButtonWidth = 160;
const double _mergeActionButtonHeight = 40;

class VideoMergeDialog extends StatefulWidget {
  const VideoMergeDialog({
    super.key,
    required this.exportService,
    required this.dialogService,
    this.initialVideos = const <VideoClipInfo>[],
    this.initialDirectory,
    this.initialFitMode = ClipFitMode.cropCenter,
    this.initialFrameRateMode = VideoMergeFrameRateMode.firstVideo,
    this.onSettingsChanged,
  });

  final VideoExportService exportService;
  final SystemDialogService dialogService;
  final List<VideoClipInfo> initialVideos;
  final String? initialDirectory;
  final ClipFitMode initialFitMode;
  final VideoMergeFrameRateMode initialFrameRateMode;
  final void Function(ClipFitMode, VideoMergeFrameRateMode)? onSettingsChanged;

  @override
  State<VideoMergeDialog> createState() => _VideoMergeDialogState();
}

class _VideoMergeDialogState extends State<VideoMergeDialog> {
  final List<VideoClipInfo> _videos = <VideoClipInfo>[];
  final Map<String, VideoPlayerController> _thumbnailControllers =
      <String, VideoPlayerController>{};
  final Map<String, double> _videoFrameRates = <String, double>{};
  bool _isAdding = false;
  bool _isMerging = false;
  bool _isDraggingOver = false;
  bool _isSequencePlaying = false;
  bool _isAdvancingPreview = false;
  bool _showMergeComplete = false;
  double _progress = 0;
  String? _message;
  String? _selectedVideoId;
  String? _lastMergedOutputPath;
  int _nextMergeInstanceNumber = 1;
  ClipFitMode _mergeFitMode = ClipFitMode.cropCenter;
  VideoMergeFrameRateMode _frameRateMode = VideoMergeFrameRateMode.firstVideo;

  Duration get _totalDuration =>
      _videos.fold(Duration.zero, (total, video) => total + video.duration);

  double? get _outputFrameRate {
    if (_videos.isEmpty) {
      return null;
    }
    if (_frameRateMode == VideoMergeFrameRateMode.firstVideo) {
      return _videoFrameRates[_videos.first.id];
    }
    final rates = _videos
        .map((video) => _videoFrameRates[video.id])
        .whereType<double>();
    return rates.isEmpty ? null : rates.reduce((a, b) => a > b ? a : b);
  }

  @override
  void initState() {
    super.initState();
    _videos.addAll(widget.initialVideos.map(_newMergeVideoInstance));
    _mergeFitMode = widget.initialFitMode;
    _frameRateMode = widget.initialFrameRateMode;
    _selectedVideoId = _videos.isEmpty ? null : _videos.first.id;
    for (final video in _videos) {
      unawaited(_initializeThumbnail(video));
      unawaited(_initializeFrameRate(video));
    }
  }

  @override
  void dispose() {
    for (final controller in _thumbnailControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstVideo = _videos.isEmpty ? null : _videos.first;
    final selectedVideo = _videoForId(_selectedVideoId);
    final selectedController = selectedVideo == null
        ? null
        : _thumbnailControllers[selectedVideo.id];
    final availableContentHeight = (MediaQuery.sizeOf(context).height - 220)
        .clamp(430.0, 520.0);
    return PopScope(
      canPop: !_isMerging,
      child: DropTarget(
        onDragEntered: (_) {
          if (!_isMerging) {
            setState(() => _isDraggingOver = true);
          }
        },
        onDragExited: (_) {
          if (_isDraggingOver) {
            setState(() => _isDraggingOver = false);
          }
        },
        onDragDone: (details) {
          if (_isMerging) {
            return;
          }
          setState(() => _isDraggingOver = false);
          unawaited(
            _addVideoPaths(
              details.files.map((file) => file.path).toList(growable: false),
            ),
          );
        },
        child: AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Row(
            children: <Widget>[
              const Icon(Icons.merge),
              const SizedBox(width: 10),
              const Text('Merge Videos'),
              const Spacer(),
              _MergeOptionCheckbox(
                label: 'Center inside',
                value: _mergeFitMode == ClipFitMode.centerInside,
                onChanged: _isMerging ? null : _setCenterInside,
              ),
              const SizedBox(width: 8),
              _MergeOptionCheckbox(
                label: 'Highest FPS',
                value: _frameRateMode == VideoMergeFrameRateMode.highest,
                onChanged: _isMerging ? null : _setHighestFrameRate,
              ),
            ],
          ),
          content: SizedBox(
            width: _mergeDialogWidth,
            height: availableContentHeight,
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 22,
                  child: firstVideo == null
                      ? Text(
                          _isDraggingOver
                              ? 'Drop videos here'
                              : 'No videos selected',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _isDraggingOver
                                    ? Theme.of(context).colorScheme.primary
                                    : const Color(0xFF697180),
                                fontWeight: _isDraggingOver
                                    ? FontWeight.w600
                                    : null,
                              ),
                        )
                      : Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Export: ${firstVideo.width}×${firstVideo.height}  •  '
                                '${_formatMergeFrameRate(_outputFrameRate, unavailable: 'FPS loading…')}  •  '
                                '${_formatMergeDuration(_totalDuration)} total',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFF747B88)),
                              ),
                            ),
                            if (selectedVideo != null) ...<Widget>[
                              const SizedBox(width: 16),
                              Text(
                                'Media: ${selectedVideo.width}×${selectedVideo.height}  •  '
                                '${_formatMergeFrameRate(_videoFrameRates[selectedVideo.id])}  •  '
                                '${_formatMergeDuration(selectedVideo.duration)}',
                                key: const ValueKey<String>(
                                  'merge-selected-media-info',
                                ),
                                maxLines: 1,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFF747B88)),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: _mergeMaximumPreviewHeight,
                      ),
                      child: selectedVideo == null
                          ? const AspectRatio(
                              aspectRatio: 16 / 9,
                              child: _EmptyMergePreview(),
                            )
                          : _MergeOutputPreview(
                              video: selectedVideo,
                              outputVideo: firstVideo!,
                              controller: selectedController,
                              fitMode: _mergeFitMode,
                              onTap: _isMerging
                                  ? null
                                  : () => unawaited(_togglePlayback()),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  key: const ValueKey<String>('merge-playback-controls'),
                  height: _mergePlaybackControlsHeight,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 40,
                        child: _MergePlayButton(
                          controller: selectedController,
                          onPressed: selectedController == null || _isMerging
                              ? null
                              : () => unawaited(_togglePlayback()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MergeSeekBar(
                          controller: selectedController,
                          video: selectedVideo,
                          elapsedBeforeVideo: _durationBeforeVideo(
                            selectedVideo,
                          ),
                          totalDuration: _totalDuration,
                          enabled: !_isMerging,
                          onSeek: (position) =>
                              unawaited(_seekPreview(position)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  key: const ValueKey<String>('merge-list-container'),
                  height: _mergeListHeight,
                  decoration: BoxDecoration(
                    color: _isDraggingOver
                        ? Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.28)
                        : const Color(0xFFF3EFE7),
                    border: Border.all(
                      color: _isDraggingOver
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFFD8D0C4),
                      width: _isDraggingOver ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: ReorderableListView.builder(
                          key: const ValueKey<String>('merge-list'),
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 7,
                          ),
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) => Material(
                            color: Colors.transparent,
                            elevation: 0,
                            child: child,
                          ),
                          itemCount: _videos.length,
                          onReorder: _isMerging ? (_, _) {} : _reorder,
                          itemBuilder: (context, index) {
                            final video = _videos[index];
                            return ReorderableDragStartListener(
                              key: ValueKey<String>(video.id),
                              index: index,
                              enabled: !_isMerging,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _MergeVideoThumbnail(
                                  index: index,
                                  video: video,
                                  controller: _thumbnailControllers[video.id],
                                  isSelected: video.id == _selectedVideoId,
                                  onTap: _isMerging
                                      ? null
                                      : () => unawaited(_selectVideo(video)),
                                  onTrim: _isMerging
                                      ? null
                                      : () => unawaited(_trimVideo(video)),
                                  onRemove: _isMerging
                                      ? null
                                      : () => _removeVideo(index),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(
                        height: 64,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Color(0xFFD8D0C4),
                        ),
                      ),
                      Padding(
                        key: const ValueKey<String>('merge-add-video-tile'),
                        padding: const EdgeInsets.fromLTRB(7, 7, 8, 7),
                        child: _MergeAddVideoButton(
                          isLoading: _isAdding,
                          onPressed: _isAdding || _isMerging
                              ? null
                              : _addVideos,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            SizedBox(
              width: _mergeDialogWidth,
              child: Row(
                children: <Widget>[
                  _MergeSaveButton(
                    onPressed: _isMerging
                        ? () => unawaited(
                            widget.exportService.cancelActiveExport(),
                          )
                        : _videos.length < 2 || _isAdding
                        ? null
                        : _merge,
                    isMerging: _isMerging,
                    showCompleted: _showMergeComplete,
                    progress: _progress,
                  ),
                  if (_lastMergedOutputPath != null) ...<Widget>[
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey<String>('merge-open-result-button'),
                      onPressed: _isMerging
                          ? null
                          : () => unawaited(_openMergeResult()),
                      tooltip: 'Open File',
                      icon: const Icon(Icons.open_in_new_rounded),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(40),
                        maximumSize: const Size.square(40),
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: _isMerging
                        ? null
                        : () =>
                              Navigator.of(context).pop(_lastMergedOutputPath),
                    child: Text(
                      _lastMergedOutputPath == null ? 'Cancel' : 'Close',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addVideos() async {
    final paths = await widget.dialogService.pickVideos();
    await _addVideoPaths(paths);
  }

  VideoClipInfo _newMergeVideoInstance(VideoClipInfo video) {
    return video.copyWith(
      instanceId: 'merge-video-${_nextMergeInstanceNumber++}',
    );
  }

  void _setCenterInside(bool isCenterInside) {
    _updateMergeSettings(
      fitMode: isCenterInside
          ? ClipFitMode.centerInside
          : ClipFitMode.cropCenter,
    );
  }

  void _setHighestFrameRate(bool useHighestFrameRate) {
    _updateMergeSettings(
      frameRateMode: useHighestFrameRate
          ? VideoMergeFrameRateMode.highest
          : VideoMergeFrameRateMode.firstVideo,
    );
  }

  void _updateMergeSettings({
    ClipFitMode? fitMode,
    VideoMergeFrameRateMode? frameRateMode,
  }) {
    setState(() {
      _mergeFitMode = fitMode ?? _mergeFitMode;
      _frameRateMode = frameRateMode ?? _frameRateMode;
      _showMergeComplete = false;
    });
    widget.onSettingsChanged?.call(_mergeFitMode, _frameRateMode);
  }

  Future<void> _openMergeResult() async {
    final outputPath = _lastMergedOutputPath;
    if (outputPath == null) {
      return;
    }
    final didOpen = await DesktopFileService.openFile(outputPath);
    if (mounted && !didOpen) {
      setState(() => _message = 'Unable to open merge result: $outputPath');
    }
  }

  Future<void> _addVideoPaths(List<String> paths) async {
    if (paths.isEmpty || !mounted || _isAdding || _isMerging) {
      return;
    }
    setState(() {
      _isAdding = true;
      _message = null;
      _showMergeComplete = false;
    });
    try {
      for (final path in paths) {
        final video = _newMergeVideoInstance(
          await widget.exportService.probeMedia(path),
        );
        if (video.isVideo && mounted) {
          setState(() {
            _videos.add(video);
            _selectedVideoId ??= video.id;
          });
          unawaited(_initializeThumbnail(video));
          unawaited(_initializeFrameRate(video));
        }
      }
    } on VideoExportException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not load video: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  Future<void> _initializeThumbnail(VideoClipInfo video) async {
    if (_thumbnailControllers.containsKey(video.id)) {
      return;
    }
    final controller = VideoPlayerController.file(File(video.path));
    _thumbnailControllers[video.id] = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1);
      await controller.pause();
      await controller.seekTo(video.trimStart);
      controller.addListener(
        () => _handlePreviewControllerChanged(video.id, controller),
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      await controller.dispose();
      if (identical(_thumbnailControllers[video.id], controller)) {
        _thumbnailControllers.remove(video.id);
      }
    }
  }

  Future<void> _initializeFrameRate(VideoClipInfo video) async {
    if (_videoFrameRates.containsKey(video.id)) {
      return;
    }
    try {
      final frameRate = await widget.exportService.probeVideoFrameRate(
        video.path,
      );
      if (mounted && frameRate > 0) {
        setState(() => _videoFrameRates[video.id] = frameRate);
      }
    } catch (_) {
      // Frame rate is supplemental display metadata; media remains usable.
    }
  }

  void _removeVideo(int index) {
    final video = _videos.removeAt(index);
    final controller = _thumbnailControllers.remove(video.id);
    _videoFrameRates.remove(video.id);
    if (_selectedVideoId == video.id) {
      _isSequencePlaying = false;
    }
    unawaited(controller?.dispose());
    setState(() {
      _showMergeComplete = false;
      if (_selectedVideoId == video.id) {
        if (_videos.isEmpty) {
          _selectedVideoId = null;
        } else {
          _selectedVideoId = _videos[index.clamp(0, _videos.length - 1)].id;
        }
      }
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex >= _videos.length) {
      return;
    }
    setState(() {
      _showMergeComplete = false;
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final video = _videos.removeAt(oldIndex);
      if (newIndex > _videos.length) {
        newIndex = _videos.length;
      }
      _videos.insert(newIndex, video);
    });
  }

  Future<void> _trimVideo(VideoClipInfo video) async {
    await _stopPreviewPlayback();
    final controller = _thumbnailControllers[video.id];
    await controller?.pause();
    if (!mounted) {
      return;
    }

    final result = await showDialog<VideoTrimResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          VideoTrimmerDialog(clip: video, exportService: widget.exportService),
    );
    if (result == null || !mounted) {
      return;
    }

    final index = _videos.indexWhere((candidate) => candidate.id == video.id);
    if (index < 0) {
      return;
    }
    final trimmedDuration = result.end - result.start;
    setState(() {
      final current = _videos[index];
      _videos[index] = current.copyWith(
        duration: trimmedDuration,
        sourceDuration: current.fullDuration,
        trimStart: result.start,
      );
      _selectedVideoId = current.id;
      _showMergeComplete = false;
      _message = null;
    });
    await controller?.seekTo(result.start);
  }

  VideoClipInfo? _videoForId(String? id) {
    if (id == null) {
      return null;
    }
    for (final video in _videos) {
      if (video.id == id) {
        return video;
      }
    }
    return null;
  }

  Duration _durationBeforeVideo(VideoClipInfo? selectedVideo) {
    if (selectedVideo == null) {
      return Duration.zero;
    }
    var elapsed = Duration.zero;
    for (final video in _videos) {
      if (video.id == selectedVideo.id) {
        break;
      }
      elapsed += video.duration;
    }
    return elapsed;
  }

  Future<void> _seekPreview(Duration sequencePosition) async {
    if (_videos.isEmpty || _isMerging) {
      return;
    }

    final targetPosition = sequencePosition < Duration.zero
        ? Duration.zero
        : sequencePosition > _totalDuration
        ? _totalDuration
        : sequencePosition;
    var elapsed = Duration.zero;
    var targetVideo = _videos.last;
    var positionInVideo = targetVideo.duration;
    for (final video in _videos) {
      final videoEnd = elapsed + video.duration;
      if (targetPosition < videoEnd || video.id == _videos.last.id) {
        targetVideo = video;
        positionInVideo = video.trimStart + (targetPosition - elapsed);
        break;
      }
      elapsed = videoEnd;
    }

    final wasPlaying = _isSequencePlaying;
    final current = _thumbnailControllers[_selectedVideoId];
    final target = _thumbnailControllers[targetVideo.id];
    if (current != null &&
        !identical(current, target) &&
        current.value.isPlaying) {
      await current.pause();
    }
    if (!mounted) {
      return;
    }
    if (_selectedVideoId != targetVideo.id) {
      setState(() => _selectedVideoId = targetVideo.id);
    }
    if (target == null || !target.value.isInitialized) {
      return;
    }
    await target.seekTo(positionInVideo);
    if (wasPlaying && positionInVideo < targetVideo.trimEnd) {
      await target.setVolume(1);
      await target.play();
    }
  }

  Future<void> _selectVideo(VideoClipInfo video) async {
    if (_selectedVideoId == video.id) {
      return;
    }
    final current = _thumbnailControllers[_selectedVideoId];
    if (current?.value.isPlaying == true) {
      await current?.pause();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedVideoId = video.id;
      _isSequencePlaying = false;
    });
    final next = _thumbnailControllers[video.id];
    if (next?.value.isInitialized == true) {
      await next?.seekTo(video.trimStart);
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _thumbnailControllers[_selectedVideoId];
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) {
        setState(() => _isSequencePlaying = false);
      }
      return;
    }
    final selectedVideo = _videoForId(_selectedVideoId);
    if (selectedVideo == null) {
      return;
    }
    if (controller.value.isCompleted ||
        controller.value.position < selectedVideo.trimStart ||
        controller.value.position >= selectedVideo.trimEnd) {
      await controller.seekTo(selectedVideo.trimStart);
    }
    await controller.setVolume(1);
    if (mounted) {
      setState(() => _isSequencePlaying = true);
    }
    await controller.play();
  }

  void _handlePreviewControllerChanged(
    String id,
    VideoPlayerController controller,
  ) {
    if (!mounted ||
        !_isSequencePlaying ||
        _isAdvancingPreview ||
        _selectedVideoId != id ||
        !identical(_thumbnailControllers[id], controller)) {
      return;
    }
    final value = controller.value;
    if (!value.isInitialized ||
        (!value.isCompleted &&
            value.position < (_videoForId(id)?.trimEnd ?? value.duration))) {
      return;
    }
    _isAdvancingPreview = true;
    unawaited(_advancePreviewFrom(id));
  }

  Future<void> _advancePreviewFrom(String id) async {
    try {
      final currentIndex = _videos.indexWhere((video) => video.id == id);
      if (currentIndex < 0) {
        if (mounted) {
          setState(() => _isSequencePlaying = false);
        }
        return;
      }

      final current = _thumbnailControllers[id];
      if (current?.value.isPlaying == true) {
        await current?.pause();
      }
      if (currentIndex >= _videos.length - 1) {
        final currentVideo = _videos[currentIndex];
        if (current?.value.isInitialized == true &&
            current!.value.position != currentVideo.trimEnd) {
          await current.seekTo(currentVideo.trimEnd);
        }
        if (mounted) {
          setState(() => _isSequencePlaying = false);
        }
        return;
      }

      final nextVideo = _videos[currentIndex + 1];
      final next = _thumbnailControllers[nextVideo.id];
      if (next == null || !next.value.isInitialized || !mounted) {
        if (mounted) {
          setState(() => _isSequencePlaying = false);
        }
        return;
      }

      setState(() => _selectedVideoId = nextVideo.id);
      await next.setLooping(false);
      await next.setVolume(1);
      await next.seekTo(nextVideo.trimStart);
      await next.play();
    } catch (_) {
      if (mounted) {
        setState(() => _isSequencePlaying = false);
      }
    } finally {
      _isAdvancingPreview = false;
    }
  }

  Future<void> _stopPreviewPlayback() async {
    _isSequencePlaying = false;
    for (final controller in _thumbnailControllers.values) {
      if (controller.value.isPlaying) {
        await controller.pause();
      }
    }
  }

  Future<void> _merge() async {
    await _stopPreviewPlayback();
    final outputPath = await widget.dialogService.pickSavePath(
      format: ExportFormat.mp4,
      suggestedName:
          '${p.basenameWithoutExtension(_videos.first.path)}_merged.mp4',
      initialDirectory: widget.initialDirectory,
    );
    if (outputPath == null || outputPath.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _isMerging = true;
      _showMergeComplete = false;
      _progress = 0;
      _message = null;
    });
    var completed = false;
    try {
      await widget.exportService.mergeVideos(
        videos: List<VideoClipInfo>.of(_videos),
        outputPath: outputPath,
        fitMode: _mergeFitMode,
        frameRateMode: _frameRateMode,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress.progress);
          }
        },
      );
      if (mounted) {
        completed = true;
        setState(() {
          _isMerging = false;
          _showMergeComplete = true;
          _progress = 1;
          _lastMergedOutputPath = outputPath;
        });
      }
    } on VideoExportException catch (error) {
      if (mounted) {
        setState(
          () => _message = _isMergeCancellation(error) ? null : error.message,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _isMergeCancellation(error)
              ? null
              : 'Merge failed: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMerging = false;
          if (!_showMergeComplete) {
            _progress = 0;
          }
        });
      }
      if (!completed && File(outputPath).existsSync()) {
        await File(outputPath).delete();
      }
    }
  }

  bool _isMergeCancellation(Object error) {
    final message = error is VideoExportException
        ? error.message
        : error.toString();
    return message.toLowerCase().contains('cancel');
  }
}

class _MergeVideoThumbnail extends StatelessWidget {
  const _MergeVideoThumbnail({
    required this.index,
    required this.video,
    required this.controller,
    required this.isSelected,
    required this.onTap,
    required this.onTrim,
    required this.onRemove,
  });

  final int index;
  final VideoClipInfo video;
  final VideoPlayerController? controller;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onTrim;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isReady = controller?.value.isInitialized == true;
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.grab,
      child: Listener(
        key: ValueKey<String>('merge-thumbnail-tap-${video.id}'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: onTap == null ? null : (_) => onTap!(),
        child: AnimatedContainer(
          key: ValueKey<String>('merge-thumbnail-${video.id}'),
          duration: const Duration(milliseconds: 140),
          width: _mergeThumbnailSize,
          height: _mergeThumbnailSize,
          decoration: BoxDecoration(
            color: const Color(0xFF20242C),
            borderRadius: BorderRadius.circular(9),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFFF7A59)
                  : const Color(0xFFE7DED1),
              width: isSelected ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              isReady
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller!.value.size.width,
                        height: controller!.value.size.height,
                        child: VideoPlayer(controller!),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: Color(0xFFB8C0CC),
                      ),
                    ),
              Positioned(
                left: 5,
                top: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 3,
                top: 3,
                child: IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove ${p.basename(video.path)}',
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 16,
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xBB000000),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(24),
                    maximumSize: const Size.square(24),
                  ),
                ),
              ),
              Positioned(
                left: 3,
                bottom: 3,
                child: IconButton(
                  key: ValueKey<String>('merge-trim-${video.id}'),
                  onPressed: onTrim,
                  tooltip: 'Trim ${p.basename(video.path)}',
                  icon: Icon(
                    Icons.content_cut_rounded,
                    size: 15,
                    color: video.isTrimmed
                        ? const Color(0xFFFFC107)
                        : Colors.white,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xBB000000),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(24),
                    maximumSize: const Size.square(24),
                  ),
                ),
              ),
              Positioned(
                right: 5,
                bottom: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      _formatMergeDuration(video.duration),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MergeOutputPreview extends StatelessWidget {
  const _MergeOutputPreview({
    required this.video,
    required this.outputVideo,
    required this.controller,
    required this.fitMode,
    required this.onTap,
  });

  final VideoClipInfo video;
  final VideoClipInfo outputVideo;
  final VideoPlayerController? controller;
  final ClipFitMode fitMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outputAspect = outputVideo.width > 0 && outputVideo.height > 0
        ? outputVideo.width / outputVideo.height
        : 16 / 9;
    final isReady = controller?.value.isInitialized == true;

    return AspectRatio(
      key: const ValueKey<String>('merge-output-preview'),
      aspectRatio: outputAspect,
      child: MouseRegion(
        key: ValueKey<String>('merge-preview-${video.id}'),
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            key: const ValueKey<String>('merge-output-frame'),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: isReady
                ? FittedBox(
                    fit: fitMode.previewFit,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: controller!.value.size.width,
                      height: controller!.value.size.height,
                      child: VideoPlayer(controller!),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.movie_outlined,
                      size: 44,
                      color: Color(0xFFB8C0CC),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMergePreview extends StatelessWidget {
  const _EmptyMergePreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.video_library_outlined,
              size: 44,
              color: Color(0xFFB8C0CC),
            ),
            SizedBox(height: 10),
            Text(
              'No video to preview',
              style: TextStyle(color: Color(0xFFB8C0CC)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MergeSeekBar extends StatelessWidget {
  const _MergeSeekBar({
    required this.controller,
    required this.video,
    required this.elapsedBeforeVideo,
    required this.totalDuration,
    required this.enabled,
    required this.onSeek,
  });

  final VideoPlayerController? controller;
  final VideoClipInfo? video;
  final Duration elapsedBeforeVideo;
  final Duration totalDuration;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return _buildContents(context, const VideoPlayerValue.uninitialized());
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => _buildContents(context, value),
    );
  }

  Widget _buildContents(BuildContext context, VideoPlayerValue value) {
    final primary = Theme.of(context).colorScheme.primary;
    final totalMilliseconds = totalDuration.inMilliseconds;
    final rawPosition =
        elapsedBeforeVideo +
        (value.isInitialized && video != null
            ? value.position - video!.trimStart
            : Duration.zero);
    final currentPosition = rawPosition > totalDuration
        ? totalDuration
        : rawPosition;
    final sliderValue = totalMilliseconds == 0
        ? 0.0
        : currentPosition.inMilliseconds.clamp(0, totalMilliseconds).toDouble();
    final canSeek = enabled && value.isInitialized && totalMilliseconds > 0;
    final timeStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: const Color(0xFF747B88),
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Row(
      children: <Widget>[
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              inactiveTrackColor: primary.withValues(alpha: 0.28),
              disabledInactiveTrackColor: const Color(0xFFD0C2BE),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            ),
            child: Slider(
              key: const ValueKey<String>('merge-seek-bar'),
              min: 0,
              max: totalMilliseconds == 0 ? 1 : totalMilliseconds.toDouble(),
              value: sliderValue,
              onChanged: canSeek
                  ? (milliseconds) =>
                        onSeek(Duration(milliseconds: milliseconds.round()))
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          key: const ValueKey<String>('merge-playback-time'),
          width: 92,
          child: Text(
            '${_formatMergeDuration(currentPosition)} / '
            '${_formatMergeDuration(totalDuration)}',
            textAlign: TextAlign.right,
            maxLines: 1,
            style: timeStyle,
          ),
        ),
      ],
    );
  }
}

class _MergePlayButton extends StatelessWidget {
  const _MergePlayButton({required this.controller, required this.onPressed});

  final VideoPlayerController? controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return _buildButton(context, isPlaying: false);
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _buildButton(context, isPlaying: value.isPlaying),
    );
  }

  Widget _buildButton(BuildContext context, {required bool isPlaying}) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: IconButton(
        key: const ValueKey<String>('merge-preview-play-button'),
        onPressed: onPressed,
        tooltip: isPlaying ? 'Pause' : 'Play',
        iconSize: 25,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: _mergeCompactButtonSize,
          height: _mergeCompactButtonSize,
        ),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: primary,
          disabledForegroundColor: const Color(0xFF9A9EA6),
          minimumSize: const Size.square(_mergeCompactButtonSize),
          maximumSize: const Size.square(_mergeCompactButtonSize),
        ),
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}

class _MergeAddVideoButton extends StatelessWidget {
  const _MergeAddVideoButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: _mergeAddButtonWidth,
      height: _mergeThumbnailSize,
      child: Center(
        child: IconButton(
          key: const ValueKey<String>('merge-add-video-button'),
          onPressed: onPressed,
          tooltip: 'Add video',
          iconSize: 25,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: _mergeCompactButtonSize,
            height: _mergeCompactButtonSize,
          ),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: primary,
            minimumSize: const Size.square(_mergeCompactButtonSize),
            maximumSize: const Size.square(_mergeCompactButtonSize),
          ),
          icon: isLoading
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                )
              : const Icon(Icons.add_rounded),
        ),
      ),
    );
  }
}

class _MergeOptionCheckbox extends StatelessWidget {
  const _MergeOptionCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Checkbox(
            key: ValueKey<String>(
              'merge-${label.toLowerCase().replaceAll(' ', '-')}-checkbox',
            ),
            value: value,
            onChanged: onChanged == null
                ? null
                : (checked) => onChanged!(checked ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 2),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _MergeSaveButton extends StatelessWidget {
  const _MergeSaveButton({
    required this.onPressed,
    required this.isMerging,
    required this.showCompleted,
    required this.progress,
  });

  final VoidCallback? onPressed;
  final bool isMerging;
  final bool showCompleted;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(20);
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final displayProgress = showCompleted
        ? 1.0
        : isMerging
        ? progress.clamp(0.0, 1.0)
        : 0.0;
    final icon = showCompleted
        ? Icons.check_rounded
        : isMerging
        ? Icons.stop_rounded
        : Icons.call_merge;
    final label = showCompleted
        ? 'Saved'
        : isMerging
        ? 'Cancel'
        : 'Merge & Save';
    final isDisabled = onPressed == null;
    final background = isDisabled
        ? colorScheme.onSurface.withValues(alpha: 0.12)
        : isMerging
        ? colorScheme.primaryContainer
        : primary;
    final baseForeground = isDisabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isMerging
        ? primary
        : Colors.white;

    return SizedBox(
      key: const ValueKey<String>('merge-save-button'),
      width: _mergeSaveButtonWidth,
      height: _mergeActionButtonHeight,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(radius),
        child: Material(
          color: background,
          child: InkWell(
            onTap: onPressed,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: isMerging
                            ? const Duration(milliseconds: 240)
                            : Duration.zero,
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * displayProgress,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.horizontal(
                            left: radius,
                            right: displayProgress >= 0.999
                                ? radius
                                : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: _MergeSaveButtonContent(
                        icon: icon,
                        label: label,
                        color: baseForeground,
                      ),
                    ),
                    if (displayProgress > 0)
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: displayProgress,
                          child: Center(
                            child: _MergeSaveButtonContent(
                              icon: icon,
                              label: label,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MergeSaveButtonContent extends StatelessWidget {
  const _MergeSaveButtonContent({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatMergeDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:$minutes:$seconds'
      : '${duration.inMinutes}:$seconds';
}

String _formatMergeFrameRate(
  double? frameRate, {
  String unavailable = 'FPS unavailable',
}) {
  if (frameRate == null) {
    return unavailable;
  }
  final rounded = frameRate.round();
  final value = (frameRate - rounded).abs() < 0.005
      ? '$rounded'
      : frameRate.toStringAsFixed(2);
  return '$value FPS';
}
