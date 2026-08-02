import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'services/desktop_file_service.dart';
import 'services/system_dialog_service.dart';
import 'services/video_export_service.dart';

class VideoTrimResult {
  const VideoTrimResult({required this.start, required this.end});

  final Duration start;
  final Duration end;
}

enum _TimelineDragTarget { trimStart, trimEnd, selection, playhead }

enum _TrimExportAction { openFile, openFolder }

enum _TrimExportResolution {
  original('Original', null),
  p720('720p', 720),
  p1080('1080p', 1080),
  p1440('2K', 1440),
  p2160('4K', 2160);

  const _TrimExportResolution(this.label, this.shortEdge);

  final String label;
  final int? shortEdge;
}

enum _TrimExportFrameRate {
  original('Original', null),
  fps24('24 FPS', 24),
  fps30('30 FPS', 30),
  fps60('60 FPS', 60);

  const _TrimExportFrameRate(this.label, this.framesPerSecond);

  final String label;
  final int? framesPerSecond;
}

class _TrimExportSettings {
  const _TrimExportSettings({
    required this.resolution,
    required this.frameRate,
  });

  final _TrimExportResolution resolution;
  final _TrimExportFrameRate frameRate;
}

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
  static const double _dialogVerticalChromeHeight = 220;
  static const double _minimumDialogContentHeight = 250;
  static const double _maximumDialogContentHeight = 532;
  static const double _maximumPreviewHeight = 420;
  static const SystemDialogService _dialogService = SystemDialogService();

  VideoPlayerController? _controller;
  Timer? _exportCompletionTimer;
  Timer? _toastTimer;
  OverlayEntry? _toastOverlayEntry;
  List<String> _thumbnailPaths = const <String>[];
  String? _thumbnailDirectory;
  String? _error;
  late RangeValues _selection;
  double _positionMilliseconds = 0;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _showExportComplete = false;
  double _exportProgress = 0;
  String? _lastExportPath;
  _TrimExportResolution _exportResolution = _TrimExportResolution.original;
  _TrimExportFrameRate _exportFrameRate = _TrimExportFrameRate.original;
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
    final outputSize = _exportOutputSize();
    setState(() {
      _exportCompletionTimer?.cancel();
      _isExporting = true;
      _showExportComplete = false;
      _exportProgress = 0;
    });
    try {
      await widget.exportService.exportTrimmedVideo(
        filePath: widget.clip.path,
        start: Duration(milliseconds: _selection.start.round()),
        duration: selectedDuration,
        outputPath: outputPath,
        hasAudio: widget.clip.hasAudio,
        outputSize: outputSize,
        frameRate: _exportFrameRate.framesPerSecond,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _exportProgress = progress.progress;
            });
          }
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _showExportComplete = true;
        _exportProgress = 1;
        _lastExportPath = outputPath;
      });
      _exportCompletionTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) {
          setState(() {
            _showExportComplete = false;
            _exportProgress = 0;
          });
        }
      });
      _showToast('Exported ${p.basename(outputPath)}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _showExportComplete = false;
        _exportProgress = 0;
      });
      final message =
          error is VideoExportException && error.message == 'Export cancelled.'
          ? error.message
          : 'Unable to export trimmed video: $error';
      _showToast(message);
    }
  }

  Future<void> _handleExportButtonPressed() async {
    if (_isExporting) {
      await widget.exportService.cancelActiveExport();
      return;
    }
    final settings = await _showExportSettings();
    if (settings == null || !mounted) {
      return;
    }
    setState(() {
      _exportResolution = settings.resolution;
      _exportFrameRate = settings.frameRate;
    });
    await _exportTrimmedVideo();
  }

  Future<_TrimExportSettings?> _showExportSettings() {
    var resolution = _exportResolution;
    var frameRate = _exportFrameRate;
    return showDialog<_TrimExportSettings>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Export settings'),
          content: SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _TrimExportChoiceSection<_TrimExportResolution>(
                  title: 'Resolution',
                  options: _TrimExportResolution.values,
                  selected: resolution,
                  labelFor: (option) => option.label,
                  onSelected: (option) {
                    setDialogState(() => resolution = option);
                  },
                ),
                const SizedBox(height: 20),
                _TrimExportChoiceSection<_TrimExportFrameRate>(
                  title: 'FPS',
                  options: _TrimExportFrameRate.values,
                  selected: frameRate,
                  labelFor: (option) => option.label,
                  onSelected: (option) {
                    setDialogState(() => frameRate = option);
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _TrimExportSettings(
                  resolution: resolution,
                  frameRate: frameRate,
                ),
              ),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }

  ({int width, int height})? _exportOutputSize() {
    final shortEdge = _exportResolution.shortEdge;
    final sourceWidth = widget.clip.width;
    final sourceHeight = widget.clip.height;
    if (shortEdge == null || sourceWidth <= 0 || sourceHeight <= 0) {
      return null;
    }

    int even(int value) => value.isEven ? value : value + 1;
    if (sourceWidth <= sourceHeight) {
      return (
        width: shortEdge,
        height: even((sourceHeight * shortEdge / sourceWidth).round()),
      );
    }
    return (
      width: even((sourceWidth * shortEdge / sourceHeight).round()),
      height: shortEdge,
    );
  }

  Future<void> _openLastExport({bool revealInFolder = false}) async {
    final exportPath = _lastExportPath;
    if (exportPath == null) {
      return;
    }
    if (!await File(exportPath).exists()) {
      _showToast('Export file no longer exists: $exportPath');
      return;
    }

    final targetDescription = revealInFolder
        ? 'folder: ${p.dirname(exportPath)}'
        : 'export: $exportPath';
    final didOpen = revealInFolder
        ? await DesktopFileService.revealFile(exportPath)
        : await DesktopFileService.openFile(exportPath);
    if (!didOpen) {
      _showToast('Unable to open $targetDescription');
    }
  }

  void _showToast(String message) {
    if (!mounted) {
      return;
    }
    _toastTimer?.cancel();
    _toastOverlayEntry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 24,
        right: 24,
        bottom: 36,
        child: IgnorePointer(
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xE3171A21),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _toastOverlayEntry = entry;
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toastOverlayEntry?.remove();
      _toastOverlayEntry = null;
      _toastTimer = null;
    });
  }

  Future<void> _showLastExportMenu(TapDownDetails details) async {
    if (_isExporting || _lastExportPath == null) {
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = details.globalPosition;
    final action = await showMenu<_TrimExportAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<_TrimExportAction>>[
        PopupMenuItem<_TrimExportAction>(
          value: _TrimExportAction.openFile,
          child: Text('Open File'),
        ),
        PopupMenuItem<_TrimExportAction>(
          value: _TrimExportAction.openFolder,
          child: Text('Open Folder'),
        ),
      ],
    );

    switch (action) {
      case _TrimExportAction.openFile:
        await _openLastExport();
      case _TrimExportAction.openFolder:
        await _openLastExport(revealInFolder: true);
      case null:
        return;
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
    _exportCompletionTimer?.cancel();
    _toastTimer?.cancel();
    _toastOverlayEntry?.remove();
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
    final availableContentHeight =
        (MediaQuery.sizeOf(context).height - _dialogVerticalChromeHeight).clamp(
          _minimumDialogContentHeight,
          _maximumDialogContentHeight,
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
        height: availableContentHeight,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: _maximumPreviewHeight,
                  ),
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
              _TrimExportButton(
                onPressed: _controller == null
                    ? null
                    : () => unawaited(_handleExportButtonPressed()),
                isExporting: _isExporting,
                showCompleted: _showExportComplete,
                progress: _exportProgress,
              ),
              if (_lastExportPath != null) ...<Widget>[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: _isExporting
                      ? null
                      : (details) => unawaited(_showLastExportMenu(details)),
                  child: IconButton(
                    onPressed: _isExporting
                        ? null
                        : () => unawaited(_openLastExport()),
                    tooltip: 'Open File',
                    icon: const Icon(Icons.open_in_new_rounded),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                  ),
                ),
              ],
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
                                  Positioned(
                                    left: _trimHandleWidth,
                                    top: _timelineRailThickness,
                                    bottom: _timelineRailThickness,
                                    width: startBoundary - _trimHandleWidth,
                                    child: const ColoredBox(
                                      color: Color(0x99000000),
                                    ),
                                  ),
                                  Positioned(
                                    left: endBoundary,
                                    right: _trimHandleWidth,
                                    top: _timelineRailThickness,
                                    bottom: _timelineRailThickness,
                                    child: const ColoredBox(
                                      color: Color(0x99000000),
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

class _TrimExportChoiceSection<T> extends StatelessWidget {
  const _TrimExportChoiceSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T option) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final option in options)
              ChoiceChip(
                label: Text(labelFor(option)),
                selected: selected == option,
                showCheckmark: false,
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrimExportButton extends StatelessWidget {
  const _TrimExportButton({
    required this.onPressed,
    required this.isExporting,
    required this.showCompleted,
    required this.progress,
  });

  final VoidCallback? onPressed;
  final bool isExporting;
  final bool showCompleted;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(16);
    const buttonWidth = 124.0;
    // Matches the compact desktop height used by the adjacent Material
    // TextButton and FilledButton controls.
    const buttonHeight = 32.0;
    final colorScheme = Theme.of(context).colorScheme;
    final sharedButtonColor = colorScheme.primary;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final displayProgress = showCompleted
        ? 1.0
        : (isExporting ? clampedProgress : 0.0);
    final icon = showCompleted
        ? Icons.check_rounded
        : isExporting
        ? Icons.stop_rounded
        : Icons.file_upload_outlined;
    final label = isExporting ? 'Exporting' : 'Export';

    return SizedBox(
      width: buttonWidth,
      height: buttonHeight,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(radius),
        child: Material(
          color: isExporting
              ? colorScheme.primaryContainer
              : Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: sharedButtonColor),
                borderRadius: const BorderRadius.all(radius),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fillWidth = constraints.maxWidth * displayProgress;
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          // Animate progress only while exporting. Completion
                          // resets directly to the outline state so the fill
                          // never appears to run backwards.
                          duration: isExporting
                              ? const Duration(milliseconds: 240)
                              : Duration.zero,
                          curve: Curves.easeOutCubic,
                          width: fillWidth,
                          decoration: BoxDecoration(
                            color: sharedButtonColor,
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
                        child: _TrimExportButtonContent(
                          icon: icon,
                          label: label,
                          color: sharedButtonColor,
                        ),
                      ),
                      if (displayProgress > 0)
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: displayProgress,
                            child: Center(
                              child: _TrimExportButtonContent(
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
      ),
    );
  }
}

class _TrimExportButtonContent extends StatelessWidget {
  const _TrimExportButtonContent({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
      ],
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
