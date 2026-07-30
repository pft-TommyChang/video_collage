import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'services/system_dialog_service.dart';
import 'services/video_export_service.dart';

class VideoTrimResult {
  const VideoTrimResult({required this.start, required this.end});

  final Duration start;
  final Duration end;
}

enum _TimelineDragTarget { trimStart, trimEnd, selection, playhead }

class VideoTrimmerDialog extends StatefulWidget {
  const VideoTrimmerDialog({
    super.key,
    required this.clip,
    required this.exportService,
  });

  final VideoClipInfo clip;
  final VideoExportService exportService;

  @override
  State<VideoTrimmerDialog> createState() => _VideoTrimmerDialogState();
}

class _VideoTrimmerDialogState extends State<VideoTrimmerDialog> {
  static const int _thumbnailCount = 12;
  static const double _timelineHeight = 66;
  static const double _minimumTrimMilliseconds = 200;
  static const double _playButtonWidth = 58;
  static const double _timelineGap = 0;
  static const double _trimHandleWidth = 20;
  static const double _timelineRailThickness = 4;
  static const SystemDialogService _dialogService = SystemDialogService();

  VideoPlayerController? _controller;
  List<String> _thumbnailPaths = const <String>[];
  String? _thumbnailDirectory;
  String? _error;
  late RangeValues _selection;
  double _positionMilliseconds = 0;
  bool _isLoading = true;
  bool _isExporting = false;
  _TimelineDragTarget? _activeDragTarget;

  double get _sourceMilliseconds => widget.clip.fullDuration.inMilliseconds
      .toDouble()
      .clamp(1, double.infinity);
  double get _effectiveMinimumTrimMilliseconds =>
      _sourceMilliseconds < _minimumTrimMilliseconds
      ? _sourceMilliseconds
      : _minimumTrimMilliseconds;

  @override
  void initState() {
    super.initState();
    final max = _sourceMilliseconds;
    _selection = RangeValues(
      widget.clip.trimStart.inMilliseconds.toDouble().clamp(0, max),
      widget.clip.trimEnd.inMilliseconds.toDouble().clamp(0, max),
    );
    _positionMilliseconds = _selection.start;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(widget.clip.path));
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1);
      await controller.seekTo(Duration(milliseconds: _selection.start.round()));
      controller.addListener(_handleControllerChanged);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
      controller = null;
      unawaited(_loadThumbnails());
    } catch (error) {
      await controller?.dispose();
      if (mounted) {
        setState(() {
          _error = 'Unable to open video preview: $error';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadThumbnails() async {
    try {
      final result = await widget.exportService.generateVideoThumbnails(
        filePath: widget.clip.path,
        duration: widget.clip.fullDuration,
        count: _thumbnailCount,
        onProgress: (paths) {
          if (mounted) {
            setState(() {
              _thumbnailPaths = paths;
            });
          }
        },
      );
      if (!mounted) {
        await result.dispose();
        return;
      }
      setState(() {
        _thumbnailPaths = result.paths;
        _thumbnailDirectory = result.directoryPath;
      });
    } catch (_) {
      // The trimmer remains usable with a neutral timeline if extraction fails.
    }
  }

  Future<void> _exportTrimmedVideo() async {
    if (_isExporting) {
      return;
    }
    final outputPath = await _dialogService.pickSavePath(
      format: ExportFormat.mp4,
      suggestedName:
          '${p.basenameWithoutExtension(widget.clip.path)}_trimmed.mp4',
    );
    if (outputPath == null || !mounted) {
      return;
    }

    final selectedDuration = Duration(
      milliseconds: (_selection.end - _selection.start).round(),
    );
    setState(() {
      _isExporting = true;
    });
    try {
      await widget.exportService.exportTrimmedVideo(
        filePath: widget.clip.path,
        start: Duration(milliseconds: _selection.start.round()),
        duration: selectedDuration,
        outputPath: outputPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${p.basename(outputPath)}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to export trimmed video: $error')),
      );
    }
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    final position = controller.value.position.inMilliseconds.toDouble();
    if (controller.value.isPlaying && position >= _selection.end) {
      unawaited(controller.pause());
      unawaited(
        controller.seekTo(Duration(milliseconds: _selection.start.round())),
      );
    }
    if ((position - _positionMilliseconds).abs() >= 16) {
      setState(() {
        _positionMilliseconds = position.clamp(
          _selection.start,
          _selection.end,
        );
      });
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }
    if (controller.value.position.inMilliseconds >= _selection.end - 40) {
      await controller.seekTo(Duration(milliseconds: _selection.start.round()));
    }
    await controller.play();
  }

  Future<void> _seekPreservingPlayback(double milliseconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final wasPlaying = controller.value.isPlaying;
    await controller.seekTo(Duration(milliseconds: milliseconds.round()));
    if (wasPlaying && !controller.value.isPlaying) {
      await controller.play();
    }
  }

  void _updateSelection(RangeValues values) {
    var start = values.start;
    var end = values.end;
    final minimumTrim = _effectiveMinimumTrimMilliseconds;
    if (end - start < minimumTrim) {
      if ((start - _selection.start).abs() > (end - _selection.end).abs()) {
        start = (end - minimumTrim).clamp(0, _sourceMilliseconds);
      } else {
        end = (start + minimumTrim).clamp(0, _sourceMilliseconds);
      }
    }
    final selection = RangeValues(start, end);
    setState(() {
      _selection = selection;
      _positionMilliseconds = _positionMilliseconds.clamp(start, end);
    });
    unawaited(_seekPreservingPlayback(_positionMilliseconds));
  }

  double _timelineContentWidth(double width) {
    return (width - (_trimHandleWidth * 2)).clamp(1, double.infinity);
  }

  double _timelineXForMilliseconds(double milliseconds, double width) {
    return _trimHandleWidth +
        _timelineContentWidth(width) * milliseconds / _sourceMilliseconds;
  }

  double _millisecondsForTimelineX(double x, double width) {
    return ((x - _trimHandleWidth) /
            _timelineContentWidth(width) *
            _sourceMilliseconds)
        .clamp(0, _sourceMilliseconds);
  }

  void _beginTimelineDrag(Offset localPosition, double width) {
    final x = localPosition.dx;
    final startBoundary = _timelineXForMilliseconds(_selection.start, width);
    final endBoundary = _timelineXForMilliseconds(_selection.end, width);
    final playhead = _timelineXForMilliseconds(_positionMilliseconds, width);

    if ((x - playhead).abs() <= 6) {
      _activeDragTarget = _TimelineDragTarget.playhead;
    } else if (x >= startBoundary - _trimHandleWidth && x <= startBoundary) {
      _activeDragTarget = _TimelineDragTarget.trimStart;
    } else if (x >= endBoundary && x <= endBoundary + _trimHandleWidth) {
      _activeDragTarget = _TimelineDragTarget.trimEnd;
    } else if (x > startBoundary && x < endBoundary) {
      _activeDragTarget = _TimelineDragTarget.selection;
    } else {
      _activeDragTarget = (x - startBoundary).abs() <= (x - endBoundary).abs()
          ? _TimelineDragTarget.trimStart
          : _TimelineDragTarget.trimEnd;
    }
  }

  void _dragTimeline({
    required Offset localPosition,
    required double deltaX,
    required double width,
  }) {
    final target = _activeDragTarget;
    if (target == null || width <= 0) {
      return;
    }
    if (target == _TimelineDragTarget.playhead) {
      final position = _millisecondsForTimelineX(
        localPosition.dx,
        width,
      ).clamp(_selection.start, _selection.end);
      setState(() {
        _positionMilliseconds = position;
      });
      unawaited(_seekPreservingPlayback(position));
      return;
    }

    final deltaMilliseconds =
        deltaX / _timelineContentWidth(width) * _sourceMilliseconds;
    if (target == _TimelineDragTarget.selection) {
      final selectedDuration = _selection.end - _selection.start;
      final start = (_selection.start + deltaMilliseconds).clamp(
        0.0,
        _sourceMilliseconds - selectedDuration,
      );
      final actualDelta = start - _selection.start;
      final position = (_positionMilliseconds + actualDelta).clamp(
        start,
        start + selectedDuration,
      );
      setState(() {
        _selection = RangeValues(start, start + selectedDuration);
        _positionMilliseconds = position;
      });
      unawaited(_seekPreservingPlayback(position));
      return;
    }

    final values = switch (target) {
      _TimelineDragTarget.trimStart => RangeValues(
        (_selection.start + deltaMilliseconds).clamp(
          0,
          _selection.end - _effectiveMinimumTrimMilliseconds,
        ),
        _selection.end,
      ),
      _TimelineDragTarget.trimEnd => RangeValues(
        _selection.start,
        (_selection.end + deltaMilliseconds).clamp(
          _selection.start + _effectiveMinimumTrimMilliseconds,
          _sourceMilliseconds,
        ),
      ),
      _TimelineDragTarget.selection ||
      _TimelineDragTarget.playhead => _selection,
    };
    _updateSelection(values);
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_handleControllerChanged);
    unawaited(controller?.dispose());
    final directory = _thumbnailDirectory;
    if (directory != null) {
      unawaited(_deleteThumbnailDirectory(directory));
    }
    super.dispose();
  }

  Future<void> _deleteThumbnailDirectory(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Temporary thumbnails are best-effort cleanup.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final selectedDuration = Duration(
      milliseconds: (_selection.end - _selection.start).round(),
    );
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.content_cut_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Trim video',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: AspectRatio(
                  aspectRatio: widget.clip.width > 0 && widget.clip.height > 0
                      ? widget.clip.width / widget.clip.height
                      : 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: widget.clip.width > 0
                                    ? widget.clip.width.toDouble()
                                    : controller!.value.size.width,
                                height: widget.clip.height > 0
                                    ? widget.clip.height.toDouble()
                                    : controller!.value.size.height,
                                child: VideoPlayer(controller!),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _buildTimeline(),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  formatPreciseDuration(
                    Duration(milliseconds: _selection.start.round()),
                  ),
                ),
                const Spacer(),
                Text(
                  'Selected ${formatPreciseDuration(selectedDuration)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  formatPreciseDuration(
                    Duration(milliseconds: _selection.end.round()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        SizedBox(
          width: 760,
          child: Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _controller == null || _isExporting
                    ? null
                    : _exportTrimmedVideo,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
                label: Text(_isExporting ? 'Exporting...' : 'Export'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _isExporting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _controller == null || _isExporting
                    ? null
                    : () => Navigator.of(context).pop(
                        VideoTrimResult(
                          start: Duration(
                            milliseconds: _selection.start.round(),
                          ),
                          end: Duration(milliseconds: _selection.end.round()),
                        ),
                      ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Apply trim'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    final controller = _controller;
    final isPlaying = controller?.value.isPlaying == true;
    return Row(
      children: <Widget>[
        SizedBox(
          width: _playButtonWidth,
          height: _timelineHeight,
          child: Material(
            color: const Color(0xFF181A1F),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(9),
            ),
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(9),
              ),
              onTap: controller == null ? null : _togglePlayback,
              child: Center(
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: _timelineGap),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final startBoundary = _timelineXForMilliseconds(
                _selection.start,
                width,
              );
              final endBoundary = _timelineXForMilliseconds(
                _selection.end,
                width,
              );
              final playheadX = _timelineXForMilliseconds(
                _positionMilliseconds,
                width,
              );

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) =>
                      _beginTimelineDrag(details.localPosition, width),
                  onPanUpdate: (details) => _dragTimeline(
                    localPosition: details.localPosition,
                    deltaX: details.delta.dx,
                    width: width,
                  ),
                  onPanEnd: (_) => _activeDragTarget = null,
                  onPanCancel: () => _activeDragTarget = null,
                  child: SizedBox(
                    height: _timelineHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(9),
                            ),
                            child: ColoredBox(
                              color: const Color(0xFF181A1F),
                              child: Stack(
                                children: <Widget>[
                                  Positioned(
                                    left: _trimHandleWidth,
                                    right: _trimHandleWidth,
                                    top: _timelineRailThickness,
                                    bottom: _timelineRailThickness,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: _thumbnailPaths.isEmpty
                                          ? const ColoredBox(
                                              color: Color(0xFF2B3038),
                                            )
                                          : Row(
                                              children: <Widget>[
                                                for (
                                                  var index = 0;
                                                  index < _thumbnailCount;
                                                  index += 1
                                                )
                                                  Expanded(
                                                    child: _buildThumbnailSlot(
                                                      index,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    left: _trimHandleWidth,
                                    top: _timelineRailThickness,
                                    bottom: _timelineRailThickness,
                                    width: startBoundary - _trimHandleWidth,
                                    child: const ClipRRect(
                                      borderRadius: BorderRadius.horizontal(
                                        left: Radius.circular(6),
                                      ),
                                      child: ColoredBox(
                                        color: Color(0x99000000),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: endBoundary,
                                    right: _trimHandleWidth,
                                    top: _timelineRailThickness,
                                    bottom: _timelineRailThickness,
                                    child: const ClipRRect(
                                      borderRadius: BorderRadius.horizontal(
                                        right: Radius.circular(6),
                                      ),
                                      child: ColoredBox(
                                        color: Color(0x99000000),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: startBoundary,
                                    top: 0,
                                    bottom: 0,
                                    width: endBoundary - startBoundary,
                                    child: const IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.symmetric(
                                            horizontal: BorderSide(
                                              color: Color(0xFFFFD400),
                                              width: _timelineRailThickness,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildTrimHandle(
                                    left: startBoundary - _trimHandleWidth,
                                    icon: Icons.chevron_left_rounded,
                                    borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(7),
                                    ),
                                  ),
                                  _buildTrimHandle(
                                    left: endBoundary,
                                    icon: Icons.chevron_right_rounded,
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: playheadX - 1.5,
                          top: -5,
                          bottom: -7,
                          child: IgnorePointer(
                            child: Container(
                              width: 3,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0x88000000),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailSlot(int index) {
    final path = index < _thumbnailPaths.length ? _thumbnailPaths[index] : null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: SizedBox.expand(
        key: ValueKey<String>(path ?? 'empty-thumbnail'),
        child: path == null
            ? const ColoredBox(color: Color(0xFF2B3038))
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) =>
                    const ColoredBox(color: Color(0xFF2B3038)),
              ),
      ),
    );
  }

  Widget _buildTrimHandle({
    required double left,
    required IconData icon,
    required BorderRadius borderRadius,
  }) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: _trimHandleWidth,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFD400),
            borderRadius: borderRadius,
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF171717)),
        ),
      ),
    );
  }
}

String formatPreciseDuration(Duration duration) {
  final totalMilliseconds = duration.inMilliseconds;
  final minutes = totalMilliseconds ~/ 60000;
  final seconds = (totalMilliseconds % 60000) ~/ 1000;
  final tenths = (totalMilliseconds % 1000) ~/ 100;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}
