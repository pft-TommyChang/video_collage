import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'services/editor_settings_store.dart';
import 'services/system_dialog_service.dart';
import 'services/video_export_service.dart';

const _aspectPresets = <AspectRatioPreset>[
  AspectRatioPreset(label: '1:1', widthFactor: 1, heightFactor: 1),
  AspectRatioPreset(label: '4:5', widthFactor: 4, heightFactor: 5),
  AspectRatioPreset(label: '9:16', widthFactor: 9, heightFactor: 16),
  AspectRatioPreset(label: '3:4', widthFactor: 3, heightFactor: 4),
  AspectRatioPreset(label: '16:9', widthFactor: 16, heightFactor: 9),
];

const _resolutionPresets = <ResolutionPreset>[
  ResolutionPreset(label: 'HD 720', shortEdge: 720),
  ResolutionPreset(label: 'Full HD 1080', shortEdge: 1080),
  ResolutionPreset(label: '2K 1440', shortEdge: 1440),
  ResolutionPreset(label: '4K 2160', shortEdge: 2160),
];

const _colorChoices = <ColorChoice>[
  ColorChoice(label: 'White', color: Color(0xFFFFFFFF), ffmpegHex: '0xFFFFFF'),
  ColorChoice(label: 'Grey', color: Color(0xFFD0D5DD), ffmpegHex: '0xD0D5DD'),
  ColorChoice(label: 'Ink', color: Color(0xFF101217), ffmpegHex: '0x101217'),
  ColorChoice(label: 'Coral', color: Color(0xFFFF7A59), ffmpegHex: '0xFF7A59'),
  ColorChoice(label: 'Aqua', color: Color(0xFF4CC9C0), ffmpegHex: '0x4CC9C0'),
];

const _supportedVideoExtensions = <String>{
  '.mp4',
  '.mov',
  '.m4v',
  '.avi',
  '.mkv',
};

class VideoCollageApp extends StatelessWidget {
  const VideoCollageApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF7A59),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Perfect Video Collage',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF3EFE7),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF171A21),
          displayColor: const Color(0xFF171A21),
        ),
      ),
      home: const VideoCollageScreen(),
    );
  }
}

class VideoCollageScreen extends StatefulWidget {
  const VideoCollageScreen({super.key});

  @override
  State<VideoCollageScreen> createState() => _VideoCollageScreenState();
}

class _VideoCollageScreenState extends State<VideoCollageScreen> {
  final SystemDialogService _dialogService = const SystemDialogService();
  final EditorSettingsStore _settingsStore = const EditorSettingsStore();
  final VideoExportService _exportService = const VideoExportService();

  final List<VideoClipInfo> _clips = <VideoClipInfo>[];
  final Map<int, String> _slotAssignments = <int, String>{};
  final Map<String, VideoPlayerController> _controllers =
      <String, VideoPlayerController>{};
  final Set<String> _loadingClipPaths = <String>{};
  final Map<String, String> _clipErrors = <String, String>{};

  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  Timer? _settingsSaveDebounce;
  bool _isRestoringSettings = false;
  int? _externalDropHoverSlotIndex;

  AspectRatioPreset _selectedAspect = _aspectPresets[4];
  ResolutionPreset _selectedResolution = _resolutionPresets[1];
  ColorChoice _selectedBorderColor = _colorChoices[0];
  ColorChoice _selectedBackgroundColor = _colorChoices[1];

  int _rows = 2;
  int _columns = 2;
  double _borderThickness = 12;
  double _tileCornerRadius = 12;
  bool _includeClipLabelsInOutput = false;
  bool _isImporting = false;
  bool _isExporting = false;
  double _exportProgress = 0;
  bool _isPreviewPlaying = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final initialSize = _sizeFromPreset(_selectedAspect, _selectedResolution);
    _widthController = TextEditingController(text: '${initialSize.$1}')
      ..addListener(_scheduleSettingsSave);
    _heightController = TextEditingController(text: '${initialSize.$2}')
      ..addListener(_scheduleSettingsSave);
    unawaited(_restoreSettings());
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    _widthController.dispose();
    _heightController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ExportOptions get _options {
    final width = int.tryParse(_widthController.text) ?? 1080;
    final height = int.tryParse(_heightController.text) ?? 1920;
    return ExportOptions(
      rows: _rows,
      columns: _columns,
      outputWidth: width,
      outputHeight: height,
      borderThickness: _borderThickness,
      tileCornerRadius: _tileCornerRadius,
      backgroundColor: _selectedBackgroundColor,
      borderColor: _selectedBorderColor,
      includeClipLabelsInOutput: _includeClipLabelsInOutput,
    );
  }

  int get _gridCapacity => _rows * _columns;

  Future<void> _restoreSettings() async {
    final savedSettings = await _settingsStore.load();
    if (!mounted || savedSettings == null) {
      return;
    }

    _isRestoringSettings = true;
    setState(() {
      _rows = savedSettings.rows.clamp(1, 6);
      _columns = savedSettings.columns.clamp(1, 6);
      _borderThickness = savedSettings.borderThickness.clamp(0, 48).toDouble();
      _tileCornerRadius = savedSettings.tileCornerRadius
          .clamp(0, 48)
          .toDouble();
      _includeClipLabelsInOutput = savedSettings.includeClipLabelsInOutput;
      _selectedAspect = _aspectPresets.firstWhere(
        (preset) => preset.label == savedSettings.aspectLabel,
        orElse: () => _selectedAspect,
      );
      _selectedResolution = _resolutionPresets.firstWhere(
        (preset) => preset.label == savedSettings.resolutionLabel,
        orElse: () => _selectedResolution,
      );
      _selectedBorderColor = _colorChoices.firstWhere(
        (choice) => choice.label == savedSettings.borderColorLabel,
        orElse: () => _selectedBorderColor,
      );
      _selectedBackgroundColor = _colorChoices.firstWhere(
        (choice) => choice.label == savedSettings.backgroundColorLabel,
        orElse: () => _selectedBackgroundColor,
      );
      _widthController.text = '${_ensureEven(savedSettings.outputWidth)}';
      _heightController.text = '${_ensureEven(savedSettings.outputHeight)}';
    });
    _isRestoringSettings = false;
  }

  void _scheduleSettingsSave() {
    if (_isRestoringSettings) {
      return;
    }

    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistSettings());
    });
  }

  Future<void> _persistSettings() async {
    final width = _ensureEven(int.tryParse(_widthController.text) ?? 1080);
    final height = _ensureEven(int.tryParse(_heightController.text) ?? 1920);
    await _settingsStore.save(
      PersistedEditorSettings(
        rows: _rows,
        columns: _columns,
        borderThickness: _borderThickness,
        tileCornerRadius: _tileCornerRadius,
        includeClipLabelsInOutput: _includeClipLabelsInOutput,
        outputWidth: width,
        outputHeight: height,
        aspectLabel: _selectedAspect.label,
        resolutionLabel: _selectedResolution.label,
        borderColorLabel: _selectedBorderColor.label,
        backgroundColorLabel: _selectedBackgroundColor.label,
      ),
    );
  }

  void _setStateAndSave(VoidCallback update) {
    setState(update);
    _scheduleSettingsSave();
  }

  Future<void> _pickVideos() async {
    setState(() {
      _isImporting = true;
      _statusMessage = 'Selecting videos...';
    });

    try {
      final paths = await _dialogService.pickVideos();
      final newPaths = paths
          .where((path) => !_clips.any((clip) => clip.path == path))
          .toList();

      if (newPaths.isNotEmpty && mounted) {
        setState(() {
          for (final path in newPaths) {
            _clips.add(_placeholderClip(path));
            _loadingClipPaths.add(path);
            _clipErrors.remove(path);
            _slotAssignments[_nextAvailableSlot()] = path;
          }
          _statusMessage = 'Queued ${newPaths.length} video(s) for import.';
        });
      }

      for (final path in newPaths) {
        unawaited(_loadClip(path));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = paths.isEmpty
            ? 'No video was selected.'
            : newPaths.isEmpty
            ? 'Selected videos were already added.'
            : 'Added ${newPaths.length} video(s). Initializing previews...';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'File dialog failed: ${error.message ?? error.code}';
      });
    } on VideoExportException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Unable to load videos: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  void _removeClip(VideoClipInfo clip) {
    _controllers.remove(clip.path)?.dispose();
    setState(() {
      _clips.removeWhere((candidate) => candidate.path == clip.path);
      _slotAssignments.removeWhere((_, path) => path == clip.path);
      _loadingClipPaths.remove(clip.path);
      _clipErrors.remove(clip.path);
      _statusMessage = 'Removed ${clip.name}.';
    });
  }

  void _clearClips() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    setState(() {
      _clips.clear();
      _slotAssignments.clear();
      _loadingClipPaths.clear();
      _clipErrors.clear();
      _statusMessage = 'Cleared all videos.';
    });
  }

  void _applyResolutionPreset(ResolutionPreset preset) {
    final size = _sizeFromPreset(_selectedAspect, preset);
    _setStateAndSave(() {
      _selectedResolution = preset;
      _widthController.text = '${size.$1}';
      _heightController.text = '${size.$2}';
    });
  }

  void _applyAspectPreset(AspectRatioPreset preset) {
    final size = _sizeFromPreset(preset, _selectedResolution);
    _setStateAndSave(() {
      _selectedAspect = preset;
      _widthController.text = '${size.$1}';
      _heightController.text = '${size.$2}';
    });
  }

  void _autoLayout() {
    if (_clips.isEmpty) {
      return;
    }

    final columns = math.sqrt(_clips.length).ceil();
    final rows = (_clips.length / columns).ceil();
    _setStateAndSave(() {
      _columns = columns.clamp(1, 6);
      _rows = rows.clamp(1, 6);
      _statusMessage = 'Auto layout applied for ${_clips.length} videos.';
    });
  }

  Future<void> _export() async {
    if (_clips.isEmpty) {
      setState(() {
        _statusMessage = 'Add videos before exporting.';
      });
      return;
    }

    final options = _options;
    if (options.outputWidth <= 0 || options.outputHeight <= 0) {
      setState(() {
        _statusMessage = 'Resolution must be greater than zero.';
      });
      return;
    }

    final savePath = await _dialogService.pickSavePath();
    if (savePath == null || savePath.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Export cancelled.';
      });
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
      _statusMessage = 'Exporting collage video...';
    });

    try {
      await _exportService.exportCollage(
        slotClips: _slotClipsForExport(),
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
          setState(() {
            _exportProgress = progress.progress;
            _statusMessage =
                'Exporting collage video... $percent% • ${formatDuration(progress.processed)} / ${formatDuration(progress.total)}$speedText';
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _exportProgress = 1;
        _statusMessage = 'Export complete: $savePath';
      });
    } on VideoExportException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Export failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final slotClips = _slotClipsForExport();
    final scaledBorderThickness = options.scaledBorderThickness;
    final scaledTileCornerRadius = options.scaledTileCornerRadius;
    final overlayLabelScale = options.scaleFactor * 1.2;
    final activeCount = slotClips.length;
    final exportDuration = slotClips.fold<Duration>(
      Duration.zero,
      (current, entry) =>
          entry.clip.duration > current ? entry.clip.duration : current,
    );
    final previewCanvasWidth = options.outputWidth.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final previewCanvasHeight = options.outputHeight.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final previewCellAspectRatio = _previewCellAspectRatio(options);

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 370,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFD8D0C4))),
                  color: Color(0xFFFFFCF7),
                ),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: <Widget>[
                          Text(
                            'Perfect Video Collage',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 20),
                          _SectionCard(
                            title: 'Media',
                            subtitle:
                                '${_clips.length} loaded • capacity $_gridCapacity',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: <Widget>[
                                    FilledButton.icon(
                                      onPressed: _isImporting
                                          ? null
                                          : _pickVideos,
                                      icon: const Icon(
                                        Icons.video_library_outlined,
                                      ),
                                      label: Text(
                                        _isImporting
                                            ? 'Loading...'
                                            : 'Add Videos',
                                      ),
                                    ),
                                    IconButton.outlined(
                                      onPressed: _clips.isEmpty
                                          ? null
                                          : _autoLayout,
                                      tooltip: 'Auto Layout',
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(34, 34),
                                        maximumSize: const Size(34, 34),
                                      ),
                                      icon: const Icon(
                                        Icons.auto_fix_high,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton.outlined(
                                      onPressed: _clips.isEmpty
                                          ? null
                                          : _clearClips,
                                      tooltip: 'Clear',
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(34, 34),
                                        maximumSize: const Size(34, 34),
                                      ),
                                      icon: const Icon(
                                        Icons.cleaning_services_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_clips.isEmpty)
                                  const _EmptyListState()
                                else
                                  ..._clips.asMap().entries.map((entry) {
                                    final clip = entry.value;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: _ClipListTile(
                                        clip: clip,
                                        isUsed: _isClipVisibleInGrid(clip.path),
                                        isLoading: _loadingClipPaths.contains(
                                          clip.path,
                                        ),
                                        errorMessage: _clipErrors[clip.path],
                                        onRemove: () => _removeClip(clip),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Layout',
                            subtitle: 'Rows, columns, and border spacing',
                            child: Column(
                              children: <Widget>[
                                _StepperRow(
                                  label: 'Rows',
                                  value: _rows,
                                  onChanged: (value) =>
                                      _setStateAndSave(() => _rows = value),
                                ),
                                const SizedBox(height: 12),
                                _StepperRow(
                                  label: 'Columns',
                                  value: _columns,
                                  onChanged: (value) =>
                                      _setStateAndSave(() => _columns = value),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: <Widget>[
                                    const Expanded(
                                      child: Text('Border thickness'),
                                    ),
                                    Text('${_borderThickness.round()} px'),
                                  ],
                                ),
                                Slider(
                                  value: _borderThickness,
                                  min: 0,
                                  max: 48,
                                  divisions: 24,
                                  onChanged: (value) {
                                    _setStateAndSave(() {
                                      _borderThickness = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: <Widget>[
                                    const Expanded(
                                      child: Text('Tile corner radius'),
                                    ),
                                    Text('${_tileCornerRadius.round()} px'),
                                  ],
                                ),
                                Slider(
                                  value: _tileCornerRadius,
                                  min: 0,
                                  max: 48,
                                  divisions: 24,
                                  onChanged: (value) {
                                    _setStateAndSave(() {
                                      _tileCornerRadius = value;
                                    });
                                  },
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Include clip labels'),
                                  value: _includeClipLabelsInOutput,
                                  onChanged: (value) {
                                    _setStateAndSave(() {
                                      _includeClipLabelsInOutput = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 6),
                                _ColorSelector(
                                  label: 'Border',
                                  selected: _selectedBorderColor,
                                  onSelected: (choice) {
                                    _setStateAndSave(() {
                                      _selectedBorderColor = choice;
                                    });
                                  },
                                ),
                                const SizedBox(height: 12),
                                _ColorSelector(
                                  label: 'Background',
                                  selected: _selectedBackgroundColor,
                                  onSelected: (choice) {
                                    _setStateAndSave(() {
                                      _selectedBackgroundColor = choice;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Output',
                            subtitle: 'Aspect ratio and render size',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Aspect ratio',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _aspectPresets.map((preset) {
                                    return ChoiceChip(
                                      selected: identical(
                                        preset,
                                        _selectedAspect,
                                      ),
                                      label: Text(preset.label),
                                      onSelected: (_) =>
                                          _applyAspectPreset(preset),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Resolution preset',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _resolutionPresets.map((preset) {
                                    return ChoiceChip(
                                      selected: identical(
                                        preset,
                                        _selectedResolution,
                                      ),
                                      label: Text(preset.label),
                                      onSelected: (_) =>
                                          _applyResolutionPreset(preset),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: TextField(
                                        controller: _widthController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: <TextInputFormatter>[
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Width',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _heightController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: <TextInputFormatter>[
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Height',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'More than $_gridCapacity videos is supported. The current export uses the first $_gridCapacity clips in order.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF5A6270),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xFFE7D6C0),
                        border: Border(
                          top: BorderSide(color: Color(0xFFD8C9B5)),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Center(
                              child: SizedBox(
                                width: 240,
                                child: _ExportButton(
                                  onPressed: _isExporting ? null : _export,
                                  isExporting: _isExporting,
                                  progress: _exportProgress,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                'Output: ${options.outputWidth} × ${options.outputHeight} • ${options.rows}×${options.columns} grid • ${formatDuration(exportDuration)}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFFFFF8EE),
                      Color(0xFFF4E7D5),
                      Color(0xFFE7DDD0),
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            IconButton.filledTonal(
                              onPressed: _controllers.isEmpty
                                  ? null
                                  : () {
                                      unawaited(
                                        _setPreviewPlayback(!_isPreviewPlaying),
                                      );
                                    },
                              tooltip: _isPreviewPlaying
                                  ? 'Pause preview'
                                  : 'Play preview',
                              icon: Icon(
                                _isPreviewPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Preview',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.74),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFD0C5B5),
                                ),
                              ),
                              child: Text(
                                '${_clips.length} videos • $activeCount active in preview',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: previewCanvasWidth,
                                height: previewCanvasHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _selectedBorderColor.color,
                                    boxShadow: const <BoxShadow>[
                                      BoxShadow(
                                        color: Color(0x2A000000),
                                        blurRadius: 28,
                                        offset: Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      scaledBorderThickness,
                                    ),
                                    child: GridView.builder(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: _gridCapacity,
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: _columns,
                                            crossAxisSpacing:
                                                scaledBorderThickness,
                                            mainAxisSpacing:
                                                scaledBorderThickness,
                                            childAspectRatio:
                                                previewCellAspectRatio,
                                          ),
                                      itemBuilder: (context, index) {
                                        final clip = _clipForSlot(index);
                                        return DragTarget<int>(
                                          onWillAcceptWithDetails: (details) =>
                                              details.data != index,
                                          onAcceptWithDetails: (details) {
                                            _moveOrSwapPreviewSlot(
                                              details.data,
                                              index,
                                            );
                                          },
                                          builder: (context, candidateData, rejectedData) {
                                            return DropTarget(
                                              onDragEntered: (_) {
                                                if (_externalDropHoverSlotIndex !=
                                                    index) {
                                                  setState(() {
                                                    _externalDropHoverSlotIndex =
                                                        index;
                                                  });
                                                }
                                              },
                                              onDragExited: (_) {
                                                if (_externalDropHoverSlotIndex ==
                                                    index) {
                                                  setState(() {
                                                    _externalDropHoverSlotIndex =
                                                        null;
                                                  });
                                                }
                                              },
                                              onDragDone: (details) {
                                                if (_externalDropHoverSlotIndex ==
                                                    index) {
                                                  setState(() {
                                                    _externalDropHoverSlotIndex =
                                                        null;
                                                  });
                                                }
                                                unawaited(
                                                  _handleExternalDropToSlot(
                                                    index,
                                                    details.files,
                                                  ),
                                                );
                                              },
                                              child: _PreviewTile(
                                                clip: clip,
                                                controller: clip == null
                                                    ? null
                                                    : _controllers[clip.path],
                                                cornerRadius:
                                                    scaledTileCornerRadius,
                                                isLoading:
                                                    clip != null &&
                                                    _loadingClipPaths.contains(
                                                      clip.path,
                                                    ),
                                                errorMessage: clip == null
                                                    ? null
                                                    : _clipErrors[clip.path],
                                                onPickVideo: clip == null
                                                    ? () => _pickVideoForSlot(
                                                        index,
                                                      )
                                                    : null,
                                                index: index,
                                                backgroundColor:
                                                    _selectedBackgroundColor
                                                        .color,
                                                dragData: clip == null
                                                    ? null
                                                    : index,
                                                isDragTarget:
                                                    candidateData.isNotEmpty ||
                                                    _externalDropHoverSlotIndex ==
                                                        index,
                                                overlayLabelScale:
                                                    overlayLabelScale,
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.64),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD8D0C4)),
                          ),
                          child: Text(
                            _statusMessage ?? 'Ready',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF364152)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (int, int) _sizeFromPreset(
    AspectRatioPreset aspect,
    ResolutionPreset resolution,
  ) {
    final ratio = aspect.value;
    late final int width;
    late final int height;

    if (ratio >= 1) {
      height = resolution.shortEdge;
      width = (resolution.shortEdge * ratio).round();
    } else {
      width = resolution.shortEdge;
      height = (resolution.shortEdge / ratio).round();
    }

    return (_ensureEven(width), _ensureEven(height));
  }

  int _nextAvailableSlot() {
    var candidate = 0;
    while (_slotAssignments.containsKey(candidate)) {
      candidate++;
    }
    return candidate;
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
        entries.add(CollageSlotClip(slotIndex: slotIndex, clip: clip));
      }
    }
    return entries;
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

  bool _isClipVisibleInGrid(String path) {
    for (final entry in _slotAssignments.entries) {
      if (entry.value == path && entry.key < _gridCapacity) {
        return true;
      }
    }
    return false;
  }

  void _moveOrSwapPreviewSlot(int fromSlotIndex, int toSlotIndex) {
    if (fromSlotIndex == toSlotIndex) {
      return;
    }

    final sourcePath = _slotAssignments[fromSlotIndex];
    if (sourcePath == null) {
      return;
    }

    setState(() {
      final targetPath = _slotAssignments[toSlotIndex];
      _slotAssignments.remove(fromSlotIndex);

      if (targetPath == null) {
        _slotAssignments[toSlotIndex] = sourcePath;
        _statusMessage = 'Moved clip to slot ${toSlotIndex + 1}.';
        return;
      }

      _slotAssignments[toSlotIndex] = sourcePath;
      _slotAssignments[fromSlotIndex] = targetPath;
      _statusMessage =
          'Swapped slot ${fromSlotIndex + 1} with slot ${toSlotIndex + 1}.';
    });
  }

  Future<void> _handleExternalDropToSlot(
    int slotIndex,
    List<DropItem> items,
  ) async {
    final item = _firstSupportedVideoDropItem(items);
    if (item == null) {
      return;
    }

    final path = item.path;
    if (path.isEmpty) {
      return;
    }

    VideoClipInfo? existingClip;
    for (final clip in _clips) {
      if (clip.path == path) {
        existingClip = clip;
        break;
      }
    }
    if (existingClip != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _slotAssignments.removeWhere(
          (assignedSlotIndex, assignedPath) =>
              assignedSlotIndex != slotIndex && assignedPath == path,
        );
        _slotAssignments[slotIndex] = path;
        _statusMessage =
            'Assigned ${existingClip!.name} to slot ${slotIndex + 1}.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _clips.add(_placeholderClip(path));
      _slotAssignments[slotIndex] = path;
      _loadingClipPaths.add(path);
      _clipErrors.remove(path);
      _statusMessage = 'Queued ${p.basename(path)} for slot ${slotIndex + 1}.';
    });

    await _loadClip(path);
  }

  DropItem? _firstSupportedVideoDropItem(List<DropItem> items) {
    for (final item in items) {
      if (item is DropItemDirectory) {
        continue;
      }
      if (_isSupportedVideoPath(item.path)) {
        return item;
      }
    }
    return null;
  }

  bool _isSupportedVideoPath(String path) {
    return _supportedVideoExtensions.contains(p.extension(path).toLowerCase());
  }

  Future<void> _pickVideoForSlot(int slotIndex) async {
    final path = await _dialogService.pickSingleVideo();
    if (path == null || path.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'No video was selected.';
      });
      return;
    }

    if (_clips.any((clip) => clip.path == path)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Selected video was already added.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _clips.add(_placeholderClip(path));
      _slotAssignments[slotIndex] = path;
      _loadingClipPaths.add(path);
      _clipErrors.remove(path);
      _statusMessage = 'Queued 1 video for slot ${slotIndex + 1}.';
    });

    unawaited(_loadClip(path));
  }

  Future<void> _setPreviewPlayback(bool shouldPlay) async {
    final controllers = _controllers.values.toList(growable: false);

    setState(() {
      _isPreviewPlaying = shouldPlay;
      _statusMessage = shouldPlay
          ? 'Preview playback started.'
          : 'Preview playback paused.';
    });

    for (final controller in controllers) {
      if (!controller.value.isInitialized) {
        continue;
      }
      if (shouldPlay) {
        await controller.play();
      } else {
        await controller.pause();
      }
    }
  }

  int _ensureEven(int value) {
    if (value <= 0) {
      return 2;
    }
    return value.isEven ? value : value + 1;
  }

  VideoClipInfo _placeholderClip(String path) {
    return VideoClipInfo(
      path: path,
      name: path.split(Platform.pathSeparator).last,
      duration: Duration.zero,
      width: 0,
      height: 0,
    );
  }

  Future<void> _loadClip(String path) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(path));
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (_isPreviewPlaying) {
        await controller.play();
      } else {
        await controller.pause();
      }

      VideoClipInfo clip;
      try {
        clip = await _exportService.probeClip(path);
      } catch (_) {
        final value = controller.value;
        clip = VideoClipInfo(
          path: path,
          name: path.split(Platform.pathSeparator).last,
          duration: value.duration,
          width: value.size.width.round(),
          height: value.size.height.round(),
        );
      }

      if (!mounted) {
        controller.dispose();
        return;
      }

      final previousController = _controllers[path];
      setState(() {
        _controllers[path] = controller!;
        _loadingClipPaths.remove(path);
        _clipErrors.remove(path);
        final index = _clips.indexWhere((clip) => clip.path == path);
        if (index >= 0) {
          _clips[index] = clip;
        } else {
          _clips.add(clip);
        }
        _statusMessage = 'Loaded ${clip.name}.';
      });
      if (!identical(previousController, controller)) {
        previousController?.dispose();
      }
      controller = null;
    } catch (error) {
      controller?.dispose();
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingClipPaths.remove(path);
        _clipErrors[path] = '$error';
        _statusMessage =
            'Preview failed for ${path.split(Platform.pathSeparator).last}.';
      });
    }
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.onPressed,
    required this.isExporting,
    required this.progress,
  });

  final VoidCallback? onPressed;
  final bool isExporting;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(999);
    const idleColor = Color(0xFFA0563D);
    const trackColor = Color(0xFFD8C8B0);
    const progressColor = Color(0xFFA0563D);
    final foregroundColor = isExporting
        ? const Color(0xFF766658)
        : Colors.white;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percent = (clampedProgress * 100).round().clamp(0, 100);

    return SizedBox(
      height: 56,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(radius),
        child: Material(
          color: isExporting ? trackColor : idleColor,
          child: InkWell(
            onTap: onPressed,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (isExporting)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: clampedProgress,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: progressColor,
                          borderRadius: BorderRadius.all(radius),
                        ),
                      ),
                    ),
                  ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.file_download_outlined,
                        color: foregroundColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isExporting ? 'Exporting... $percent%' : 'Export MP4',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foregroundColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2D8CA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF697180)),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ClipListTile extends StatelessWidget {
  const _ClipListTile({
    required this.clip,
    required this.isUsed,
    required this.isLoading,
    required this.errorMessage,
    required this.onRemove,
  });

  final VideoClipInfo clip;
  final bool isUsed;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DED1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isUsed
                    ? const Color(0xFFFF7A59)
                    : const Color(0xFFCCD4DD),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                isUsed ? Icons.grid_view_rounded : Icons.pause_presentation,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    clip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _clipDetails,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: errorMessage == null
                          ? const Color(0xFF697180)
                          : const Color(0xFFB42318),
                    ),
                  ),
                  if (errorMessage != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      errorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB42318),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  String get _clipDetails {
    if (isLoading) {
      return 'Importing preview...';
    }
    if (errorMessage != null) {
      return 'Preview unavailable • export still possible';
    }
    if (clip.width == 0 || clip.height == 0) {
      return formatDuration(clip.duration);
    }
    return '${clip.width}×${clip.height} • ${formatDuration(clip.duration)}';
  }
}

class _PreviewTile extends StatelessWidget {
  static const Size _dragFeedbackSize = Size(240, 160);

  const _PreviewTile({
    required this.clip,
    required this.controller,
    required this.cornerRadius,
    required this.isLoading,
    required this.errorMessage,
    required this.onPickVideo,
    required this.index,
    required this.backgroundColor,
    required this.dragData,
    required this.isDragTarget,
    required this.overlayLabelScale,
  });

  final VideoClipInfo? clip;
  final VideoPlayerController? controller;
  final double cornerRadius;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onPickVideo;
  final int index;
  final Color backgroundColor;
  final int? dragData;
  final bool isDragTarget;
  final double overlayLabelScale;

  @override
  Widget build(BuildContext context) {
    final label = clip == null ? null : '#${index + 1} ${clip!.name}';
    final tile = _PreviewTileBody(
      clip: clip,
      controller: controller,
      cornerRadius: cornerRadius,
      isLoading: isLoading,
      errorMessage: errorMessage,
      onTap: onPickVideo,
      label: label,
      backgroundColor: backgroundColor,
      isDragTarget: isDragTarget,
      overlayLabelScale: overlayLabelScale,
    );

    if (dragData == null) {
      return tile;
    }

    return LongPressDraggable<int>(
      data: dragData!,
      delay: const Duration(milliseconds: 220),
      dragAnchorStrategy:
          (Draggable<Object> draggable, BuildContext context, Offset position) {
            return Offset(
              _dragFeedbackSize.width / 2,
              _dragFeedbackSize.height / 2,
            );
          },
      feedback: Transform.scale(
        scale: 1.04,
        child: SizedBox(
          width: _dragFeedbackSize.width,
          height: _dragFeedbackSize.height,
          child: Material(
            color: Colors.transparent,
            elevation: 24,
            shadowColor: const Color(0x55000000),
            borderRadius: BorderRadius.circular(cornerRadius + 8),
            child: _PreviewTileBody(
              clip: clip,
              controller: controller,
              cornerRadius: cornerRadius,
              isLoading: isLoading,
              errorMessage: errorMessage,
              onTap: null,
              label: label,
              backgroundColor: backgroundColor,
              isDragTarget: false,
              overlayLabelScale: overlayLabelScale,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.30, child: tile),
      child: tile,
    );
  }
}

class _PreviewTileBody extends StatelessWidget {
  const _PreviewTileBody({
    required this.clip,
    required this.controller,
    required this.cornerRadius,
    required this.isLoading,
    required this.errorMessage,
    required this.onTap,
    required this.label,
    required this.backgroundColor,
    required this.isDragTarget,
    required this.overlayLabelScale,
  });

  final VideoClipInfo? clip;
  final VideoPlayerController? controller;
  final double cornerRadius;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onTap;
  final String? label;
  final Color backgroundColor;
  final bool isDragTarget;
  final double overlayLabelScale;

  @override
  Widget build(BuildContext context) {
    final labelStyle = clipLabelStyleForOverlayScale(overlayLabelScale);

    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: isDragTarget ? 1.02 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cornerRadius),
          boxShadow: isDragTarget
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x26FF7A59),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cornerRadius),
          child: Material(
            color: backgroundColor,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (controller != null && controller!.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller!.value.size.width,
                        height: controller!.value.size.height,
                        child: VideoPlayer(controller!),
                      ),
                    )
                  else if (isLoading)
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            clip == null
                                ? Icons.add
                                : errorMessage == null
                                ? Icons.movie_creation_outlined
                                : Icons.warning_amber_rounded,
                            size: clip == null ? 68 : 34,
                            color: Colors.black.withValues(alpha: 0.28),
                          ),
                          if (errorMessage != null) ...<Widget>[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'Preview failed',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.black.withValues(
                                        alpha: 0.55,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (isDragTarget)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(cornerRadius),
                            border: Border.all(
                              color: const Color(0xFFFF7A59),
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (label != null)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: EdgeInsets.all(labelStyle.margin),
                        padding: EdgeInsets.symmetric(
                          horizontal: labelStyle.horizontalPadding,
                          vertical: labelStyle.verticalPadding,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.48),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: labelStyle.fontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSelector extends StatelessWidget {
  const _ColorSelector({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final ColorChoice selected;
  final ValueChanged<ColorChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label color', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        DropdownButtonFormField<ColorChoice>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFD7CEC2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFD7CEC2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF171A21), width: 2),
            ),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: _colorChoices.map((choice) {
            return DropdownMenuItem<ColorChoice>(
              value: choice,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: choice.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD7CEC2)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(choice.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (choice) {
            if (choice != null) {
              onSelected(choice);
            }
          },
        ),
      ],
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          onPressed: value < 6 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _EmptyListState extends StatelessWidget {
  const _EmptyListState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DED1)),
      ),
      child: Text(
        'Import .mp4, .mov, .m4v, .avi, or .mkv clips. The app supports more videos than the visible grid and exports the first rows×columns clips in order.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF697180)),
      ),
    );
  }
}
