part of '../video_collage_app.dart';

class _CompactExportButton extends StatelessWidget {
  const _CompactExportButton({
    required this.onPressed,
    required this.isExporting,
    required this.showCompleted,
    required this.progress,
  });

  final VoidCallback onPressed;
  final bool isExporting;
  final bool showCompleted;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final icon = showCompleted
        ? Icons.check_rounded
        : Icons.file_download_outlined;
    final tooltip = showCompleted
        ? 'Export complete'
        : isExporting
        ? 'Exporting... ${(clampedProgress * 100).round()}%'
        : 'Export';

    return SizedBox.square(
      key: const ValueKey<String>('collapsed-export-button'),
      dimension: 42,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          IconButton.filled(
            onPressed: onPressed,
            tooltip: tooltip,
            icon: Icon(icon),
          ),
          if (isExporting)
            IgnorePointer(
              child: SizedBox.square(
                dimension: 42,
                child: CircularProgressIndicator(
                  value: clampedProgress > 0 ? clampedProgress : null,
                  strokeWidth: 3,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.28),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
