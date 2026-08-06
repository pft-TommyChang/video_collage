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

const double _mergeDialogWidth = 760;
const double _mergeMaximumPreviewHeight = 400;
const double _mergeListHeight = 106;
const double _mergeThumbnailSize = 90;
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
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Export: ${firstVideo.width}×${firstVideo.height}  •  '
                            '${_formatMergeFrameRate(_outputFrameRate, unavailable: 'FPS loading…')}  •  '
                            '${_formatMergeDuration(_totalDuration)} total',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF747B88)),
                          ),
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
                const SizedBox(height: 10),
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
                      SizedBox(
                        width: 76,
                        child: _MergePlayButton(
                          controller: selectedController,
                          onPressed: selectedController == null || _isMerging
                              ? null
                              : () => unawaited(_togglePlayback()),
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
                          itemCount: _videos.length + 1,
                          onReorder: _isMerging ? (_, _) {} : _reorder,
                          itemBuilder: (context, index) {
                            if (index == _videos.length) {
                              return Padding(
                                key: const ValueKey<String>(
                                  'merge-add-video-tile',
                                ),
                                padding: const EdgeInsets.only(right: 6),
                                child: _MergeAddVideoTile(
                                  isLoading: _isAdding,
                                  onPressed: _isAdding || _isMerging
                                      ? null
                                      : _addVideos,
                                ),
                              );
                            }
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
                                  frameRate: _videoFrameRates[video.id],
                                  isSelected: video.id == _selectedVideoId,
                                  onTap: _isMerging
                                      ? null
                                      : () => unawaited(_selectVideo(video)),
                                  onRemove: _isMerging
                                      ? null
                                      : () => _removeVideo(index),
                                ),
                              ),
                            );
                          },
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
      await controller.seekTo(Duration.zero);
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
      await next?.seekTo(Duration.zero);
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
    if (controller.value.isCompleted ||
        controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
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
        (!value.isCompleted && value.position < value.duration)) {
      return;
    }
    _isAdvancingPreview = true;
    unawaited(_advancePreviewFrom(id));
  }

  Future<void> _advancePreviewFrom(String id) async {
    try {
      final currentIndex = _videos.indexWhere((video) => video.id == id);
      if (currentIndex < 0 || currentIndex >= _videos.length - 1) {
        if (mounted) {
          setState(() => _isSequencePlaying = false);
        }
        return;
      }

      final current = _thumbnailControllers[id];
      if (current?.value.isPlaying == true) {
        await current?.pause();
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
      await next.seekTo(Duration.zero);
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
    required this.frameRate,
    required this.isSelected,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final VideoClipInfo video;
  final VideoPlayerController? controller;
  final double? frameRate;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isReady = controller?.value.isInitialized == true;
    return Tooltip(
      message:
          '${p.basename(video.path)}\n'
          '${video.width}×${video.height} • '
          '${_formatMergeFrameRate(frameRate)} • '
          '${_formatMergeDuration(video.duration)}',
      child: MouseRegion(
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

class _MergePlayButton extends StatelessWidget {
  const _MergePlayButton({required this.controller, required this.onPressed});

  final VideoPlayerController? controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Material(
        color: onPressed == null ? const Color(0xFF343943) : primary,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey<String>('merge-preview-play-button'),
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 52,
            child: Center(
              child: controller == null
                  ? const Icon(
                      Icons.play_arrow_rounded,
                      size: 31,
                      color: Color(0xFF747A84),
                    )
                  : ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 31,
                        color: value.isInitialized
                            ? Colors.white
                            : const Color(0xFF747A84),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MergeAddVideoTile extends StatelessWidget {
  const _MergeAddVideoTile({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: _mergeThumbnailSize,
      child: Tooltip(
        message: 'Add video',
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: primary,
            backgroundColor: primary.withValues(alpha: 0.035),
            side: BorderSide(color: primary.withValues(alpha: 0.42)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: isLoading
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                )
              : const Icon(Icons.add_rounded, size: 32),
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
