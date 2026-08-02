import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'services/editor_settings_store.dart';
import 'services/desktop_file_service.dart';
import 'services/system_dialog_service.dart';
import 'services/video_export_service.dart';
import 'video_trimmer_dialog.dart';

part 'controllers/app_controller.dart';
part 'controllers/collage_controller.dart';
part 'controllers/export_controller.dart';
part 'controllers/history_controller.dart';
part 'controllers/media_controller.dart';
part 'controllers/preview_controller.dart';
part 'controllers/settings_controller.dart';
part 'screens/video_collage_screen_content.dart';
part 'utils/editor_constants.dart';
part 'widgets/clip_label_dialog.dart';
part 'widgets/common_controls.dart';
part 'widgets/export_controls.dart';
part 'widgets/media_widgets.dart';
part 'widgets/preview_widgets.dart';
part 'widgets/preview_toolbar.dart';
part 'widgets/selection_widgets.dart';

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
  static const MethodChannel _mediaOpenChannel = MethodChannel(
    'video_collage/media_open',
  );

  final SystemDialogService _dialogService = const SystemDialogService();
  final EditorSettingsStore _settingsStore = const EditorSettingsStore();
  final VideoExportService _exportService = VideoExportService();

  final List<VideoClipInfo> _clips = <VideoClipInfo>[];
  final Map<int, String> _slotAssignments = <int, String>{};
  final Map<String, ClipViewport> _clipViewports = <String, ClipViewport>{};
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
  bool _isConsumingOpenedMedia = false;
  bool _shouldConsumeOpenedMediaAgain = false;
  int? _externalDropHoverSlotIndex;
  int? _lastPreviewProgressSecond;
  Duration _parallelPreviewElapsed = Duration.zero;
  DateTime? _parallelPreviewStartedAt;
  Duration _sequentialPreviewElapsed = Duration.zero;
  DateTime? _sequentialPreviewStartedAt;
  String? _activeSequentialClipPath;
  String? _editingViewportClipPath;

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
  String _appVersion = '…';

  ExportHistoryEntry? get _lastExportEntry => _sessionLastExportEntry;

  @override
  void initState() {
    super.initState();
    final initialSize = _sizeFromPreset(_selectedAspect, _selectedResolution);
    _outputWidth = initialSize.$1;
    _outputHeight = initialSize.$2;
    _widthController = TextEditingController(text: '$_outputWidth');
    _heightController = TextEditingController(text: '$_outputHeight');
    _mediaOpenChannel.setMethodCallHandler(_handleMediaOpenMethodCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeOpenedMediaFiles());
    });
    unawaited(_loadAppVersion());
    unawaited(_restoreSettings());
    unawaited(_restoreExportHistory());
  }

  @override
  void dispose() {
    _mediaOpenChannel.setMethodCallHandler(null);
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

  @override
  Widget build(BuildContext context) => _buildScreen(context);

  void _updateState(VoidCallback update) => setState(update);
}
