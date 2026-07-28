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
  AspectRatioPreset(label: '9:21', widthFactor: 9, heightFactor: 21),
  AspectRatioPreset(label: '9:16', widthFactor: 9, heightFactor: 16),
  AspectRatioPreset(label: '4:5', widthFactor: 4, heightFactor: 5),
  AspectRatioPreset(label: '3:4', widthFactor: 3, heightFactor: 4),
  AspectRatioPreset(label: '1:1', widthFactor: 1, heightFactor: 1),
  AspectRatioPreset(label: '5:4', widthFactor: 5, heightFactor: 4),
  AspectRatioPreset(label: '4:3', widthFactor: 4, heightFactor: 3),
  AspectRatioPreset(label: '16:9', widthFactor: 16, heightFactor: 9),
  AspectRatioPreset(label: '21:9', widthFactor: 21, heightFactor: 9),
];

const _resolutionPresets = <ResolutionPreset>[
  ResolutionPreset(label: 'HD 720', shortEdge: 720),
  ResolutionPreset(label: 'Full HD 1080', shortEdge: 1080),
  ResolutionPreset(label: '2K 1440', shortEdge: 1440),
  ResolutionPreset(label: '4K 2160', shortEdge: 2160),
];
const ResolutionPreset _customResolutionPreset = ResolutionPreset(
  label: 'Custom',
  shortEdge: 0,
);
const _resolutionOptions = <ResolutionPreset>[
  ..._resolutionPresets,
  _customResolutionPreset,
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

const _supportedPhotoExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.heif',
};

final AspectRatioPreset _defaultAspectPreset = _aspectPresets.firstWhere(
  (preset) => preset.label == '16:9',
);
final ResolutionPreset _defaultResolutionPreset = _resolutionPresets[1];

ButtonStyle _sectionHeaderIconButtonStyle() {
  return IconButton.styleFrom(
    minimumSize: const Size(34, 34),
    maximumSize: const Size(34, 34),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
  );
}

final ColorChoice _defaultBorderColor = _colorChoices[0];
final ColorChoice _defaultBackgroundColor = _colorChoices[1];

const int _defaultRows = 1;
const int _defaultColumns = 3;
const double _defaultBorderThickness = 12;
const double _defaultTileCornerRadius = 12;
const double _defaultClipLabelFontSize = 16;
const double _defaultClipLabelPadding = 10;
const bool _defaultIncludeClipLabelsInOutput = true;
const ClipLabelDisplayMode _defaultClipLabelDisplayMode =
    ClipLabelDisplayMode.labelOnly;
const ClipLabelAlignment _defaultClipLabelAlignment =
    ClipLabelAlignment.topLeft;
const ClipLabelVisualStyle _defaultClipLabelVisualStyle =
    ClipLabelVisualStyle.dark;
const bool _defaultAppendDateTimeToExportName = true;
const PlayMode _defaultPlayMode = PlayMode.parallel;
const AudioMode _defaultAudioMode = AudioMode.firstClip;
const ExportDurationMode _defaultDurationMode = ExportDurationMode.longest;
const ClipFitMode _defaultFitMode = ClipFitMode.cropCenter;
const int _minOutputDimensionExclusive = 360;
const int _maxOutputDimensionExclusive = 4096;
const double _maxBorderThickness = 100;
const double _maxTileCornerRadius = 100;
const double _maxClipLabelFontSize = 50;
const double _maxClipLabelPadding = 48;

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
      title: 'Perfect Collage',
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
  final VideoExportService _exportService = VideoExportService();

  final List<VideoClipInfo> _clips = <VideoClipInfo>[];
  final Map<int, String> _slotAssignments = <int, String>{};
  final Map<String, VideoPlayerController> _controllers =
      <String, VideoPlayerController>{};
  final Set<String> _loadingClipPaths = <String>{};
  final Map<String, String> _clipErrors = <String, String>{};
  final GlobalKey _previewGridKey = GlobalKey();

  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late int _outputWidth;
  late int _outputHeight;
  Timer? _settingsSaveDebounce;
  Timer? _toastTimer;
  Timer? _parallelPreviewTimer;
  Timer? _sequentialPreviewTimer;
  Timer? _exportCompletionTimer;
  OverlayEntry? _toastOverlayEntry;
  bool _isRestoringSettings = false;
  bool _isSyncingSequentialPreview = false;
  int? _externalDropHoverSlotIndex;
  int? _lastPreviewProgressSecond;
  Duration _parallelPreviewElapsed = Duration.zero;
  DateTime? _parallelPreviewStartedAt;
  Duration _sequentialPreviewElapsed = Duration.zero;
  DateTime? _sequentialPreviewStartedAt;
  String? _activeSequentialClipPath;

  AspectRatioPreset _selectedAspect = _defaultAspectPreset;
  ResolutionPreset _selectedResolution = _defaultResolutionPreset;
  ColorChoice _selectedBorderColor = _defaultBorderColor;
  ColorChoice _selectedBackgroundColor = _defaultBackgroundColor;
  PlayMode _selectedPlayMode = _defaultPlayMode;
  AudioMode _selectedAudioMode = _defaultAudioMode;
  ExportDurationMode _selectedDurationMode = _defaultDurationMode;
  ClipFitMode _selectedFitMode = _defaultFitMode;

  int _rows = _defaultRows;
  int _columns = _defaultColumns;
  bool _isMediaSectionCollapsed = false;
  bool _isLayoutSectionCollapsed = false;
  bool _isLabelSectionCollapsed = false;
  bool _isOutputSectionCollapsed = false;
  double _borderThickness = _defaultBorderThickness;
  double _tileCornerRadius = _defaultTileCornerRadius;
  double _clipLabelFontSize = _defaultClipLabelFontSize;
  double _clipLabelPadding = _defaultClipLabelPadding;
  bool _includeClipLabelsInOutput = _defaultIncludeClipLabelsInOutput;
  ClipLabelDisplayMode _clipLabelDisplayMode = _defaultClipLabelDisplayMode;
  ClipLabelAlignment _clipLabelAlignment = _defaultClipLabelAlignment;
  ClipLabelVisualStyle _clipLabelVisualStyle = _defaultClipLabelVisualStyle;
  bool _appendDateTimeToExportName = _defaultAppendDateTimeToExportName;
  bool _isImporting = false;
  bool _isExporting = false;
  bool _showExportComplete = false;
  double _exportProgress = 0;
  bool _isPreviewPlaying = false;
  bool _isPreviewMuted = false;
  String? _statusMessage;
  List<ExportHistoryEntry> _exportHistory = const <ExportHistoryEntry>[];
  ExportHistoryEntry? _sessionLastExportEntry;
  String _lastExportDirectory = '';

  ExportHistoryEntry? get _lastExportEntry => _sessionLastExportEntry;

  @override
  void initState() {
    super.initState();
    final initialSize = _sizeFromPreset(_selectedAspect, _selectedResolution);
    _outputWidth = initialSize.$1;
    _outputHeight = initialSize.$2;
    _widthController = TextEditingController(text: '$_outputWidth');
    _heightController = TextEditingController(text: '$_outputHeight');
    unawaited(_restoreSettings());
    unawaited(_restoreExportHistory());
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    _toastTimer?.cancel();
    _parallelPreviewTimer?.cancel();
    _sequentialPreviewTimer?.cancel();
    _exportCompletionTimer?.cancel();
    _toastOverlayEntry?.remove();
    _widthController.dispose();
    _heightController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    for (final clip in _clips) {
      unawaited(_refreshClipMetadata(clip.path));
    }
  }

  ExportOptions get _options {
    return ExportOptions(
      rows: _rows,
      columns: _columns,
      outputWidth: _outputWidth,
      outputHeight: _outputHeight,
      borderThickness: _borderThickness,
      tileCornerRadius: _tileCornerRadius,
      backgroundColor: _selectedBackgroundColor,
      borderColor: _selectedBorderColor,
      fitMode: _selectedFitMode,
      includeClipLabelsInOutput: _includeClipLabelsInOutput,
      clipLabelDisplayMode: _clipLabelDisplayMode,
      clipLabelFontSize: _clipLabelFontSize,
      clipLabelAlignment: _clipLabelAlignment,
      clipLabelVisualStyle: _clipLabelVisualStyle,
      clipLabelPadding: _clipLabelPadding,
      playMode: _selectedPlayMode,
      audioMode: _selectedAudioMode,
      durationMode: _selectedDurationMode,
    );
  }

  int get _gridCapacity => _rows * _columns;

  bool get _isSequentialPlayMode => _selectedPlayMode == PlayMode.sequential;

  void _cancelExportCompletionTimer() {
    _exportCompletionTimer?.cancel();
    _exportCompletionTimer = null;
  }

  void _scheduleExportButtonReset() {
    _cancelExportCompletionTimer();
    _exportCompletionTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showExportComplete = false;
        _exportProgress = 0;
      });
    });
  }

  Future<void> _restoreSettings() async {
    final savedSettings = await _settingsStore.load();
    if (!mounted || savedSettings == null) {
      return;
    }

    _isRestoringSettings = true;
    setState(() {
      _rows = savedSettings.rows.clamp(1, 6);
      _columns = savedSettings.columns.clamp(1, 6);
      _isMediaSectionCollapsed = savedSettings.isMediaSectionCollapsed;
      _isLayoutSectionCollapsed = savedSettings.isLayoutSectionCollapsed;
      _isLabelSectionCollapsed = savedSettings.isLabelSectionCollapsed;
      _isOutputSectionCollapsed = savedSettings.isOutputSectionCollapsed;
      _borderThickness = savedSettings.borderThickness
          .clamp(0, _maxBorderThickness)
          .toDouble();
      _tileCornerRadius = savedSettings.tileCornerRadius
          .clamp(0, _maxTileCornerRadius)
          .toDouble();
      _clipLabelFontSize = savedSettings.clipLabelFontSize
          .clamp(8, _maxClipLabelFontSize)
          .toDouble();
      _clipLabelPadding = savedSettings.clipLabelPadding
          .clamp(0, _maxClipLabelPadding)
          .toDouble();
      _includeClipLabelsInOutput = savedSettings.includeClipLabelsInOutput;
      _clipLabelDisplayMode = savedSettings.clipLabelDisplayMode;
      _clipLabelAlignment = savedSettings.clipLabelAlignment;
      _clipLabelVisualStyle = savedSettings.clipLabelVisualStyle;
      _selectedFitMode = ClipFitMode.values.firstWhere(
        (mode) => mode.name == savedSettings.fitMode,
        orElse: () => _selectedFitMode,
      );
      _appendDateTimeToExportName = savedSettings.appendDateTimeToExportName;
      _selectedAspect = _aspectPresets.firstWhere(
        (preset) => preset.label == savedSettings.aspectLabel,
        orElse: () => _selectedAspect,
      );
      _selectedResolution = _resolutionOptions.firstWhere(
        (preset) => preset.label == savedSettings.resolutionLabel,
        orElse: () => _selectedResolution,
      );
      _selectedPlayMode = PlayMode.values.firstWhere(
        (mode) => mode.name == savedSettings.playMode,
        orElse: () => _selectedPlayMode,
      );
      _selectedAudioMode = AudioMode.values.firstWhere(
        (mode) => mode.name == savedSettings.audioMode,
        orElse: () => _selectedAudioMode,
      );
      _selectedDurationMode = ExportDurationMode.values.firstWhere(
        (mode) => mode.name == savedSettings.durationMode,
        orElse: () => _selectedDurationMode,
      );
      _lastExportDirectory = savedSettings.lastExportDirectory;
      _selectedBorderColor = _colorChoices.firstWhere(
        (choice) => choice.label == savedSettings.borderColorLabel,
        orElse: () => _selectedBorderColor,
      );
      _selectedBackgroundColor = _colorChoices.firstWhere(
        (choice) => choice.label == savedSettings.backgroundColorLabel,
        orElse: () => _selectedBackgroundColor,
      );
      _outputWidth = _ensureEven(savedSettings.outputWidth);
      _outputHeight = _ensureEven(savedSettings.outputHeight);
      _syncResolutionDraft(_outputWidth, _outputHeight);
    });
    _isRestoringSettings = false;
    unawaited(_syncPreviewPlaybackMode());
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

  Future<void> _restoreExportHistory() async {
    final history = await _settingsStore.loadExportHistory();
    if (!mounted) {
      return;
    }
    setState(() {
      _exportHistory = history;
    });
  }

  Future<void> _persistSettings() async {
    await _settingsStore.save(
      PersistedEditorSettings(
        rows: _rows,
        columns: _columns,
        isMediaSectionCollapsed: _isMediaSectionCollapsed,
        isLayoutSectionCollapsed: _isLayoutSectionCollapsed,
        isLabelSectionCollapsed: _isLabelSectionCollapsed,
        isOutputSectionCollapsed: _isOutputSectionCollapsed,
        borderThickness: _borderThickness,
        tileCornerRadius: _tileCornerRadius,
        clipLabelFontSize: _clipLabelFontSize,
        clipLabelAlignment: _clipLabelAlignment,
        clipLabelVisualStyle: _clipLabelVisualStyle,
        clipLabelPadding: _clipLabelPadding,
        includeClipLabelsInOutput: _includeClipLabelsInOutput,
        clipLabelDisplayMode: _clipLabelDisplayMode,
        fitMode: _selectedFitMode.name,
        outputWidth: _outputWidth,
        outputHeight: _outputHeight,
        aspectLabel: _selectedAspect.label,
        resolutionLabel: _selectedResolution.label,
        playMode: _selectedPlayMode.name,
        audioMode: _selectedAudioMode.name,
        durationMode: _selectedDurationMode.name,
        appendDateTimeToExportName: _appendDateTimeToExportName,
        lastExportDirectory: _lastExportDirectory,
        borderColorLabel: _selectedBorderColor.label,
        backgroundColorLabel: _selectedBackgroundColor.label,
      ),
    );
  }

  void _setStateAndSave(VoidCallback update) {
    setState(update);
    _scheduleSettingsSave();
  }

  void _toggleMediaSection() {
    _setStateAndSave(() {
      _isMediaSectionCollapsed = !_isMediaSectionCollapsed;
    });
  }

  void _toggleLayoutSection() {
    _setStateAndSave(() {
      _isLayoutSectionCollapsed = !_isLayoutSectionCollapsed;
    });
  }

  void _toggleLabelSection() {
    _setStateAndSave(() {
      _isLabelSectionCollapsed = !_isLabelSectionCollapsed;
    });
  }

  void _toggleOutputSection() {
    _setStateAndSave(() {
      _isOutputSectionCollapsed = !_isOutputSectionCollapsed;
    });
  }

  ResolutionPreset get _effectiveResolutionForSizing {
    if (_selectedResolution != _customResolutionPreset) {
      return _selectedResolution;
    }

    final shortEdge = math.min(_outputWidth, _outputHeight);
    return ResolutionPreset(
      label: _customResolutionPreset.label,
      shortEdge: _ensureEven(math.max(shortEdge, 2)),
    );
  }

  bool _isValidOutputDimension(int value) {
    return value > _minOutputDimensionExclusive &&
        value < _maxOutputDimensionExclusive;
  }

  bool _isValidOutputResolution(int width, int height) {
    return _isValidOutputDimension(width) && _isValidOutputDimension(height);
  }

  String get _outputResolutionRangeMessage {
    return 'Width and height must be greater than 360 and less than 4096.';
  }

  (int, int)? _parseResolutionDraft() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    final normalizedWidth = _ensureEven(width);
    final normalizedHeight = _ensureEven(height);
    if (!_isValidOutputResolution(normalizedWidth, normalizedHeight)) {
      return null;
    }

    return (normalizedWidth, normalizedHeight);
  }

  bool get _canApplyCustomResolution {
    final parsedSize = _parseResolutionDraft();
    if (parsedSize != null) {
      return parsedSize.$1 != _outputWidth ||
          parsedSize.$2 != _outputHeight ||
          _widthController.text != '$_outputWidth' ||
          _heightController.text != '$_outputHeight';
    }
    return false;
  }

  void _syncResolutionDraft(int width, int height) {
    _widthController.text = '$width';
    _heightController.text = '$height';
  }

  void _setAppliedResolution({
    required int width,
    required int height,
    ResolutionPreset? preset,
  }) {
    _outputWidth = _ensureEven(width);
    _outputHeight = _ensureEven(height);
    _syncResolutionDraft(_outputWidth, _outputHeight);
    if (preset != null) {
      _selectedResolution = preset;
    }
  }

  Future<void> _recordExportHistory(String path, ExportFormat format) async {
    final normalizedPath = _resolveHistoryPath(path);
    final entry = ExportHistoryEntry(
      path: normalizedPath,
      format: format.label,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final history = await _settingsStore.addExportHistoryEntry(entry);
    if (!mounted) {
      return;
    }
    setState(() {
      _exportHistory = history;
      _sessionLastExportEntry = entry;
    });
  }

  Future<void> _openExportHistoryEntry(ExportHistoryEntry entry) async {
    final resolvedPath = _resolveHistoryPath(entry.path);
    final file = File(resolvedPath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Export file no longer exists: $resolvedPath';
      });
      return;
    }

    try {
      final result = await Process.run('open', <String>[resolvedPath]);
      if (result.exitCode != 0 && mounted) {
        setState(() {
          _statusMessage = 'Unable to open export: $resolvedPath';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Unable to open export: $resolvedPath';
      });
    }
  }

  Future<void> _openLastExport() async {
    final lastExportEntry = _lastExportEntry;
    if (lastExportEntry == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'No export history yet.';
      });
      return;
    }
    await _openExportHistoryEntry(lastExportEntry);
  }

  Future<void> _openExportHistoryFolder(ExportHistoryEntry entry) async {
    final resolvedPath = _resolveHistoryPath(entry.path);
    final file = File(resolvedPath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Export file no longer exists: $resolvedPath';
      });
      return;
    }

    final directoryPath = p.dirname(resolvedPath);
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Export folder no longer exists: $directoryPath';
      });
      return;
    }

    try {
      final result = await Process.run('open', <String>['-R', resolvedPath]);
      if (result.exitCode != 0 && mounted) {
        setState(() {
          _statusMessage = 'Unable to open folder: $directoryPath';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Unable to open folder: $directoryPath';
      });
    }
  }

  String _resolveHistoryPath(String path) {
    if (p.isAbsolute(path)) {
      return p.normalize(path);
    }
    return p.normalize(p.absolute(path));
  }

  Future<void> _showExportHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Recent Exports'),
          content: SizedBox(
            width: 520,
            child: _exportHistory.isEmpty
                ? const Text('No recent exports.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _exportHistory.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _exportHistory[index];
                      final exists = File(entry.path).existsSync();
                      return ListTile(
                        enabled: exists,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          p.basename(entry.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entry.format} • ${_formatHistoryTimestamp(entry.timestampMillis)}\n${entry.path}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Open folder',
                              onPressed: !exists
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop();
                                      unawaited(
                                        _openExportHistoryFolder(entry),
                                      );
                                    },
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                            IconButton(
                              tooltip: 'Open file',
                              onPressed: !exists
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop();
                                      unawaited(_openExportHistoryEntry(entry));
                                    },
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                          ],
                        ),
                        onTap: !exists
                            ? null
                            : () {
                                Navigator.of(dialogContext).pop();
                                unawaited(_openExportHistoryEntry(entry));
                              },
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    _toastOverlayEntry?.remove();

    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
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
    _toastTimer = Timer(const Duration(seconds: 1), () {
      _toastOverlayEntry?.remove();
      _toastOverlayEntry = null;
      _toastTimer = null;
    });
  }

  String _defaultClipNameForPath(String path) {
    return p.basenameWithoutExtension(path);
  }

  String _suggestedExportFileName(ExportFormat format) {
    if (!_appendDateTimeToExportName) {
      return format.suggestedFileName;
    }
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final extension = format == ExportFormat.jpg ? 'jpg' : 'mp4';
    return 'pfc_export_$timestamp.$extension';
  }

  Future<void> _pickMedia() async {
    setState(() {
      _isImporting = true;
      _statusMessage = 'Selecting media...';
    });

    try {
      final selections = await _dialogService.pickMedia();
      final paths = selections
          .map((selection) => selection.path)
          .toList(growable: false);
      final selectionByPath = <String, PickedMediaFile>{
        for (final selection in selections) selection.path: selection,
      };
      final existingPaths = paths
          .where((path) => _clips.any((clip) => clip.path == path))
          .toList(growable: false);
      final newPaths = paths
          .where((path) => !_clips.any((clip) => clip.path == path))
          .toList();

      if (newPaths.isNotEmpty && mounted) {
        setState(() {
          for (final path in newPaths) {
            final initialClip = selectionByPath[path]?.clipInfo;
            _clips.add(initialClip ?? _placeholderClip(path));
            _loadingClipPaths.add(path);
            _clipErrors.remove(path);
            _slotAssignments[_nextAvailableSlot()] = path;
          }
          _statusMessage =
              'Queued ${newPaths.length} media item(s) for import.';
        });
      }

      for (final path in newPaths) {
        unawaited(
          _loadClip(path, initialClip: selectionByPath[path]?.clipInfo),
        );
      }
      for (final path in existingPaths) {
        unawaited(_refreshClipMetadata(path));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = paths.isEmpty
            ? 'No media was selected.'
            : newPaths.isEmpty
            ? 'Refreshing selected media metadata...'
            : 'Added ${newPaths.length} media item(s). Initializing previews...';
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
        _statusMessage = 'Unable to load media: $error';
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
      _compactSlotAssignments();
      _backfillVisibleSlotsFromOverflow();
      _loadingClipPaths.remove(clip.path);
      _clipErrors.remove(clip.path);
      if (_controllers.isEmpty) {
        _isPreviewPlaying = false;
      }
      _statusMessage = 'Removed ${clip.name}.';
    });
    unawaited(_syncPreviewPlaybackMode());
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
    setState(() {
      _clips.clear();
      _slotAssignments.clear();
      _loadingClipPaths.clear();
      _clipErrors.clear();
      _isPreviewPlaying = false;
      _activeSequentialClipPath = null;
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
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset everything?'),
          content: const Text(
            'This will remove all loaded media and restore Layout, Label, and Output settings to their defaults. History and exported files will be kept.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset All'),
            ),
          ],
        );
      },
    );

    if (shouldReset == true && mounted) {
      await _resetAll();
    }
  }

  Future<void> _resetAll() async {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _parallelPreviewTimer?.cancel();
    _parallelPreviewTimer = null;
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = null;
    final defaultSize = _sizeFromPreset(
      _defaultAspectPreset,
      _defaultResolutionPreset,
    );

    setState(() {
      _clips.clear();
      _slotAssignments.clear();
      _loadingClipPaths.clear();
      _clipErrors.clear();
      _selectedAspect = _defaultAspectPreset;
      _selectedResolution = _defaultResolutionPreset;
      _selectedBorderColor = _defaultBorderColor;
      _selectedBackgroundColor = _defaultBackgroundColor;
      _selectedPlayMode = _defaultPlayMode;
      _selectedAudioMode = _defaultAudioMode;
      _selectedDurationMode = _defaultDurationMode;
      _selectedFitMode = _defaultFitMode;
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
      _activeSequentialClipPath = null;
      _externalDropHoverSlotIndex = null;
      _statusMessage = 'Everything reset to defaults.';
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
      _activeSequentialClipPath = null;
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
      setState(() {
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
        _activeSequentialClipPath = null;
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

  void _autoLayout() {
    if (_clips.isEmpty) {
      return;
    }

    final consideredClips = _clips.take(36).toList(growable: false);
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

    for (var rows = 1; rows <= 6; rows++) {
      for (var columns = 1; columns <= 6; columns++) {
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
      _statusMessage =
          'Auto layout picked ${resolvedChoice.rows}×${resolvedChoice.columns} • ${resolvedChoice.aspectPreset.label}.';
    });
  }

  Future<void> _export() async {
    if (_clips.isEmpty) {
      setState(() {
        _statusMessage = 'Add media before exporting.';
      });
      return;
    }

    final options = _options;
    final slotClips = _slotClipsForExport();
    final exportFormat = exportFormatForClips(slotClips);
    if (!_isValidOutputResolution(options.outputWidth, options.outputHeight)) {
      setState(() {
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
      setState(() {
        _statusMessage = 'Export cancelled.';
      });
      return;
    }

    var completedSuccessfully = false;
    setState(() {
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
          setState(() {
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
      setState(() {
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
      setState(() {
        _showExportComplete = false;
        _statusMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showExportComplete = false;
        _statusMessage = 'Export failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
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

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel export?'),
          content: const Text(
            'The export is still running. Do you want to cancel it?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep exporting'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel export'),
            ),
          ],
        );
      },
    );

    if (shouldCancel != true || !mounted) {
      return;
    }

    setState(() {
      _statusMessage = 'Cancelling export...';
    });
    await _exportService.cancelActiveExport();
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final slotClips = _slotClipsForExport();
    final scaledBorderThickness = options.scaledBorderThickness;
    final scaledTileCornerRadius = options.scaledTileCornerRadius;
    final overlayLabelScale = options.scaleFactor * 1.2;
    final exportFormat = exportFormatForClips(slotClips);
    final resolvedExportFormat = slotClips.isEmpty ? null : exportFormat;
    final hasPreviewMotion = slotClips.any((entry) => entry.clip.isVideo);
    final exportDuration = exportDurationForClips(
      slotClips,
      _selectedDurationMode,
      _selectedPlayMode,
    );
    final previewPosition = _currentPreviewDisplayElapsed(exportDuration);
    final canStopPreview = hasPreviewMotion && previewPosition > Duration.zero;
    final playModeLabel = _selectedPlayMode.label;
    final previewCanvasWidth = options.outputWidth.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final previewCanvasHeight = options.outputHeight.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final previewCellAspectRatio = _previewCellAspectRatio(options);
    final lastExportEntry = _lastExportEntry;
    final hasLastExport =
        lastExportEntry != null &&
        File(_resolveHistoryPath(lastExportEntry.path)).existsSync();

    return Scaffold(
      body: SafeArea(
        child: DropTarget(
          onDragExited: (_) {
            if (_externalDropHoverSlotIndex != null) {
              setState(() {
                _externalDropHoverSlotIndex = null;
              });
            }
          },
          onDragDone: (details) {
            unawaited(
              _handleExternalDrop(
                details.files,
                preferredSlotIndex: _externalDropHoverSlotIndex,
                globalPosition: details.globalPosition,
              ),
            );
          },
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
                        child: AbsorbPointer(
                          absorbing: _isExporting,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: _isExporting ? 0.58 : 1,
                            child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: const <BoxShadow>[
                                          BoxShadow(
                                            color: Color(0x22000000),
                                            blurRadius: 14,
                                            offset: Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.asset(
                                          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Perfect Collage',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.outlined(
                                      onPressed: _isImporting
                                          ? null
                                          : () => unawaited(_confirmResetAll()),
                                      tooltip: 'Reset all',
                                      style: _sectionHeaderIconButtonStyle(),
                                      icon: const Icon(
                                        Icons.restart_alt_rounded,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _SectionCard(
                                  title: 'Media',
                                  subtitle:
                                      '${_clips.length} loaded • capacity $_gridCapacity',
                                  isCollapsed: _isMediaSectionCollapsed,
                                  onToggle: _toggleMediaSection,
                                  action: IconButton.outlined(
                                    onPressed: _clips.isEmpty
                                        ? null
                                        : () => unawaited(_confirmClearClips()),
                                    tooltip: 'Reset media',
                                    style: _sectionHeaderIconButtonStyle(),
                                    icon: const Icon(
                                      Icons.cleaning_services_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: FilledButton.icon(
                                                onPressed: _isImporting
                                                    ? null
                                                    : _pickMedia,
                                                icon: const Icon(
                                                  Icons.video_library_outlined,
                                                ),
                                                label: Text(
                                                  _isImporting
                                                      ? 'Loading...'
                                                      : 'Add Media',
                                                ),
                                              ),
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
                                              controller:
                                                  _controllers[clip.path],
                                              isUsed: _isClipVisibleInGrid(
                                                clip.path,
                                              ),
                                              isLoading: _loadingClipPaths
                                                  .contains(clip.path),
                                              errorMessage:
                                                  _clipErrors[clip.path],
                                              onTap: () => unawaited(
                                                _toggleClipActive(clip),
                                              ),
                                              onEditLabel: () => unawaited(
                                                _editClipTitle(clip),
                                              ),
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
                                  subtitle:
                                      'Aspect ratio, rows, columns, and styling',
                                  isCollapsed: _isLayoutSectionCollapsed,
                                  onToggle: _toggleLayoutSection,
                                  action: IconButton.outlined(
                                    onPressed: _resetLayoutDefaults,
                                    tooltip: 'Reset layout defaults',
                                    style: _sectionHeaderIconButtonStyle(),
                                    icon: const Icon(Icons.refresh, size: 18),
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      _SelectionDropdown<AspectRatioPreset>(
                                        label: 'Aspect ratio',
                                        selected: _selectedAspect,
                                        options: _aspectPresets,
                                        itemLabel: (preset) => preset.label,
                                        itemBuilder: (preset) =>
                                            _AspectRatioDropdownItem(
                                              preset: preset,
                                            ),
                                        onSelected: _applyAspectPreset,
                                      ),
                                      const SizedBox(height: 16),
                                      _StepperRow(
                                        label: 'Rows',
                                        value: _rows,
                                        onChanged: (value) => _setStateAndSave(
                                          () {
                                            _rows = value;
                                            _backfillVisibleSlotsFromOverflow();
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _StepperRow(
                                        label: 'Columns',
                                        value: _columns,
                                        onChanged: (value) => _setStateAndSave(
                                          () {
                                            _columns = value;
                                            _backfillVisibleSlotsFromOverflow();
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Text(
                                              'Border thickness',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                          ),
                                          Text(
                                            '${_borderThickness.round()} px',
                                          ),
                                        ],
                                      ),
                                      Slider(
                                        value: _borderThickness,
                                        min: 0,
                                        max: _maxBorderThickness,
                                        divisions: 50,
                                        onChanged: (value) {
                                          _setStateAndSave(() {
                                            _borderThickness = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Text(
                                              'Tile corner radius',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                          ),
                                          Text(
                                            '${_tileCornerRadius.round()} px',
                                          ),
                                        ],
                                      ),
                                      Slider(
                                        value: _tileCornerRadius,
                                        min: 0,
                                        max: _maxTileCornerRadius,
                                        divisions: 50,
                                        onChanged: (value) {
                                          _setStateAndSave(() {
                                            _tileCornerRadius = value;
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
                                      const SizedBox(height: 12),
                                      _SelectionDropdown<ClipFitMode>(
                                        label: 'Fit mode',
                                        selected: _selectedFitMode,
                                        options: ClipFitMode.values,
                                        itemLabel: (mode) => mode.label,
                                        itemBuilder: (mode) =>
                                            _ClipFitModeDropdownItem(
                                              mode: mode,
                                            ),
                                        onSelected: (mode) {
                                          _setStateAndSave(() {
                                            _selectedFitMode = mode;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Label',
                                  subtitle: 'Label display settings',
                                  isCollapsed: _isLabelSectionCollapsed,
                                  onToggle: _toggleLabelSection,
                                  action: IconButton.outlined(
                                    onPressed: _resetLabelDefaults,
                                    tooltip: 'Reset label defaults',
                                    style: _sectionHeaderIconButtonStyle(),
                                    icon: const Icon(Icons.refresh, size: 18),
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Show clip labels'),
                                        value: _includeClipLabelsInOutput,
                                        onChanged: (value) {
                                          _setStateAndSave(() {
                                            _includeClipLabelsInOutput = value;
                                          });
                                        },
                                      ),
                                      if (_includeClipLabelsInOutput) ...<
                                        Widget
                                      >[
                                        const SizedBox(height: 4),
                                        _SelectionDropdown<ClipLabelAlignment>(
                                          label: 'Clip label position',
                                          selected: _clipLabelAlignment,
                                          options: ClipLabelAlignment.values,
                                          itemLabel: (alignment) =>
                                              alignment.label,
                                          itemBuilder: (alignment) =>
                                              _ClipLabelAlignmentDropdownItem(
                                                alignment: alignment,
                                              ),
                                          onSelected: (alignment) {
                                            _setStateAndSave(() {
                                              _clipLabelAlignment = alignment;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _SelectionDropdown<
                                          ClipLabelVisualStyle
                                        >(
                                          label: 'Clip label style',
                                          selected: _clipLabelVisualStyle,
                                          options: ClipLabelVisualStyle.values,
                                          itemLabel: (style) => style.label,
                                          itemBuilder: (style) =>
                                              _ClipLabelStyleDropdownItem(
                                                style: style,
                                              ),
                                          onSelected: (style) {
                                            _setStateAndSave(() {
                                              _clipLabelVisualStyle = style;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(
                                                'Clip label font size',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                            Text(
                                              '${_clipLabelFontSize.round()} px',
                                            ),
                                          ],
                                        ),
                                        Slider(
                                          value: _clipLabelFontSize,
                                          min: 8,
                                          max: _maxClipLabelFontSize,
                                          divisions: 42,
                                          onChanged: (value) {
                                            _setStateAndSave(() {
                                              _clipLabelFontSize = value;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(
                                                'Clip label padding',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                            Text(
                                              '${_clipLabelPadding.round()} px',
                                            ),
                                          ],
                                        ),
                                        Slider(
                                          value: _clipLabelPadding,
                                          min: 0,
                                          max: _maxClipLabelPadding,
                                          divisions: 48,
                                          onChanged: (value) {
                                            _setStateAndSave(() {
                                              _clipLabelPadding = value;
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Output',
                                  subtitle: '$playModeLabel mode',
                                  isCollapsed: _isOutputSectionCollapsed,
                                  onToggle: _toggleOutputSection,
                                  action: IconButton.outlined(
                                    onPressed: () =>
                                        unawaited(_resetOutputDefaults()),
                                    tooltip: 'Reset output defaults',
                                    style: _sectionHeaderIconButtonStyle(),
                                    icon: const Icon(Icons.refresh, size: 18),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      _SelectionDropdown<PlayMode>(
                                        label: 'Play mode',
                                        selected: _selectedPlayMode,
                                        options: PlayMode.values,
                                        itemLabel: (mode) => mode.label,
                                        itemBuilder: (mode) =>
                                            _PlayModeDropdownItem(mode: mode),
                                        onSelected: (mode) {
                                          unawaited(
                                            _handlePlayModeSelected(mode),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      if (!_isSequentialPlayMode) ...<Widget>[
                                        _SelectionDropdown<AudioMode>(
                                          label: 'Audio',
                                          selected: _selectedAudioMode,
                                          options: AudioMode.values,
                                          itemLabel: (mode) => mode.label,
                                          itemBuilder: (mode) =>
                                              _AudioModeDropdownItem(
                                                mode: mode,
                                              ),
                                          onSelected: (mode) {
                                            _setStateAndSave(() {
                                              _selectedAudioMode = mode;
                                            });
                                            unawaited(
                                              _syncPreviewPlaybackMode(),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        _SelectionDropdown<ExportDurationMode>(
                                          label: 'Duration',
                                          selected: _selectedDurationMode,
                                          options: ExportDurationMode.values,
                                          itemLabel: (mode) => mode.label,
                                          itemBuilder: (mode) =>
                                              _ExportDurationDropdownItem(
                                                mode: mode,
                                              ),
                                          onSelected: (mode) {
                                            _setStateAndSave(() {
                                              _selectedDurationMode = mode;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      _SelectionDropdown<ResolutionPreset>(
                                        label: 'Resolution',
                                        selected: _selectedResolution,
                                        options: _resolutionOptions,
                                        itemLabel: (preset) => preset.label,
                                        onSelected: _applyResolutionPreset,
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: TextField(
                                              controller: _widthController,
                                              onChanged: (_) => setState(() {}),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters:
                                                  <TextInputFormatter>[
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
                                              onChanged: (_) => setState(() {}),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters:
                                                  <TextInputFormatter>[
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                  ],
                                              decoration: const InputDecoration(
                                                labelText: 'Height',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          IconButton.filledTonal(
                                            tooltip: 'Apply custom resolution',
                                            onPressed: _canApplyCustomResolution
                                                ? _applyCustomResolution
                                                : null,
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(34, 34),
                                              maximumSize: const Size(34, 34),
                                              shape: const CircleBorder(),
                                              padding: EdgeInsets.zero,
                                            ),
                                            icon: const Icon(
                                              Icons.check_rounded,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Add datetime to filename',
                                        ),
                                        value: _appendDateTimeToExportName,
                                        onChanged: (value) {
                                          _setStateAndSave(() {
                                            _appendDateTimeToExportName = value;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFFDBC29F),
                          border: Border(
                            top: BorderSide(color: Color(0xFFCDAF86)),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: IconButton(
                                        onPressed: _isExporting
                                            ? null
                                            : _showExportHistory,
                                        tooltip: 'History',
                                        icon: const Icon(Icons.history_rounded),
                                        color: const Color(0xFF6A452D),
                                        iconSize: 24,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: _ExportButton(
                                      onPressed: () => unawaited(
                                        _handleExportButtonPressed(),
                                      ),
                                      isExporting: _isExporting,
                                      showCompleted: _showExportComplete,
                                      progress: _exportProgress,
                                      exportFormat: resolvedExportFormat,
                                    ),
                                  ),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        onPressed:
                                            _isExporting || !hasLastExport
                                            ? null
                                            : () =>
                                                  unawaited(_openLastExport()),
                                        tooltip: hasLastExport
                                            ? 'Last export'
                                            : 'No last export yet',
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                        ),
                                        color: const Color(0xFF6A452D),
                                        iconSize: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  exportFormat == ExportFormat.jpg
                                      ? '${options.outputWidth}x${options.outputHeight} • ${options.rows}×${options.columns} grid • ${options.fitMode.label} • $playModeLabel'
                                      : '${options.outputWidth}x${options.outputHeight} • ${options.rows}×${options.columns} grid • ${options.fitMode.label} • $playModeLabel • ${formatDuration(exportDuration)}',
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
                child: AbsorbPointer(
                  absorbing: _isExporting,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _isExporting ? 0.58 : 1,
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
                                  Text(
                                    'Preview',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 12),
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
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.74,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFFD0C5B5),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        IconButton(
                                          onPressed: !hasPreviewMotion
                                              ? null
                                              : () {
                                                  unawaited(
                                                    _setPreviewPlayback(
                                                      !_isPreviewPlaying,
                                                    ),
                                                  );
                                                },
                                          tooltip: !hasPreviewMotion
                                              ? 'Preview playback unavailable for photos only'
                                              : _isPreviewPlaying
                                              ? 'Pause preview'
                                              : 'Play preview',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 24,
                                          splashRadius: 16,
                                          icon: Icon(
                                            _isPreviewPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: !canStopPreview
                                              ? null
                                              : () {
                                                  unawaited(
                                                    _stopPreviewPlayback(),
                                                  );
                                                },
                                          tooltip: 'Reset preview to start',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 23,
                                          splashRadius: 16,
                                          icon: const Icon(Icons.refresh),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: _clips.isEmpty
                                              ? null
                                              : () {
                                                  unawaited(
                                                    _togglePreviewMute(),
                                                  );
                                                },
                                          tooltip: _isPreviewMuted
                                              ? 'Unmute preview'
                                              : 'Mute preview',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 22,
                                          splashRadius: 16,
                                          icon: Icon(
                                            _isPreviewMuted
                                                ? Icons.volume_off_rounded
                                                : Icons.volume_up_rounded,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${formatDuration(previewPosition)} / ${formatDuration(exportDuration)}',
                                          style: (() {
                                            final baseStyle = Theme.of(
                                              context,
                                            ).textTheme.bodyMedium;
                                            final baseFontSize =
                                                baseStyle?.fontSize ?? 14;
                                            return baseStyle?.copyWith(
                                              fontSize: baseFontSize * 1.17,
                                              fontFeatures: const <FontFeature>[
                                                FontFeature.tabularFigures(),
                                              ],
                                            );
                                          })(),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
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
                                          child: SizedBox.expand(
                                            key: _previewGridKey,
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
                                                final clip = _clipForSlot(
                                                  index,
                                                );
                                                return DragTarget<int>(
                                                  onWillAcceptWithDetails:
                                                      (details) =>
                                                          details.data != index,
                                                  onAcceptWithDetails:
                                                      (details) {
                                                        _moveOrSwapPreviewSlot(
                                                          details.data,
                                                          index,
                                                        );
                                                      },
                                                  builder:
                                                      (
                                                        context,
                                                        candidateData,
                                                        rejectedData,
                                                      ) {
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
                                                          child: _PreviewTile(
                                                            clip: clip,
                                                            controller:
                                                                clip == null
                                                                ? null
                                                                : _controllers[clip
                                                                      .path],
                                                            cornerRadius:
                                                                scaledTileCornerRadius,
                                                            isLoading:
                                                                clip != null &&
                                                                _loadingClipPaths
                                                                    .contains(
                                                                      clip.path,
                                                                    ),
                                                            errorMessage:
                                                                clip == null
                                                                ? null
                                                                : _clipErrors[clip
                                                                      .path],
                                                            onPickMedia:
                                                                clip == null
                                                                ? () =>
                                                                      _pickMediaForSlot(
                                                                        index,
                                                                      )
                                                                : null,
                                                            index: index,
                                                            backgroundColor:
                                                                _selectedBackgroundColor
                                                                    .color,
                                                            dragData:
                                                                clip == null
                                                                ? null
                                                                : index,
                                                            showLabel:
                                                                _includeClipLabelsInOutput,
                                                            labelDisplayMode:
                                                                _clipLabelDisplayMode,
                                                            onEditLabel:
                                                                clip == null
                                                                ? null
                                                                : () => unawaited(
                                                                    _editClipTitle(
                                                                      clip,
                                                                    ),
                                                                  ),
                                                            isActiveLabel:
                                                                _isSequentialPlayMode &&
                                                                _isPreviewPlaying &&
                                                                _activeSequentialClipPath ==
                                                                    clip?.path,
                                                            clipLabelFontSize:
                                                                _clipLabelFontSize,
                                                            clipLabelAlignment:
                                                                _clipLabelAlignment,
                                                            clipLabelVisualStyle:
                                                                _clipLabelVisualStyle,
                                                            clipLabelPadding:
                                                                _clipLabelPadding,
                                                            fitMode:
                                                                _selectedFitMode,
                                                            isDragTarget:
                                                                candidateData
                                                                    .isNotEmpty ||
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
                              ),
                              const SizedBox(height: 16),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      final message = _statusMessage ?? 'Ready';
                                      Clipboard.setData(
                                        ClipboardData(text: message),
                                      );
                                      _showToast('Copied to clipboard');
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.64,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFD8D0C4),
                                        ),
                                      ),
                                      child: Text(
                                        _statusMessage ?? 'Ready',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF364152),
                                            ),
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
                  ),
                ),
              ),
            ],
          ),
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
        entries.add(CollageSlotClip(slotIndex: slotIndex, clip: clip));
      }
    }
    return entries;
  }

  List<CollageSlotClip> _sequentialVideoSlotClips() {
    return _slotClipsForExport()
        .where(
          (entry) => entry.clip.isVideo && entry.clip.duration > Duration.zero,
        )
        .toList(growable: false);
  }

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
    setState(() {});
  }

  Duration _lastFramePosition(VideoClipInfo clip) {
    final durationMs = clip.duration.inMilliseconds;
    if (durationMs <= 34) {
      return Duration.zero;
    }
    return Duration(milliseconds: durationMs - 34);
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

  Future<void> _syncParallelPreviewControllers() async {
    _sequentialPreviewTimer?.cancel();
    _sequentialPreviewTimer = null;
    _sequentialPreviewStartedAt = null;
    _sequentialPreviewElapsed = Duration.zero;
    if (_activeSequentialClipPath != null && mounted) {
      setState(() {
        _activeSequentialClipPath = null;
      });
    }

    final visibleSlotClips = _slotClipsForExport();
    final audibleClipPaths = _previewAudibleClipPaths(visibleSlotClips);
    final parallelClips = visibleSlotClips
        .where(
          (entry) => entry.clip.isVideo && entry.clip.duration > Duration.zero,
        )
        .toList(growable: false);
    final visibleVideoPaths = parallelClips
        .map((entry) => entry.clip.path)
        .toSet();

    if (parallelClips.isEmpty) {
      _parallelPreviewTimer?.cancel();
      _parallelPreviewTimer = null;
      _parallelPreviewStartedAt = null;
      _parallelPreviewElapsed = Duration.zero;
      if (_isPreviewPlaying && mounted) {
        setState(() {
          _isPreviewPlaying = false;
        });
      }
      await _pauseInactivePreviewControllers(const <String>{});
      return;
    }

    await _pauseInactivePreviewControllers(visibleVideoPaths);

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
        setState(() {
          _isPreviewPlaying = false;
          _statusMessage = 'Preview playback finished.';
        });
      }

      for (final entry in parallelClips) {
        final controller = _controllers[entry.clip.path];
        if (controller == null || !controller.value.isInitialized) {
          continue;
        }
        await controller.setLooping(false);
        await controller.setVolume(0);
        await controller.pause();
        final target = totalDuration >= entry.clip.duration
            ? _lastFramePosition(entry.clip)
            : totalDuration;
        await _seekControllerIfNeeded(controller, target);
      }
      return;
    }

    for (final entry in parallelClips) {
      final controller = _controllers[entry.clip.path];
      if (controller == null || !controller.value.isInitialized) {
        continue;
      }
      final clip = entry.clip;
      final isClipFinished = elapsed >= clip.duration;
      final target = isClipFinished ? _lastFramePosition(clip) : elapsed;

      await controller.setLooping(false);
      await controller.setVolume(
        _previewVolumeForClip(
          clipPath: clip.path,
          audibleClipPaths: audibleClipPaths,
        ),
      );
      await _seekControllerIfNeeded(controller, target);
      if (_isPreviewPlaying && !isClipFinished) {
        await controller.play();
      } else {
        await controller.pause();
      }
    }
  }

  Future<void> _syncSequentialPreviewControllers() async {
    if (_isSyncingSequentialPreview || !mounted) {
      return;
    }
    _isSyncingSequentialPreview = true;
    try {
      final segments = _sequentialVideoSlotClips();
      final visibleSlotClips = _slotClipsForExport();
      final audibleClipPaths = _previewAudibleClipPaths(visibleSlotClips);
      final visibleVideoPaths = segments
          .map((entry) => entry.clip.path)
          .toSet();
      if (segments.isEmpty) {
        _sequentialPreviewTimer?.cancel();
        _sequentialPreviewTimer = null;
        _sequentialPreviewStartedAt = null;
        _sequentialPreviewElapsed = Duration.zero;
        if (_activeSequentialClipPath != null || _isPreviewPlaying) {
          setState(() {
            _activeSequentialClipPath = null;
            _isPreviewPlaying = false;
          });
        }
        for (final controller in _controllers.values) {
          if (!controller.value.isInitialized) {
            continue;
          }
          await controller.setVolume(0);
          await controller.pause();
        }
        return;
      }

      await _pauseInactivePreviewControllers(visibleVideoPaths);

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
          setState(() {
            _activeSequentialClipPath = null;
            _isPreviewPlaying = false;
            _statusMessage = 'Preview playback finished.';
          });
        }
        for (final entry in segments) {
          final controller = _controllers[entry.clip.path];
          if (controller == null || !controller.value.isInitialized) {
            continue;
          }
          await controller.setLooping(false);
          await controller.pause();
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
      final activeClipPath = activeEntry.clip.path;
      final activeOffset = remaining;
      final sequentialOrder = <String, int>{
        for (var index = 0; index < segments.length; index += 1)
          segments[index].clip.path: index,
      };

      if (_activeSequentialClipPath != activeClipPath && mounted) {
        setState(() {
          _activeSequentialClipPath = activeClipPath;
        });
      }

      for (final clip in _slotClipsForExport()) {
        if (!clip.clip.isVideo) {
          continue;
        }
        final controller = _controllers[clip.clip.path];
        if (controller == null || !controller.value.isInitialized) {
          continue;
        }

        await controller.setLooping(false);
        await controller.setVolume(
          _previewVolumeForClip(
            clipPath: clip.clip.path,
            audibleClipPaths: audibleClipPaths,
          ),
        );

        final clipOrder = sequentialOrder[clip.clip.path];
        if (clip.clip.path == activeClipPath) {
          await _seekControllerIfNeeded(controller, activeOffset);
          if (_isPreviewPlaying) {
            await controller.play();
          } else {
            await controller.pause();
          }
          continue;
        }

        await controller.pause();
        if (clipOrder != null && clipOrder < activeSegmentIndex) {
          await _seekControllerIfNeeded(
            controller,
            _lastFramePosition(clip.clip),
          );
        } else {
          await _seekControllerIfNeeded(controller, Duration.zero);
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

  Set<String> _previewAudibleClipPaths(List<CollageSlotClip> slotClips) {
    if (_isPreviewMuted || slotClips.isEmpty) {
      return const <String>{};
    }

    switch (_selectedAudioMode) {
      case AudioMode.firstClip:
        final clip = slotClips.first.clip;
        return clip.hasAudio ? <String>{clip.path} : const <String>{};
      case AudioMode.mixAll:
        return slotClips
            .where((entry) => entry.clip.hasAudio)
            .map((entry) => entry.clip.path)
            .toSet();
      case AudioMode.longestClip:
        var longestEntry = slotClips.first;
        for (final entry in slotClips.skip(1)) {
          if (entry.clip.duration > longestEntry.clip.duration) {
            longestEntry = entry;
          }
        }
        return longestEntry.clip.hasAudio
            ? <String>{longestEntry.clip.path}
            : const <String>{};
      case AudioMode.mute:
        return const <String>{};
    }
  }

  double _previewVolumeForClip({
    required String clipPath,
    required Set<String> audibleClipPaths,
  }) {
    if (!_isPreviewPlaying || !audibleClipPaths.contains(clipPath)) {
      return 0;
    }
    if (_selectedAudioMode == AudioMode.mixAll && audibleClipPaths.isNotEmpty) {
      return 1 / audibleClipPaths.length;
    }
    return 1;
  }

  Future<void> _pauseInactivePreviewControllers(
    Set<String> activeVisibleVideoPaths,
  ) async {
    for (final entry in _controllers.entries) {
      final controller = entry.value;
      if (!controller.value.isInitialized ||
          activeVisibleVideoPaths.contains(entry.key)) {
        continue;
      }
      await controller.setVolume(0);
      await controller.pause();
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

  bool _isClipVisibleInGrid(String path) {
    for (final entry in _slotAssignments.entries) {
      if (entry.value == path && entry.key < _gridCapacity) {
        return true;
      }
    }
    return false;
  }

  Future<void> _toggleClipActive(VideoClipInfo clip) async {
    if (_isClipVisibleInGrid(clip.path)) {
      setState(() {
        _slotAssignments.removeWhere((_, path) => path == clip.path);
        _slotAssignments[_nextOverflowSlot()] = clip.path;
        _statusMessage = 'Marked ${clip.name} as non-active.';
      });
      await _syncPreviewPlaybackMode();
      return;
    }

    final emptySlot = _firstEmptyVisibleSlot();
    if (emptySlot == null) {
      if (mounted) {
        setState(() {
          _statusMessage = 'No empty slots available.';
        });
      }
      _showToast('Grid is full.');
      return;
    }

    setState(() {
      _assignPathToSlot(clip.path, emptySlot);
      _statusMessage = 'Added ${clip.name} to slot ${emptySlot + 1}.';
    });
    await _syncPreviewPlaybackMode();
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
        _backfillVisibleSlotsFromOverflow();
        _statusMessage = 'Moved clip to slot ${toSlotIndex + 1}.';
        return;
      }

      _slotAssignments[toSlotIndex] = sourcePath;
      _slotAssignments[fromSlotIndex] = targetPath;
      _statusMessage =
          'Swapped slot ${fromSlotIndex + 1} with slot ${toSlotIndex + 1}.';
    });
    unawaited(_syncPreviewPlaybackMode());
  }

  Future<void> _handleExternalDropToSlot(
    int slotIndex,
    List<DropItem> items,
  ) async {
    final supportedPaths = _supportedMediaDropPaths(items);
    if (supportedPaths.isEmpty) {
      return;
    }

    if (supportedPaths.length > 1) {
      await _handleExternalMultiDrop(supportedPaths);
      return;
    }

    final path = supportedPaths.first;
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
        _replacePathInSlot(path, slotIndex);
        _statusMessage =
            'Replaced slot ${slotIndex + 1} with ${existingClip!.name}.';
      });
      unawaited(_syncPreviewPlaybackMode());
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _clips.add(_placeholderClip(path));
      _replacePathInSlot(path, slotIndex);
      _loadingClipPaths.add(path);
      _clipErrors.remove(path);
      _statusMessage =
          'Replacing slot ${slotIndex + 1} with ${p.basename(path)}.';
    });

    await _loadClip(path);
  }

  Future<void> _handleExternalDrop(
    List<DropItem> items, {
    required int? preferredSlotIndex,
    Offset? globalPosition,
  }) async {
    final slotIndex = globalPosition == null
        ? preferredSlotIndex
        : _slotIndexForGlobalDropPosition(globalPosition) ?? preferredSlotIndex;
    if (mounted && _externalDropHoverSlotIndex != null) {
      setState(() {
        _externalDropHoverSlotIndex = null;
      });
    }

    if (slotIndex != null) {
      await _handleExternalDropToSlot(slotIndex, items);
      return;
    }

    final supportedPaths = _supportedMediaDropPaths(items);
    if (supportedPaths.isEmpty) {
      return;
    }

    await _handleExternalMultiDrop(supportedPaths);
  }

  Future<void> _handleExternalMultiDrop(List<String> paths) async {
    final uniquePaths = <String>[];
    final seenPaths = <String>{};
    for (final path in paths) {
      if (path.isEmpty || !seenPaths.add(path)) {
        continue;
      }
      if (_clips.any((clip) => clip.path == path)) {
        continue;
      }
      uniquePaths.add(path);
    }

    final emptyVisibleSlotCount = Iterable<int>.generate(
      _gridCapacity,
    ).where((slotIndex) => !_slotAssignments.containsKey(slotIndex)).length;

    if (!mounted) {
      return;
    }

    if (uniquePaths.isEmpty) {
      setState(() {
        _statusMessage = 'Dropped media was already added.';
      });
      return;
    }

    setState(() {
      for (final path in uniquePaths) {
        _clips.add(_placeholderClip(path));
        _slotAssignments[_nextAvailableSlot()] = path;
        _loadingClipPaths.add(path);
        _clipErrors.remove(path);
      }
      final assignedVisibleCount = math.min(
        uniquePaths.length,
        emptyVisibleSlotCount,
      );
      _statusMessage = assignedVisibleCount == uniquePaths.length
          ? 'Queued ${uniquePaths.length} media item(s) into empty slots.'
          : 'Queued ${uniquePaths.length} media item(s). '
                '$assignedVisibleCount assigned to empty slot(s), '
                '${uniquePaths.length - assignedVisibleCount} kept in Media.';
    });

    for (final path in uniquePaths) {
      await _loadClip(path);
    }
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
      setState(() {
        _statusMessage = 'No media was selected.';
      });
      return;
    }

    if (_clips.any((clip) => clip.path == path)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Selected media was already added.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _clips.add(_placeholderClip(path));
      _assignPathToSlot(path, slotIndex);
      _loadingClipPaths.add(path);
      _clipErrors.remove(path);
      _statusMessage = 'Queued 1 media item for slot ${slotIndex + 1}.';
    });

    unawaited(_loadClip(path));
  }

  Future<void> _setPreviewPlayback(bool shouldPlay) async {
    final parallelPausePosition = !shouldPlay && !_isSequentialPlayMode
        ? _currentParallelPreviewElapsed()
        : null;
    final sequentialPausePosition = !shouldPlay && _isSequentialPlayMode
        ? _currentSequentialPreviewElapsed()
        : null;

    setState(() {
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
    setState(() {
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
    _activeSequentialClipPath = null;

    await _syncPreviewPlaybackMode();
  }

  Future<void> _togglePreviewMute() async {
    setState(() {
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

  VideoClipInfo _placeholderClip(String path) {
    return VideoClipInfo(
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

  Future<void> _loadClip(String path, {VideoClipInfo? initialClip}) async {
    if (_isSupportedPhotoPath(path)) {
      try {
        final clip = await _exportService.probeMedia(path);
        if (!mounted) {
          return;
        }

        _controllers.remove(path)?.dispose();
        setState(() {
          _loadingClipPaths.remove(path);
          _clipErrors.remove(path);
          final index = _clips.indexWhere((clip) => clip.path == path);
          if (index >= 0) {
            _clips[index] = clip.copyWith(name: _clips[index].name);
            _statusMessage = 'Loaded ${_clips[index].name}.';
          } else {
            _clips.add(clip);
            _statusMessage = 'Loaded ${clip.name}.';
          }
        });
        unawaited(_syncPreviewPlaybackMode());
      } catch (error) {
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
      return;
    }

    VideoPlayerController? controller;
    var probedClip = initialClip;
    try {
      if (probedClip == null) {
        try {
          probedClip = await _exportService.probeMedia(path);
          if (mounted) {
            setState(() {
              final index = _clips.indexWhere((clip) => clip.path == path);
              if (index >= 0) {
                _clips[index] = probedClip!.copyWith(name: _clips[index].name);
              }
            });
          }
        } catch (_) {}
      }

      controller = VideoPlayerController.file(File(path));
      await controller.initialize().timeout(const Duration(seconds: 12));
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

      final previousController = _controllers[path];
      setState(() {
        _controllers[path] = initializedController;
        _loadingClipPaths.remove(path);
        _clipErrors.remove(path);
        final index = _clips.indexWhere((clip) => clip.path == path);
        if (index >= 0) {
          _clips[index] = clip.copyWith(name: _clips[index].name);
          _statusMessage = 'Loaded ${_clips[index].name}.';
        } else {
          _clips.add(clip);
          _statusMessage = 'Loaded ${clip.name}.';
        }
      });
      if (!identical(previousController, controller)) {
        previousController?.dispose();
      }
      unawaited(_syncPreviewPlaybackMode());
      controller = null;
    } catch (error) {
      controller?.dispose();
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingClipPaths.remove(path);
        if (probedClip == null) {
          _clipErrors[path] = '$error';
          _statusMessage =
              'Preview failed for ${path.split(Platform.pathSeparator).last}.';
          return;
        }
        _clipErrors.remove(path);
        _statusMessage =
            'Loaded metadata for ${probedClip.name}, but preview failed.';
      });
    }
  }

  Future<void> _refreshClipMetadata(String path) async {
    if (_loadingClipPaths.contains(path)) {
      return;
    }

    final existingIndex = _clips.indexWhere((clip) => clip.path == path);
    if (existingIndex < 0) {
      return;
    }

    try {
      final refreshed = await _exportService.probeMedia(path);
      if (!mounted) {
        return;
      }

      setState(() {
        final currentIndex = _clips.indexWhere((clip) => clip.path == path);
        if (currentIndex < 0) {
          return;
        }
        final current = _clips[currentIndex];
        _clips[currentIndex] = refreshed.copyWith(name: current.name);
      });
    } catch (_) {
      // Keep the existing metadata if refresh fails.
    }
  }

  Future<void> _editClipTitle(VideoClipInfo clip) async {
    final visibleSlotClips = _slotClipsForExport();
    final showTwoClipPresets =
        visibleSlotClips.length == 2 &&
        visibleSlotClips.any((entry) => entry.clip.path == clip.path);

    final result = await showDialog<_ClipLabelEditResult>(
      context: context,
      builder: (dialogContext) {
        return _ClipLabelEditDialog(
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
          final clipPath = latestVisibleSlotClips[index].clip.path;
          final clipIndex = _clips.indexWhere(
            (entry) => entry.path == clipPath,
          );
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
      final index = _clips.indexWhere((entry) => entry.path == clip.path);
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

class _ClipLabelEditResult {
  const _ClipLabelEditResult({
    required this.displayMode,
    this.name,
    this.preset,
  });

  final String? name;
  final _TwoClipLabelPreset? preset;
  final ClipLabelDisplayMode displayMode;
}

class _ClipLabelEditDialog extends StatefulWidget {
  const _ClipLabelEditDialog({
    required this.initialLabel,
    required this.initialDisplayMode,
    required this.showTwoClipPresets,
  });

  final String initialLabel;
  final ClipLabelDisplayMode initialDisplayMode;
  final bool showTwoClipPresets;

  @override
  State<_ClipLabelEditDialog> createState() => _ClipLabelEditDialogState();
}

class _ClipLabelEditDialogState extends State<_ClipLabelEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _textController;
  late String _draftName;
  late ClipLabelDisplayMode _selectedDisplayMode;

  @override
  void initState() {
    super.initState();
    _draftName = widget.initialLabel;
    _selectedDisplayMode = widget.initialDisplayMode;
    _textController = TextEditingController(text: widget.initialLabel)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialLabel.length,
      );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _applySingleClipPreset(String preset) {
    Navigator.of(context).pop(
      _ClipLabelEditResult(name: preset, displayMode: _selectedDisplayMode),
    );
  }

  void _applyTwoClipPreset(_TwoClipLabelPreset preset) {
    Navigator.of(context).pop(
      _ClipLabelEditResult(preset: preset, displayMode: _selectedDisplayMode),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _ClipLabelEditResult(
        name: _draftName.trim(),
        displayMode: _selectedDisplayMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactPresetButtonStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: Theme.of(context).textTheme.bodyMedium,
    );

    return AlertDialog(
      title: const Text('Edit clip label'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Global label display',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Affects every clip in preview and export.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<ClipLabelDisplayMode>(
                  showSelectedIcon: false,
                  segments: ClipLabelDisplayMode.values
                      .map(
                        (mode) => ButtonSegment<ClipLabelDisplayMode>(
                          value: mode,
                          label: Text(mode.label),
                        ),
                      )
                      .toList(growable: false),
                  selected: <ClipLabelDisplayMode>{_selectedDisplayMode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedDisplayMode = selection.first;
                    });
                  },
                ),
                if (_selectedDisplayMode ==
                    ClipLabelDisplayMode.indexOnly) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    'Index only mode hides custom labels, so clip label editing is unavailable.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'This clip',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only updates the selected clip label. Label cannot be blank.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _textController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Clip label',
                      border: OutlineInputBorder(),
                      helperText: 'Required',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Clip label cannot be blank.';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setState(() {
                        _draftName = value;
                      });
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Single-clip presets',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _singleClipLabelPresetRows
                        .map((presetRow) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: presetRow
                                  .map((preset) {
                                    return OutlinedButton(
                                      style: compactPresetButtonStyle,
                                      onPressed: () =>
                                          _applySingleClipPreset(preset),
                                      child: Text(preset),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  if (widget.showTwoClipPresets) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Two-clip presets',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Global action for the two visible clips in the collage.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _twoClipLabelPresets
                          .map((preset) {
                            return OutlinedButton(
                              style: compactPresetButtonStyle,
                              onPressed: () => _applyTwoClipPreset(preset),
                              child: Text(
                                '${preset.firstLabel} / ${preset.secondLabel}',
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _TwoClipLabelPreset {
  const _TwoClipLabelPreset(this.firstLabel, this.secondLabel);

  final String firstLabel;
  final String secondLabel;
}

const List<_TwoClipLabelPreset> _twoClipLabelPresets = <_TwoClipLabelPreset>[
  _TwoClipLabelPreset('Before', 'After'),
  _TwoClipLabelPreset('Source', 'Target'),
  _TwoClipLabelPreset('Current', 'New'),
  _TwoClipLabelPreset('Input', 'Output'),
];

const List<List<String>> _singleClipLabelPresetRows = <List<String>>[
  <String>['Source', 'Before', 'Current', 'Input'],
  <String>['Target', 'After', 'New', 'Output', 'Result'],
];

String _formatHistoryTimestamp(int timestampMillis) {
  if (timestampMillis <= 0) {
    return 'Unknown time';
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
  final year = dateTime.year.toString().padLeft(4, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.onPressed,
    required this.isExporting,
    required this.showCompleted,
    required this.progress,
    required this.exportFormat,
  });

  final VoidCallback? onPressed;
  final bool isExporting;
  final bool showCompleted;
  final double progress;
  final ExportFormat? exportFormat;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(999);
    final sharedButtonColor = Theme.of(context).colorScheme.primary;
    const exportingBackground = Color(0xFFE7D6BF);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percent = (clampedProgress * 100).round().clamp(0, 100);
    final displayProgress = showCompleted
        ? 1.0
        : (isExporting ? clampedProgress : 0.0);
    final label = showCompleted
        ? 'Complete'
        : isExporting
        ? 'Exporting... $percent%'
        : exportFormat == null
        ? 'Export'
        : 'Export ${exportFormat!.label}';
    final icon = showCompleted
        ? Icons.check_rounded
        : isExporting
        ? Icons.autorenew_rounded
        : Icons.file_download_outlined;
    final backgroundColor = showCompleted
        ? sharedButtonColor
        : isExporting
        ? exportingBackground
        : sharedButtonColor;
    final showIcon = !isExporting || showCompleted;

    return SizedBox(
      height: 56,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(radius),
        child: Material(
          color: backgroundColor,
          child: InkWell(
            onTap: onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                border: isExporting && !showCompleted
                    ? null
                    : Border.all(color: sharedButtonColor),
                borderRadius: const BorderRadius.all(radius),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x1F5F2E1E),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
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
                          duration: const Duration(milliseconds: 240),
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
                        child: _ExportButtonContent(
                          icon: showIcon ? icon : null,
                          label: label,
                          color: Colors.white,
                        ),
                      ),
                      if (displayProgress > 0)
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: displayProgress,
                            child: Center(
                              child: _ExportButtonContent(
                                icon: showIcon ? icon : null,
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

class _ExportButtonContent extends StatelessWidget {
  const _ExportButtonContent({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData? icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 12),
        ],
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

enum _AutoLayoutOrientation { portrait, square, landscape }

class _AutoLayoutChoice {
  const _AutoLayoutChoice({
    required this.rows,
    required this.columns,
    required this.aspectPreset,
    required this.emptySlots,
    required this.averageVisibleFraction,
    required this.orientationMatches,
  });

  final int rows;
  final int columns;
  final AspectRatioPreset aspectPreset;
  final int emptySlots;
  final double averageVisibleFraction;
  final bool orientationMatches;

  bool isBetterThan(_AutoLayoutChoice other) {
    if (emptySlots != other.emptySlots) {
      return emptySlots < other.emptySlots;
    }
    final visibleDelta = averageVisibleFraction - other.averageVisibleFraction;
    if (visibleDelta.abs() > 0.0001) {
      return visibleDelta > 0;
    }
    if (orientationMatches != other.orientationMatches) {
      return orientationMatches;
    }
    final shapeDelta = (rows - columns).abs().compareTo(
      (other.rows - other.columns).abs(),
    );
    if (shapeDelta != 0) {
      return shapeDelta < 0;
    }
    return rows < other.rows;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.isCollapsed,
    required this.onToggle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final Widget? action;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!isCollapsed && action != null) ...<Widget>[
                  const SizedBox(width: 12),
                  action!,
                ],
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: onToggle,
                  tooltip: isCollapsed ? 'Expand section' : 'Collapse section',
                  style: _sectionHeaderIconButtonStyle(),
                  icon: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    tween: Tween<double>(
                      begin: 0,
                      end: isCollapsed ? -math.pi / 2 : 0,
                    ),
                    builder: (context, angle, child) {
                      return Transform.rotate(angle: angle, child: child);
                    },
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                heightFactor: isCollapsed ? 0 : 1,
                child: IgnorePointer(
                  ignoring: isCollapsed,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: isCollapsed ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF697180)),
                        ),
                        const SizedBox(height: 16),
                        child,
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
}

class _ClipListTile extends StatelessWidget {
  const _ClipListTile({
    required this.clip,
    required this.controller,
    required this.isUsed,
    required this.isLoading,
    required this.errorMessage,
    required this.onTap,
    required this.onEditLabel,
    required this.onRemove,
  });

  final VideoClipInfo clip;
  final VideoPlayerController? controller;
  final bool isUsed;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onTap;
  final VoidCallback onEditLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final itemBorderColor = isUsed
        ? const Color(0xFFFF7A59)
        : const Color(0xFFE7DED1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: itemBorderColor, width: isUsed ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildThumbnail(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              clip.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Edit clip label',
                            onPressed: onEditLabel,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            visualDensity: VisualDensity.compact,
                            iconSize: 15,
                            splashRadius: 14,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Colors.black45,
                            ),
                          ),
                        ],
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFFB42318)),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  height: 56,
                  child: Center(
                    child: IconButton(
                      tooltip: 'Remove',
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
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

  Widget _buildThumbnail() {
    const borderRadius = BorderRadius.all(Radius.circular(14));
    const inactiveBorderColor = Color(0xFFD6DCE4);
    final previewVideoSize = _previewVideoDisplaySize(
      clip: clip,
      controller: controller,
    );

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: inactiveBorderColor, width: 1.25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (controller != null &&
                controller!.value.isInitialized &&
                previewVideoSize != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewVideoSize.width,
                  height: previewVideoSize.height,
                  child: VideoPlayer(controller!),
                ),
              )
            else if (!isLoading && errorMessage == null && clip.isPhoto)
              Image.file(
                File(clip.path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildThumbnailFallback();
                },
              )
            else if (isLoading)
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else
              _buildThumbnailFallback(),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUsed ? const Color(0xFFFFF1EC) : const Color(0xFFF4F6F8),
      ),
      child: Center(
        child: Icon(
          errorMessage != null
              ? Icons.warning_amber_rounded
              : clip.isPhoto
              ? Icons.photo_outlined
              : Icons.movie_creation_outlined,
          size: 24,
          color: isUsed ? const Color(0xFFA0563D) : const Color(0xFF8C98A8),
        ),
      ),
    );
  }

  String get _clipDetails {
    final clipFormat = p
        .extension(clip.path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (isLoading) {
      return 'Importing preview...';
    }
    if (errorMessage != null) {
      return 'Preview unavailable • export still possible';
    }
    if (clip.width == 0 || clip.height == 0) {
      return clip.isPhoto
          ? clipFormat
          : '${formatDuration(clip.duration)} • $clipFormat';
    }
    if (clip.isPhoto) {
      return '${clip.width}×${clip.height} • $clipFormat';
    }
    return '${clip.width}×${clip.height} • ${formatDuration(clip.duration)} • $clipFormat';
  }
}

Size? _previewVideoDisplaySize({
  required VideoClipInfo? clip,
  required VideoPlayerController? controller,
}) {
  if (clip != null && clip.width > 0 && clip.height > 0) {
    return Size(clip.width.toDouble(), clip.height.toDouble());
  }

  if (controller != null && controller.value.isInitialized) {
    final size = controller.value.size;
    if (size.width > 0 && size.height > 0) {
      return size;
    }
  }

  return null;
}

class _PreviewTile extends StatelessWidget {
  static const Size _dragFeedbackFallbackSize = Size(240, 160);
  static const double _dragFeedbackMaxSide = 240;
  static const double _dragFeedbackMinSide = 120;

  const _PreviewTile({
    required this.clip,
    required this.controller,
    required this.cornerRadius,
    required this.isLoading,
    required this.errorMessage,
    required this.onPickMedia,
    required this.index,
    required this.backgroundColor,
    required this.dragData,
    required this.showLabel,
    required this.labelDisplayMode,
    required this.onEditLabel,
    required this.isActiveLabel,
    required this.clipLabelFontSize,
    required this.clipLabelAlignment,
    required this.clipLabelVisualStyle,
    required this.clipLabelPadding,
    required this.fitMode,
    required this.isDragTarget,
    required this.overlayLabelScale,
  });

  final VideoClipInfo? clip;
  final VideoPlayerController? controller;
  final double cornerRadius;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onPickMedia;
  final int index;
  final Color backgroundColor;
  final int? dragData;
  final bool showLabel;
  final ClipLabelDisplayMode labelDisplayMode;
  final VoidCallback? onEditLabel;
  final bool isActiveLabel;
  final double clipLabelFontSize;
  final ClipLabelAlignment clipLabelAlignment;
  final ClipLabelVisualStyle clipLabelVisualStyle;
  final double clipLabelPadding;
  final ClipFitMode fitMode;
  final bool isDragTarget;
  final double overlayLabelScale;

  Size _dragFeedbackSize() {
    final mediaSize = _previewVideoDisplaySize(
      clip: clip,
      controller: controller,
    );

    if (mediaSize == null || mediaSize.width <= 0 || mediaSize.height <= 0) {
      return _dragFeedbackFallbackSize;
    }

    final aspectRatio = mediaSize.width / mediaSize.height;
    if (aspectRatio >= 1) {
      return Size(
        _dragFeedbackMaxSide,
        (_dragFeedbackMaxSide / aspectRatio).clamp(
          _dragFeedbackMinSide,
          _dragFeedbackMaxSide,
        ),
      );
    }

    return Size(
      (_dragFeedbackMaxSide * aspectRatio).clamp(
        _dragFeedbackMinSide,
        _dragFeedbackMaxSide,
      ),
      _dragFeedbackMaxSide,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawLabel = !showLabel || clip == null
        ? null
        : buildClipLabelText(
            slotIndex: index,
            clipName: clip!.name,
            mode: labelDisplayMode,
          );
    final label = rawLabel == null || rawLabel.isEmpty ? null : rawLabel;
    final tile = _PreviewTileBody(
      clip: clip,
      controller: controller,
      cornerRadius: cornerRadius,
      isLoading: isLoading,
      errorMessage: errorMessage,
      onTap: onPickMedia,
      label: label,
      backgroundColor: backgroundColor,
      onLabelTap: onEditLabel,
      isActiveLabel: isActiveLabel,
      clipLabelFontSize: clipLabelFontSize,
      clipLabelAlignment: clipLabelAlignment,
      clipLabelVisualStyle: clipLabelVisualStyle,
      clipLabelPadding: clipLabelPadding,
      fitMode: fitMode,
      isDragTarget: isDragTarget,
      overlayLabelScale: overlayLabelScale,
    );

    if (dragData == null) {
      return tile;
    }

    final dragFeedbackSize = _dragFeedbackSize();

    return LongPressDraggable<int>(
      data: dragData!,
      delay: const Duration(milliseconds: 220),
      dragAnchorStrategy:
          (Draggable<Object> draggable, BuildContext context, Offset position) {
            return Offset(
              dragFeedbackSize.width / 2,
              dragFeedbackSize.height / 2,
            );
          },
      feedback: Transform.scale(
        scale: 1.04,
        child: SizedBox(
          width: dragFeedbackSize.width,
          height: dragFeedbackSize.height,
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
              label: null,
              backgroundColor: backgroundColor,
              onLabelTap: null,
              isActiveLabel: isActiveLabel,
              clipLabelFontSize: clipLabelFontSize,
              clipLabelAlignment: clipLabelAlignment,
              clipLabelVisualStyle: clipLabelVisualStyle,
              clipLabelPadding: clipLabelPadding,
              fitMode: fitMode,
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
    required this.onLabelTap,
    required this.isActiveLabel,
    required this.clipLabelFontSize,
    required this.clipLabelAlignment,
    required this.clipLabelVisualStyle,
    required this.clipLabelPadding,
    required this.fitMode,
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
  final VoidCallback? onLabelTap;
  final bool isActiveLabel;
  final double clipLabelFontSize;
  final ClipLabelAlignment clipLabelAlignment;
  final ClipLabelVisualStyle clipLabelVisualStyle;
  final double clipLabelPadding;
  final ClipFitMode fitMode;
  final bool isDragTarget;
  final double overlayLabelScale;

  @override
  Widget build(BuildContext context) {
    final previewVideoSize = _previewVideoDisplaySize(
      clip: clip,
      controller: controller,
    );
    final labelStyle = clipLabelStyleForOverlayScale(
      overlayLabelScale,
      baseFontSize: clipLabelFontSize,
      baseEdgePadding: clipLabelPadding,
      alignment: clipLabelAlignment,
      visualStyle: clipLabelVisualStyle,
    );
    final labelTextColor = isActiveLabel
        ? clipLabelHighlightedTextColor(clipLabelVisualStyle)
        : labelStyle.textColor;

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final emptyTileIconSize =
                      (constraints.biggest.shortestSide * 0.12).clamp(
                        24.0,
                        64.0,
                      );

                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (controller != null &&
                          controller!.value.isInitialized &&
                          previewVideoSize != null)
                        FittedBox(
                          fit: fitMode.previewFit,
                          child: SizedBox(
                            width: previewVideoSize.width,
                            height: previewVideoSize.height,
                            child: VideoPlayer(controller!),
                          ),
                        )
                      else if (clip?.isPhoto == true)
                        Positioned.fill(
                          child: Image.file(
                            File(clip!.path),
                            fit: fitMode.previewFit,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 34,
                                  color: Colors.black.withValues(alpha: 0.28),
                                ),
                              );
                            },
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
                                    ? clip!.isPhoto
                                          ? Icons.photo_outlined
                                          : Icons.movie_creation_outlined
                                    : Icons.warning_amber_rounded,
                                size: clip == null ? emptyTileIconSize : 34,
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
                                borderRadius: BorderRadius.circular(
                                  cornerRadius,
                                ),
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
                          alignment: clipLabelAlignment.previewAlignment,
                          child: Padding(
                            padding: labelStyle.margin,
                            child: MouseRegion(
                              cursor: onLabelTap == null
                                  ? MouseCursor.defer
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onLabelTap,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: labelStyle.horizontalPadding,
                                    vertical: labelStyle.verticalPadding,
                                  ),
                                  decoration: BoxDecoration(
                                    color: labelStyle.backgroundColor,
                                    borderRadius: BorderRadius.circular(
                                      labelStyle.cornerRadius,
                                    ),
                                  ),
                                  child: _ClipLabelText(
                                    text: label!,
                                    color: labelTextColor,
                                    labelStyle: labelStyle,
                                  ),
                                ),
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

class _SelectionDropdown<T> extends StatelessWidget {
  const _SelectionDropdown({
    required this.label,
    required this.selected,
    required this.options,
    required this.itemLabel,
    this.itemBuilder,
    required this.onSelected,
  });

  final String label;
  final T selected;
  final List<T> options;
  final String Function(T option) itemLabel;
  final Widget Function(T option)? itemBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        DropdownButtonFormField<T>(
          key: ValueKey<String>(itemLabel(selected)),
          initialValue: selected,
          isExpanded: true,
          selectedItemBuilder: itemBuilder == null
              ? null
              : (context) => options
                    .map((option) => itemBuilder!(option))
                    .toList(growable: false),
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
          items: options
              .map(
                (option) => DropdownMenuItem<T>(
                  value: option,
                  child: itemBuilder?.call(option) ?? Text(itemLabel(option)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onSelected(value);
            }
          },
        ),
      ],
    );
  }
}

class _ClipFitModeDropdownItem extends StatelessWidget {
  const _ClipFitModeDropdownItem({required this.mode});

  final ClipFitMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ClipFitModeIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ClipFitModeIcon extends StatelessWidget {
  const _ClipFitModeIcon({required this.mode});

  final ClipFitMode mode;

  @override
  Widget build(BuildContext context) {
    final isCropCenter = mode == ClipFitMode.cropCenter;

    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFB8B1A8)),
            ),
          ),
          Center(
            child: Container(
              width: isCropCenter ? 14 : 10,
              height: isCropCenter ? 10 : 7,
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A59),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (isCropCenter)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF171A21),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClipLabelAlignmentDropdownItem extends StatelessWidget {
  const _ClipLabelAlignmentDropdownItem({required this.alignment});

  final ClipLabelAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ClipLabelAlignmentIcon(alignment: alignment),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            alignment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClipLabelStyleDropdownItem extends StatelessWidget {
  const _ClipLabelStyleDropdownItem({required this.style});

  final ClipLabelVisualStyle style;

  @override
  Widget build(BuildContext context) {
    final previewStyle = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 4,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: style,
    );

    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFF7F2EA),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD7CEC2)),
          ),
          alignment: Alignment.center,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: previewStyle.horizontalPadding,
              vertical: previewStyle.verticalPadding,
            ),
            decoration: BoxDecoration(
              color: previewStyle.backgroundColor,
              borderRadius: BorderRadius.circular(previewStyle.cornerRadius),
            ),
            child: _ClipLabelText(
              text: 'Aa',
              color: previewStyle.textColor,
              labelStyle: previewStyle,
              fontSizeOverride: 10,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            style.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClipLabelText extends StatelessWidget {
  const _ClipLabelText({
    required this.text,
    required this.color,
    required this.labelStyle,
    this.fontSizeOverride,
  });

  final String text;
  final Color color;
  final ClipLabelStyle labelStyle;
  final double? fontSizeOverride;

  TextStyle _fillStyle() {
    return TextStyle(
      color: color,
      fontSize: fontSizeOverride ?? labelStyle.fontSize,
      fontWeight: FontWeight.w600,
      shadows: labelStyle.textShadowColor == null
          ? null
          : <Shadow>[
              Shadow(
                color: labelStyle.textShadowColor!,
                blurRadius: 6,
                offset: const Offset(0, 1.5),
              ),
            ],
    );
  }

  TextStyle _outlineStyle() {
    return TextStyle(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = labelStyle.textOutlineWidth
        ..color = labelStyle.textOutlineColor!,
      fontSize: fontSizeOverride ?? labelStyle.fontSize,
      fontWeight: FontWeight.w600,
    );
  }

  Widget _buildText(TextStyle style) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (labelStyle.textOutlineColor == null ||
        labelStyle.textOutlineWidth <= 0) {
      return _buildText(_fillStyle());
    }

    return Stack(
      children: <Widget>[_buildText(_outlineStyle()), _buildText(_fillStyle())],
    );
  }
}

class _ClipLabelAlignmentIcon extends StatelessWidget {
  const _ClipLabelAlignmentIcon({required this.alignment});

  final ClipLabelAlignment alignment;

  Alignment _indicatorAlignment() => switch (alignment) {
    ClipLabelAlignment.topLeft => Alignment.topLeft,
    ClipLabelAlignment.topCenter => Alignment.topCenter,
    ClipLabelAlignment.topRight => Alignment.topRight,
    ClipLabelAlignment.center => Alignment.center,
    ClipLabelAlignment.bottomLeft => Alignment.bottomLeft,
    ClipLabelAlignment.bottomCenter => Alignment.bottomCenter,
    ClipLabelAlignment.bottomRight => Alignment.bottomRight,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF171A21), width: 1),
        ),
        child: Align(
          alignment: _indicatorAlignment(),
          child: Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Color(0xFFFF7A59),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportDurationDropdownItem extends StatelessWidget {
  const _ExportDurationDropdownItem({required this.mode});

  final ExportDurationMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ExportDurationIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _AudioModeDropdownItem extends StatelessWidget {
  const _AudioModeDropdownItem({required this.mode});

  final AudioMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _AudioModeIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _PlayModeDropdownItem extends StatelessWidget {
  const _PlayModeDropdownItem({required this.mode});

  final PlayMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _PlayModeIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _PlayModeIcon extends StatelessWidget {
  const _PlayModeIcon({required this.mode});

  final PlayMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: switch (mode) {
        PlayMode.parallel => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _PlayModeParallelRow(),
            SizedBox(height: 2),
            _PlayModeParallelRow(),
          ],
        ),
        PlayMode.sequential => const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _PlayModeTile(),
            SizedBox(width: 1),
            _PlayModeArrow(),
            SizedBox(width: 1),
            _PlayModeTile(isHighlighted: true),
          ],
        ),
      },
    );
  }
}

class _PlayModeParallelRow extends StatelessWidget {
  const _PlayModeParallelRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _PlayModeTile(isHighlighted: true),
        SizedBox(width: 1),
        _PlayModeArrow(),
      ],
    );
  }
}

class _PlayModeTile extends StatelessWidget {
  const _PlayModeTile({this.isHighlighted = false});

  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7A59)
            : const Color(0xFFE5DED3),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF7A59)
              : const Color(0xFFB8B1A8),
        ),
      ),
    );
  }
}

class _PlayModeArrow extends StatelessWidget {
  const _PlayModeArrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 4,
      height: 6,
      child: CustomPaint(painter: _PlayModeArrowPainter()),
    );
  }
}

class _PlayModeArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7A59)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width - 1.7, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 2.4, 1),
      Offset(size.width - 0.3, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 2.4, size.height - 1),
      Offset(size.width - 0.3, centerY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AudioModeIcon extends StatelessWidget {
  const _AudioModeIcon({required this.mode});

  final AudioMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: switch (mode) {
        AudioMode.firstClip => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AudioTrackBar(width: 16, isHighlighted: true),
            SizedBox(height: 2),
            _AudioTrackBar(width: 12),
            SizedBox(height: 2),
            _AudioTrackBar(width: 8),
          ],
        ),
        AudioMode.mixAll => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AudioTrackBar(width: 16, isHighlighted: true),
            SizedBox(height: 2),
            _AudioTrackBar(width: 13, isHighlighted: true),
            SizedBox(height: 2),
            _AudioTrackBar(width: 10, isHighlighted: true),
          ],
        ),
        AudioMode.longestClip => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AudioTrackBar(width: 8),
            SizedBox(height: 2),
            _AudioTrackBar(width: 11),
            SizedBox(height: 2),
            _AudioTrackBar(width: 16, isHighlighted: true),
          ],
        ),
        AudioMode.mute => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const Center(
              child: Icon(
                Icons.volume_up_rounded,
                size: 15,
                color: Color(0xFFB8B1A8),
              ),
            ),
            Center(
              child: Transform.rotate(
                angle: -0.78,
                child: Container(
                  width: 20,
                  height: 2.4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A59),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _AudioTrackBar extends StatelessWidget {
  const _AudioTrackBar({required this.width, this.isHighlighted = false});

  final double width;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7A59)
            : const Color(0xFFB8B1A8),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ExportDurationIcon extends StatelessWidget {
  const _ExportDurationIcon({required this.mode});

  final ExportDurationMode mode;

  @override
  Widget build(BuildContext context) {
    final highlightLong = mode == ExportDurationMode.longest;
    final highlightShort = mode == ExportDurationMode.shortest;

    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DurationBar(width: 16, isHighlighted: highlightLong),
          const SizedBox(height: 3),
          _DurationBar(width: 10, isHighlighted: highlightShort),
        ],
      ),
    );
  }
}

class _DurationBar extends StatelessWidget {
  const _DurationBar({required this.width, required this.isHighlighted});

  final double width;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7A59)
            : const Color(0xFFB8B1A8),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _AspectRatioDropdownItem extends StatelessWidget {
  const _AspectRatioDropdownItem({required this.preset});

  final AspectRatioPreset preset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _AspectRatioSwatch(preset: preset),
        const SizedBox(width: 12),
        Text(preset.label, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _AspectRatioSwatch extends StatelessWidget {
  const _AspectRatioSwatch({required this.preset});

  final AspectRatioPreset preset;

  @override
  Widget build(BuildContext context) {
    const outerSize = 26.0;
    const maxInnerSize = 16.0;
    final ratio = preset.value;
    final innerWidth = ratio >= 1 ? maxInnerSize : maxInnerSize * ratio;
    final innerHeight = ratio >= 1 ? maxInnerSize / ratio : maxInnerSize;

    return Container(
      width: outerSize,
      height: outerSize,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCCFBC)),
      ),
      alignment: Alignment.center,
      child: Container(
        width: innerWidth,
        height: innerHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF171A21), width: 1.4),
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
        'Import videos or photos to start your collage.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF697180)),
      ),
    );
  }
}
