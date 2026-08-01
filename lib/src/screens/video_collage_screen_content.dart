part of '../video_collage_app.dart';

extension _VideoCollageScreenContent on _VideoCollageScreenState {
  Widget _buildScreen(BuildContext context) {
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
              _updateState(() {
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
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
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
                                          Text(
                                            'Version $_appVersion',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF697180,
                                                  ),
                                                  fontSize: 10,
                                                  height: 1,
                                                ),
                                          ),
                                        ],
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
                                const SizedBox(height: 12),
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
                                              visibleAreaFraction:
                                                  visibleAreaFractionForFit(
                                                    fitMode: _selectedFitMode,
                                                    sourceAspect:
                                                        _clipAspectRatio(clip),
                                                    targetAspect:
                                                        previewCellAspectRatio,
                                                  ),
                                              onTap: () => unawaited(
                                                _toggleClipActive(clip),
                                              ),
                                              onTrim: clip.isVideo
                                                  ? () => unawaited(
                                                      _openVideoTrimmer(clip),
                                                    )
                                                  : null,
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
                                            if (mode !=
                                                ClipFitMode.cropCenter) {
                                              _editingViewportClipPath = null;
                                            }
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
                                              onChanged: (_) =>
                                                  _updateState(() {}),
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
                                              onChanged: (_) =>
                                                  _updateState(() {}),
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
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onSecondaryTapDown:
                                            _isExporting || !hasLastExport
                                            ? null
                                            : (details) => unawaited(
                                                _showLastExportMenu(
                                                  context,
                                                  details,
                                                ),
                                              ),
                                        child: IconButton(
                                          onPressed:
                                              _isExporting || !hasLastExport
                                              ? null
                                              : () => unawaited(
                                                  _openLastExport(),
                                                ),
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
                              _PreviewToolbar(
                                hasClips: _clips.isNotEmpty,
                                hasPreviewMotion: hasPreviewMotion,
                                isPreviewPlaying: _isPreviewPlaying,
                                canResetPreview: canStopPreview,
                                isPreviewMuted: _isPreviewMuted,
                                previewPosition: previewPosition,
                                previewDuration: exportDuration,
                                onAutoLayout: _autoLayout,
                                onVerticalAutoLayout: () => _autoLayout(
                                  mode: _AutoLayoutMode.verticalStack,
                                ),
                                onHorizontalAutoLayout: () => _autoLayout(
                                  mode: _AutoLayoutMode.horizontalStrip,
                                ),
                                onTogglePlayback: () => unawaited(
                                  _setPreviewPlayback(!_isPreviewPlaying),
                                ),
                                onResetPreview: () =>
                                    unawaited(_stopPreviewPlayback()),
                                onToggleMute: () =>
                                    unawaited(_togglePreviewMute()),
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, previewConstraints) {
                                    final previewDisplayScale = math.min(
                                      previewConstraints.maxWidth /
                                          previewCanvasWidth,
                                      previewConstraints.maxHeight /
                                          previewCanvasHeight,
                                    );
                                    return Center(
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
                                                        crossAxisCount:
                                                            _columns,
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
                                                              details.data !=
                                                              index,
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
                                                                  _updateState(
                                                                    () {
                                                                      _externalDropHoverSlotIndex =
                                                                          index;
                                                                    },
                                                                  );
                                                                }
                                                              },
                                                              onDragExited: (_) {
                                                                if (_externalDropHoverSlotIndex ==
                                                                    index) {
                                                                  _updateState(
                                                                    () {
                                                                      _externalDropHoverSlotIndex =
                                                                          null;
                                                                    },
                                                                  );
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
                                                                    clip !=
                                                                        null &&
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
                                                                    ? () => _pickMediaForSlot(
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
                                                                viewport:
                                                                    clip == null
                                                                    ? const ClipViewport()
                                                                    : _clipViewports[clip
                                                                              .path] ??
                                                                          const ClipViewport(),
                                                                isEditingViewport:
                                                                    clip !=
                                                                        null &&
                                                                    _editingViewportClipPath ==
                                                                        clip.path,
                                                                isVeiled:
                                                                    _editingViewportClipPath !=
                                                                        null &&
                                                                    clip?.path !=
                                                                        _editingViewportClipPath,
                                                                onVeilTap:
                                                                    _finishViewportEditing,
                                                                onEditViewport:
                                                                    clip == null
                                                                    ? null
                                                                    : () =>
                                                                          _startViewportEditing(
                                                                            clip,
                                                                          ),
                                                                onTrim:
                                                                    clip?.isVideo ==
                                                                        true
                                                                    ? () => unawaited(
                                                                        _openVideoTrimmer(
                                                                          clip!,
                                                                        ),
                                                                      )
                                                                    : null,
                                                                onRemove:
                                                                    clip == null
                                                                    ? null
                                                                    : () =>
                                                                          _removeClip(
                                                                            clip,
                                                                          ),
                                                                onViewportChanged:
                                                                    clip == null
                                                                    ? null
                                                                    : (
                                                                        viewport,
                                                                      ) => _updateClipViewport(
                                                                        clip.path,
                                                                        viewport,
                                                                      ),
                                                                onResetViewport:
                                                                    clip == null
                                                                    ? null
                                                                    : () => _resetClipViewport(
                                                                        clip.path,
                                                                      ),
                                                                onFinishViewport:
                                                                    clip == null
                                                                    ? null
                                                                    : _finishViewportEditing,
                                                                isDragTarget:
                                                                    candidateData
                                                                        .isNotEmpty ||
                                                                    _externalDropHoverSlotIndex ==
                                                                        index,
                                                                overlayLabelScale:
                                                                    overlayLabelScale,
                                                                previewDisplayScale:
                                                                    previewDisplayScale,
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
                                    );
                                  },
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
}
