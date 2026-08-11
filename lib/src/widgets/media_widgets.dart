part of '../video_collage_app.dart';

class _ClipListTile extends StatelessWidget {
  const _ClipListTile({
    required this.clip,
    required this.controller,
    required this.isUsed,
    required this.isLoading,
    required this.errorMessage,
    required this.visibleAreaFraction,
    required this.onTap,
    required this.onTrim,
    required this.onEditLabel,
    required this.onRemove,
  });

  final VideoClipInfo clip;
  final VideoPlayerController? controller;
  final bool isUsed;
  final bool isLoading;
  final String? errorMessage;
  final double visibleAreaFraction;
  final VoidCallback onTap;
  final VoidCallback? onTrim;
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                      const SizedBox(height: 4),
                      Text(
                        _clipStatus,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF697180),
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

    final thumbnail = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTrim,
      child: MouseRegion(
        cursor: onTrim == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
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
                if (clip.isVideo)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(
                      Icons.content_cut_rounded,
                      size: 15,
                      color: clip.isTrimmed
                          ? _activeMediaEditIconColor
                          : Colors.white,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xE6000000),
                          blurRadius: 5,
                          offset: Offset(0, 1),
                        ),
                        Shadow(color: Color(0x99000000), blurRadius: 2),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return onTrim == null
        ? thumbnail
        : Tooltip(message: 'Trim video', child: thumbnail);
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
    if (isLoading) {
      return 'Importing preview...';
    }
    if (errorMessage != null) {
      return 'Preview unavailable • export still possible';
    }
    if (clip.width == 0 || clip.height == 0) {
      return clip.isPhoto
          ? _clipFormat
          : '${formatDuration(clip.duration)} • ${formatFrameRate(clip.frameRate)}';
    }
    if (clip.isPhoto) {
      return '${clip.width}×${clip.height}';
    }
    final trimLabel = clip.isTrimmed ? ' • trimmed' : '';
    return '${clip.width}×${clip.height} • ${formatDuration(clip.duration)} • ${formatFrameRate(clip.frameRate)}$trimLabel';
  }

  String get _clipStatus =>
      'Visible • ${(visibleAreaFraction * 100).round()}% • $_clipFormat';

  String get _clipFormat =>
      p.extension(clip.path).replaceFirst('.', '').toLowerCase();
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
