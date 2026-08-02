part of '../video_collage_app.dart';

const double _viewportActionIconDisplaySize = 18;
const double _viewportActionButtonDisplaySize = 20;
const double _viewportActionGapDisplaySize = 4;
const double _viewportActionEdgeDisplayPadding = 5;
const double _viewportEditingIconDisplaySize = 16;
const double _viewportEditingZoomIconDisplaySize = 18;
const double _viewportEditingControlPaddingDisplaySize = 9.6;
const double _viewportEditingPanelPaddingDisplaySize = 2.4;
const double _viewportEditingPanelLeftPaddingDisplaySize = 6.4;
const double _viewportEditingDoneHorizontalPaddingDisplaySize = 6.4;
const double _viewportEditingDoneButtonDisplayWidth = 44;
const double _viewportEditingBottomInsetDisplaySize = 6.4;
const double _viewportEditingControlHeightDisplaySize = 32;
const double _viewportEditingCompactControlsDisplayWidth = 88;
const double _viewportEditingSliderMinimumDisplayWidth = 156;
const double _viewportEditingZoomIconsMinimumDisplayWidth = 200;
const double _viewportEditingControlsMinimumDisplayHeight = 48;
const double _viewportEditingControlsMaximumDisplayWidth = 294;
const double _cropActionsMinimumDisplayWidth =
    _viewportActionEdgeDisplayPadding +
    _viewportActionButtonDisplaySize * 2 +
    _viewportActionGapDisplaySize;
const double _trimActionsMinimumDisplayWidth =
    _viewportActionEdgeDisplayPadding +
    _viewportActionButtonDisplaySize * 3 +
    _viewportActionGapDisplaySize * 2;

class _ViewportActionButton extends StatelessWidget {
  const _ViewportActionButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.buttonSize,
    required this.color,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final double buttonSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: Size.square(buttonSize),
        maximumSize: Size.square(buttonSize),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      icon: Icon(
        icon,
        size: iconSize,
        color: color,
        shadows: const <Shadow>[
          Shadow(color: Color(0xE0000000), blurRadius: 8, offset: Offset(0, 2)),
          Shadow(color: Colors.black87, blurRadius: 2),
        ],
      ),
    );
  }
}

class _ViewportEditingPanel extends StatelessWidget {
  const _ViewportEditingPanel({
    required this.width,
    required this.viewport,
    required this.showSlider,
    required this.showZoomIcons,
    required this.onZoomChanged,
    required this.onReset,
    required this.onDone,
  });

  final double width;
  final ClipViewport viewport;
  final bool showSlider;
  final bool showZoomIcons;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback? onReset;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    const iconSize = _viewportEditingIconDisplaySize;
    const controlGap = _viewportEditingControlPaddingDisplaySize;
    final compactButtonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(_viewportEditingControlHeightDisplaySize),
      maximumSize: const Size.square(_viewportEditingControlHeightDisplaySize),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final doneButtonStyle = FilledButton.styleFrom(
      fixedSize: const Size(
        _viewportEditingDoneButtonDisplayWidth,
        _viewportEditingControlHeightDisplaySize,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(
        horizontal: _viewportEditingDoneHorizontalPaddingDisplaySize,
      ),
    );

    return SizedBox(
      width: width,
      child: Material(
        key: ValueKey<String>(
          showSlider
              ? 'viewport-editing-controls-full'
              : 'viewport-editing-controls-compact',
        ),
        color: const Color(0xEFFFFFFF),
        elevation: 8,
        borderRadius: BorderRadius.circular(iconSize),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _viewportEditingPanelLeftPaddingDisplaySize,
            _viewportEditingPanelPaddingDisplaySize,
            _viewportEditingPanelPaddingDisplaySize,
            _viewportEditingPanelPaddingDisplaySize,
          ),
          child: Row(
            children: <Widget>[
              if (showSlider) ...<Widget>[
                if (showZoomIcons) ...<Widget>[
                  const Icon(
                    Icons.remove_circle_outline,
                    size: _viewportEditingZoomIconDisplaySize,
                  ),
                  const SizedBox(width: controlGap * 0.25),
                ],
                Expanded(
                  child: SizedBox(
                    height: _viewportEditingControlHeightDisplaySize,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.4,
                        overlayColor: Colors.transparent,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: viewport.zoom,
                        min: 1,
                        max: 4,
                        onChanged: onZoomChanged,
                      ),
                    ),
                  ),
                ),
                if (showZoomIcons) ...<Widget>[
                  const SizedBox(width: controlGap * 0.25),
                  const Icon(
                    Icons.add_circle_outline,
                    size: _viewportEditingZoomIconDisplaySize,
                  ),
                ],
                const SizedBox(width: controlGap * 0.5),
              ],
              IconButton(
                onPressed: viewport.isDefault ? null : onReset,
                tooltip: 'Reset framing',
                iconSize: iconSize,
                style: compactButtonStyle,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              const SizedBox(width: controlGap * 0.25),
              FilledButton(
                onPressed: onDone,
                style: doneButtonStyle,
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: iconSize * 0.58),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    required this.viewport,
    required this.isEditingViewport,
    required this.isVeiled,
    required this.onVeilTap,
    required this.onEditViewport,
    required this.onTrim,
    required this.onRemove,
    required this.onViewportChanged,
    required this.onResetViewport,
    required this.onFinishViewport,
    required this.isDragTarget,
    required this.overlayLabelScale,
    required this.previewDisplayScale,
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
  final ClipViewport viewport;
  final bool isEditingViewport;
  final bool isVeiled;
  final VoidCallback onVeilTap;
  final VoidCallback? onEditViewport;
  final VoidCallback? onTrim;
  final VoidCallback? onRemove;
  final ValueChanged<ClipViewport>? onViewportChanged;
  final VoidCallback? onResetViewport;
  final VoidCallback? onFinishViewport;
  final bool isDragTarget;
  final double overlayLabelScale;
  final double previewDisplayScale;

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
    final rawLabel = !showLabel || clip == null || isEditingViewport
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
      viewport: viewport,
      isDragTarget: isDragTarget,
      overlayLabelScale: overlayLabelScale,
    );
    final interactiveTile = clip == null
        ? tile
        : _ViewportControls(
            clip: clip!,
            viewport: viewport,
            isEditing: isEditingViewport,
            canEdit: fitMode == ClipFitMode.cropCenter,
            onEdit: onEditViewport,
            onTrim: onTrim,
            onRemove: onRemove,
            onChanged: onViewportChanged,
            onReset: onResetViewport,
            onDone: onFinishViewport,
            previewDisplayScale: previewDisplayScale,
            child: tile,
          );

    final focusedTile = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        interactiveTile,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !isVeiled,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              opacity: isVeiled ? 1 : 0,
              child: Material(
                color: Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(cornerRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: onVeilTap),
              ),
            ),
          ),
        ),
      ],
    );

    if (dragData == null || isEditingViewport || isVeiled) {
      return focusedTile;
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
              viewport: viewport,
              isDragTarget: false,
              overlayLabelScale: overlayLabelScale,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.30, child: focusedTile),
      child: focusedTile,
    );
  }
}

class _ViewportControls extends StatefulWidget {
  const _ViewportControls({
    required this.clip,
    required this.viewport,
    required this.isEditing,
    required this.canEdit,
    required this.onEdit,
    required this.onTrim,
    required this.onRemove,
    required this.onChanged,
    required this.onReset,
    required this.onDone,
    required this.previewDisplayScale,
    required this.child,
  });

  final VideoClipInfo clip;
  final ClipViewport viewport;
  final bool isEditing;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onTrim;
  final VoidCallback? onRemove;
  final ValueChanged<ClipViewport>? onChanged;
  final VoidCallback? onReset;
  final VoidCallback? onDone;
  final double previewDisplayScale;
  final Widget child;

  @override
  State<_ViewportControls> createState() => _ViewportControlsState();
}

class _ViewportControlsState extends State<_ViewportControls> {
  bool _isHovered = false;
  final Set<int> _pressedViewportPointers = <int>{};
  double _gestureStartZoom = 1;

  void _setViewportPointerPressed(int pointer, {required bool isPressed}) {
    setState(() {
      if (isPressed) {
        _pressedViewportPointers.add(pointer);
      } else {
        _pressedViewportPointers.remove(pointer);
      }
    });
  }

  void _updateZoom(double zoom) {
    widget.onChanged?.call(widget.viewport.copyWith(zoom: zoom));
  }

  void _panBy(Offset delta, Size tileSize) {
    if (tileSize.width <= 0 ||
        tileSize.height <= 0 ||
        widget.clip.width <= 0 ||
        widget.clip.height <= 0) {
      return;
    }

    final sourceAspect = widget.clip.width / widget.clip.height;
    final targetAspect = tileSize.width / tileSize.height;
    final baseWidth = sourceAspect >= targetAspect
        ? tileSize.height * sourceAspect
        : tileSize.width;
    final baseHeight = sourceAspect >= targetAspect
        ? tileSize.height
        : tileSize.width / sourceAspect;
    final overflowX = baseWidth * widget.viewport.zoom - tileSize.width;
    final overflowY = baseHeight * widget.viewport.zoom - tileSize.height;
    final focusX = overflowX > 0.5
        ? widget.viewport.focusX - delta.dx / overflowX
        : 0.5;
    final focusY = overflowY > 0.5
        ? widget.viewport.focusY - delta.dy / overflowY
        : 0.5;
    widget.onChanged?.call(
      widget.viewport.copyWith(focusX: focusX, focusY: focusY),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controls = MouseRegion(
      cursor: widget.isEditing
          ? _pressedViewportPointers.isNotEmpty
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileSize = constraints.biggest;
          final shortSide = tileSize.shortestSide;
          final previewDisplayScale = widget.previewDisplayScale.clamp(
            0.001,
            double.infinity,
          );
          final displayedTileWidth = tileSize.width * previewDisplayScale;
          final displayedTileHeight = tileSize.height * previewDisplayScale;
          final hoverIconSize =
              _viewportActionIconDisplaySize / previewDisplayScale;
          final hoverControlSize =
              _viewportActionButtonDisplaySize / previewDisplayScale;
          final hoverControlGap =
              _viewportActionGapDisplaySize / previewDisplayScale;
          final hoverControlPadding =
              _viewportActionEdgeDisplayPadding / previewDisplayScale;
          final showCropAction =
              displayedTileWidth >= _cropActionsMinimumDisplayWidth;
          final showTrimAction =
              widget.onTrim != null &&
              displayedTileWidth >= _trimActionsMinimumDisplayWidth;
          const editingControlPadding =
              _viewportEditingControlPaddingDisplaySize;
          final showEditingSlider =
              displayedTileWidth >= _viewportEditingSliderMinimumDisplayWidth &&
              displayedTileHeight >=
                  _viewportEditingControlsMinimumDisplayHeight;
          final showEditingZoomIcons =
              displayedTileWidth >=
              _viewportEditingZoomIconsMinimumDisplayWidth;
          final canShowEditingControls =
              displayedTileWidth >=
                  _viewportEditingCompactControlsDisplayWidth +
                      editingControlPadding &&
              displayedTileHeight >=
                  _viewportEditingControlHeightDisplaySize +
                      _viewportEditingPanelPaddingDisplaySize * 2 +
                      _viewportEditingBottomInsetDisplaySize;
          final editingPanelWidth = showEditingSlider
              ? math.max(
                  0.0,
                  math.min(
                    _viewportEditingControlsMaximumDisplayWidth,
                    displayedTileWidth - editingControlPadding * 2,
                  ),
                )
              : _viewportEditingCompactControlsDisplayWidth;
          final editingPanelAlignment = showEditingSlider
              ? Alignment.bottomCenter
              : Alignment.bottomRight;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              widget.child,
              if (widget.isEditing)
                Listener(
                  onPointerDown: (event) => _setViewportPointerPressed(
                    event.pointer,
                    isPressed: true,
                  ),
                  onPointerUp: (event) => _setViewportPointerPressed(
                    event.pointer,
                    isPressed: false,
                  ),
                  onPointerCancel: (event) => _setViewportPointerPressed(
                    event.pointer,
                    isPressed: false,
                  ),
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent &&
                        (HardwareKeyboard.instance.isMetaPressed ||
                            HardwareKeyboard.instance.isControlPressed)) {
                      _updateZoom(
                        widget.viewport.zoom *
                            (event.scrollDelta.dy > 0 ? 0.92 : 1.08),
                      );
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onScaleStart: (_) {
                      _gestureStartZoom = widget.viewport.zoom;
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount > 1 ||
                          (details.scale - 1).abs() > 0.001) {
                        _updateZoom(_gestureStartZoom * details.scale);
                      } else {
                        _panBy(details.focalPointDelta, tileSize);
                      }
                    },
                    onDoubleTap: widget.onReset,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFFF7657),
                          width: math.max(2, shortSide * 0.008),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!widget.isEditing && _isHovered && widget.onRemove != null)
                Positioned(
                  bottom: hoverControlPadding,
                  right: hoverControlPadding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showTrimAction) ...<Widget>[
                        _ViewportActionButton(
                          onPressed: widget.onTrim,
                          tooltip: 'Trim',
                          icon: Icons.content_cut_rounded,
                          iconSize: hoverIconSize,
                          buttonSize: hoverControlSize,
                          color: Colors.white,
                        ),
                        SizedBox(width: hoverControlGap),
                      ],
                      if (showCropAction) ...<Widget>[
                        _ViewportActionButton(
                          onPressed: widget.canEdit ? widget.onEdit : null,
                          tooltip: 'Crop Area',
                          icon: widget.viewport.isDefault
                              ? Icons.crop_free_rounded
                              : Icons.center_focus_strong_rounded,
                          iconSize: hoverIconSize,
                          buttonSize: hoverControlSize,
                          color: !widget.canEdit
                              ? Colors.white54
                              : Colors.white,
                        ),
                        SizedBox(width: hoverControlGap),
                      ],
                      _ViewportActionButton(
                        onPressed: widget.onRemove,
                        tooltip: 'Remove',
                        icon: Icons.close_rounded,
                        iconSize: hoverIconSize,
                        buttonSize: hoverControlSize,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              // The entire preview canvas is painted through a FittedBox.
              // Counter-scale editing controls so their on-screen dimensions
              // stay stable when the canvas or cell dimensions change.
              if (widget.isEditing && canShowEditingControls)
                Positioned(
                  left: 0,
                  right: showEditingSlider
                      ? 0
                      : editingControlPadding / previewDisplayScale,
                  bottom:
                      _viewportEditingBottomInsetDisplaySize /
                      previewDisplayScale,
                  child: UnconstrainedBox(
                    constrainedAxis: Axis.vertical,
                    alignment: editingPanelAlignment,
                    child: Transform.scale(
                      scale: 1 / previewDisplayScale,
                      alignment: editingPanelAlignment,
                      child: _ViewportEditingPanel(
                        width: editingPanelWidth,
                        viewport: widget.viewport,
                        showSlider: showEditingSlider,
                        showZoomIcons: showEditingZoomIcons,
                        onZoomChanged: _updateZoom,
                        onReset: widget.onReset,
                        onDone: widget.onDone,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (!widget.isEditing) {
      return controls;
    }
    return TapRegion(
      onTapOutside: (_) => widget.onDone?.call(),
      child: controls,
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
    required this.viewport,
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
  final ClipViewport viewport;
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
                        Transform.scale(
                          scale: fitMode == ClipFitMode.cropCenter
                              ? viewport.zoom
                              : 1,
                          alignment: viewport.previewAlignment,
                          child: FittedBox(
                            fit: fitMode.previewFit,
                            alignment: viewport.previewAlignment,
                            child: SizedBox(
                              width: previewVideoSize.width,
                              height: previewVideoSize.height,
                              child: VideoPlayer(controller!),
                            ),
                          ),
                        )
                      else if (clip?.isPhoto == true)
                        Positioned.fill(
                          child: Transform.scale(
                            scale: fitMode == ClipFitMode.cropCenter
                                ? viewport.zoom
                                : 1,
                            alignment: viewport.previewAlignment,
                            child: Image.file(
                              File(clip!.path),
                              fit: fitMode.previewFit,
                              alignment: viewport.previewAlignment,
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
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
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
                                    size: clip == null
                                        ? emptyTileIconSize
                                        : errorMessage != null
                                        ? 68
                                        : 34,
                                    color: Colors.black.withValues(alpha: 0.28),
                                  ),
                                  if (errorMessage != null) ...<Widget>[
                                    const SizedBox(height: 16),
                                    Text(
                                      'Preview failed',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            fontSize: 24,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
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
