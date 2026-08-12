part of '../video_collage_app.dart';

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
                            onPressed: onExpandPanel,
                            tooltip: 'Expand panel',
                            icon: const Icon(
                              Icons.keyboard_double_arrow_right_rounded,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _PreviewLayoutButton(
                          onPressed: hasClips ? onAutoLayout : null,
                          tooltip: 'Auto Layout',
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                        ),
                        const SizedBox(width: 6),
                        _PreviewLayoutButton(
                          onPressed: hasClips ? onVerticalAutoLayout : null,
                          tooltip: 'Vertical Auto',
                          icon: const RotatedBox(
                            quarterTurns: 1,
                            child: Icon(Icons.view_column_outlined, size: 18),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _PreviewLayoutButton(
                          onPressed: hasClips ? onHorizontalAutoLayout : null,
                          tooltip: 'Horizontal Auto',
                          icon: const Icon(
                            Icons.view_column_outlined,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _PreviewLayoutButton(
                          onPressed: onResetAll,
                          tooltip: 'Reset all',
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
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
                      tooltip: !hasPreviewMotion
                          ? 'Preview playback unavailable for photos only'
                          : isPreviewPlaying
                          ? 'Pause preview'
                          : 'Play preview',
                      iconSize: 24,
                      icon: Icon(
                        isPreviewPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PreviewPlaybackButton(
                      onPressed: canResetPreview ? onResetPreview : null,
                      tooltip: 'Reset preview to start',
                      iconSize: 23,
                      icon: const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 8),
                    _PreviewPlaybackButton(
                      onPressed: hasClips ? onToggleMute : null,
                      tooltip: isPreviewMuted
                          ? 'Unmute preview'
                          : 'Mute preview',
                      iconSize: 22,
                      icon: Icon(
                        isPreviewMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                      ),
                    ),
                    if (showDuration) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        '${formatDuration(previewPosition)} / ${formatDuration(previewDuration)}',
                        style: _durationStyle(context),
                      ),
                      const SizedBox(width: 8),
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

  TextStyle? _durationStyle(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    return baseStyle?.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) * 1.17,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

class _PreviewLayoutButton extends StatelessWidget {
  const _PreviewLayoutButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 34),
        maximumSize: const Size(34, 34),
      ),
      icon: icon,
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
      splashRadius: 16,
      icon: icon,
    );
  }
}
