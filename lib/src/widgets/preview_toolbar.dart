part of '../video_collage_app.dart';

ButtonStyle _previewToolbarIconButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return IconButton.styleFrom(
    foregroundColor: scheme.onSurfaceVariant,
    disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
    backgroundColor: Colors.white.withValues(alpha: 0.74),
    disabledBackgroundColor: Colors.white.withValues(alpha: 0.42),
    side: const BorderSide(color: Color(0xFFD0C5B5)),
    minimumSize: const Size.square(32),
    maximumSize: const Size.square(32),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _PreviewToolbar extends StatelessWidget {
  const _PreviewToolbar({
    required this.hasClips,
    required this.hasPreviewMotion,
    required this.isPreviewPlaying,
    required this.canResetPreview,
    required this.isPreviewMuted,
    required this.previewPosition,
    required this.previewDuration,
    required this.onExpandPanel,
    required this.onAutoLayout,
    required this.onVerticalAutoLayout,
    required this.onHorizontalAutoLayout,
    required this.onResetAll,
    required this.onTogglePlayback,
    required this.onResetPreview,
    required this.onToggleMute,
  });

  static const double _durationBreakpoint = 340;

  final bool hasClips;
  final bool hasPreviewMotion;
  final bool isPreviewPlaying;
  final bool canResetPreview;
  final bool isPreviewMuted;
  final Duration previewPosition;
  final Duration previewDuration;
  final VoidCallback? onExpandPanel;
  final VoidCallback onAutoLayout;
  final VoidCallback onVerticalAutoLayout;
  final VoidCallback onHorizontalAutoLayout;
  final VoidCallback? onResetAll;
  final VoidCallback onTogglePlayback;
  final VoidCallback onResetPreview;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showDuration = constraints.maxWidth >= _durationBreakpoint;
        return SizedBox(
          width: constraints.maxWidth,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (onExpandPanel != null) ...<Widget>[
                          _PreviewLayoutButton(
                            key: const ValueKey<String>('preview-expand-panel'),
                            onPressed: onExpandPanel,
                            tooltip: 'Expand panel',
                            icon: const Icon(
                              Icons.keyboard_double_arrow_right_rounded,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _PreviewLayoutButton(
                          key: const ValueKey<String>(
                            'preview-smart-layout-button',
                          ),
                          onPressed: hasClips ? onAutoLayout : null,
                          tooltip: 'Smart layout',
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                        ),
                        const SizedBox(width: 6),
                        _PreviewLayoutButton(
                          key: const ValueKey<String>(
                            'preview-vertical-layout-button',
                          ),
                          onPressed: hasClips ? onVerticalAutoLayout : null,
                          tooltip: 'Vertical layout',
                          icon: const RotatedBox(
                            quarterTurns: 1,
                            child: Icon(Icons.view_column_outlined, size: 18),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _PreviewLayoutButton(
                          key: const ValueKey<String>(
                            'preview-horizontal-layout-button',
                          ),
                          onPressed: hasClips ? onHorizontalAutoLayout : null,
                          tooltip: 'Horizontal layout',
                          icon: const Icon(
                            Icons.view_column_outlined,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          key: const ValueKey<String>('preview-reset-button'),
                          onPressed: onResetAll,
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (hasPreviewMotion)
                Container(
                  key: const ValueKey<String>('preview-playback-controls'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.74),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFD0C5B5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _PreviewPlaybackButton(
                        onPressed: hasPreviewMotion ? onTogglePlayback : null,
                        tooltip: isPreviewPlaying
                            ? 'Pause preview'
                            : 'Play preview',
                        iconSize: 21,
                        icon: Icon(
                          isPreviewPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _PreviewPlaybackButton(
                        onPressed: canResetPreview ? onResetPreview : null,
                        tooltip: 'Return to start',
                        iconSize: 21,
                        icon: const Icon(Icons.refresh),
                      ),
                      const SizedBox(width: 6),
                      _PreviewPlaybackButton(
                        onPressed: hasPreviewMotion ? onToggleMute : null,
                        tooltip: isPreviewMuted
                            ? 'Unmute preview'
                            : 'Mute preview',
                        iconSize: 20,
                        icon: Icon(
                          isPreviewMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                      if (showDuration) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          key: const ValueKey<String>('preview-duration'),
                          '${formatDuration(previewPosition)} / ${formatDuration(previewDuration)}',
                          style: _durationStyle(
                            context,
                            enabled: hasPreviewMotion,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  TextStyle? _durationStyle(BuildContext context, {required bool enabled}) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    return baseStyle?.copyWith(
      color: enabled ? baseStyle.color : Theme.of(context).disabledColor,
      fontSize: (baseStyle.fontSize ?? 14) * 1.05,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

class _PreviewLayoutButton extends StatelessWidget {
  const _PreviewLayoutButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.outlined(
        onPressed: onPressed,
        tooltip: tooltip,
        style: _previewToolbarIconButtonStyle(context),
        icon: icon,
      ),
    );
  }
}

class _PreviewPlaybackButton extends StatelessWidget {
  const _PreviewPlaybackButton({
    required this.onPressed,
    required this.tooltip,
    required this.iconSize,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final double iconSize;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      visualDensity: VisualDensity.compact,
      iconSize: iconSize,
      splashRadius: 15,
      icon: icon,
    );
  }
}
