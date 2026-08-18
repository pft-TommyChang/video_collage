part of '../video_collage_app.dart';

extension _SettingsController on _VideoCollageScreenState {
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
      borderImagePath: _borderImagePath,
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
      _updateState(() {
        _showExportComplete = false;
        _exportProgress = 0;
      });
    });
  }

  Future<void> _restoreSettings() async {
    try {
      await _loadAndApplySettings();
    } finally {
      if (widget.deferFirstFrameUntilSettingsRestored) {
        WidgetsBinding.instance.allowFirstFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_dismissNativeStartupView());
        });
      }
    }
  }

  Future<void> _loadAndApplySettings() async {
    final savedSettings = await _settingsStore.load();
    if (!mounted) {
      return;
    }
    if (savedSettings == null) {
      return;
    }

    _isRestoringSettings = true;
    _updateState(() {
      _rows = savedSettings.rows.clamp(1, _maxGridDimension);
      _columns = savedSettings.columns.clamp(1, _maxGridDimension);
      _isMediaSectionCollapsed = savedSettings.isMediaSectionCollapsed;
      _isLayoutSectionCollapsed = savedSettings.isLayoutSectionCollapsed;
      _isLabelSectionCollapsed = savedSettings.isLabelSectionCollapsed;
      _isOutputSectionCollapsed = savedSettings.isOutputSectionCollapsed;
      _isSidePanelCollapsed = savedSettings.isSidePanelCollapsed;
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
      _setPreferAiMetadataForClipLabels(
        savedSettings.preferAiMetadataForClipLabels,
      );
      _clipLabelDisplayMode = savedSettings.clipLabelDisplayMode;
      _clipLabelAlignment = savedSettings.clipLabelAlignment;
      _clipLabelVisualStyle = savedSettings.clipLabelVisualStyle;
      _selectedFitMode = ClipFitMode.values.firstWhere(
        (mode) => mode.name == savedSettings.fitMode,
        orElse: () => _selectedFitMode,
      );
      _mergeFitMode = ClipFitMode.values.firstWhere(
        (mode) => mode.name == savedSettings.mergeFitMode,
        orElse: () => ClipFitMode.cropCenter,
      );
      _mergeFrameRateMode = VideoMergeFrameRateMode.values.firstWhere(
        (mode) => mode.name == savedSettings.mergeFrameRateMode,
        orElse: () => VideoMergeFrameRateMode.firstVideo,
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
      _selectedBorderColor = _colorChoiceFromColor(
        Color(savedSettings.borderColorValue),
      );
      _selectedBackgroundColor = _colorChoiceFromColor(
        Color(savedSettings.backgroundColorValue),
      );
      // Canvas images are session-only because sandbox access to user-selected
      // files does not survive an app restart.
      _borderImagePath = null;
      _outputWidth = _ensureEven(savedSettings.outputWidth);
      _outputHeight = _ensureEven(savedSettings.outputHeight);
      _syncResolutionDraft(_outputWidth, _outputHeight);
    });
    await WidgetsBinding.instance.endOfFrame;
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
    _updateState(() {
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
        isSidePanelCollapsed: _isSidePanelCollapsed,
        borderThickness: _borderThickness,
        tileCornerRadius: _tileCornerRadius,
        clipLabelFontSize: _clipLabelFontSize,
        clipLabelAlignment: _clipLabelAlignment,
        clipLabelVisualStyle: _clipLabelVisualStyle,
        clipLabelPadding: _clipLabelPadding,
        includeClipLabelsInOutput: _includeClipLabelsInOutput,
        preferAiMetadataForClipLabels: _preferAiMetadataForClipLabels,
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
        borderColorValue: _selectedBorderColor.color.toARGB32(),
        backgroundColorValue: _selectedBackgroundColor.color.toARGB32(),
        mergeFitMode: _mergeFitMode.name,
        mergeFrameRateMode: _mergeFrameRateMode.name,
      ),
    );
  }

  void _setStateAndSave(VoidCallback update) {
    _updateState(update);
    _scheduleSettingsSave();
  }

  Future<void> _pickBorderImage() async {
    final path = await _dialogService.pickPhoto();
    if (!mounted || path == null) {
      return;
    }
    _setStateAndSave(() {
      _selectedBorderColor = _defaultBorderColor;
      _borderImagePath = path;
      _statusMessage = 'Border image selected. It will be center-cropped.';
    });
  }

  void _clearBorderImage() {
    _setStateAndSave(() {
      _borderImagePath = null;
      _statusMessage = 'Border image removed.';
    });
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
}
