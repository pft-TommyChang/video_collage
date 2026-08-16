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

  static const double _aiMetadataRowHeight = 16;

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
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _buildThumbnail(),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildHeader(context),
                      ),
                      const SizedBox(height: 4),
                      _singleLineText(
                        _clipDetails,
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: errorMessage == null
                              ? const Color(0xFF697180)
                              : const Color(0xFFB42318),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        key: ValueKey<String>('ai-metadata-row-${clip.id}'),
                        height: _aiMetadataRowHeight,
                        child: clip.aiMetadata.hasDisplayableInfo
                            ? _buildAiMetadataRow(context)
                            : null,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: _singleLineText(
                  clip.name,
                  Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Edit clip label',
                onPressed: onEditLabel,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                splashRadius: 14,
                icon: const Icon(Icons.edit_outlined, color: Colors.black45),
              ),
            ],
          ),
        ),
        IconButton(
          key: ValueKey<String>('remove-media-${clip.id}'),
          tooltip: 'Remove',
          onPressed: onRemove,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          splashRadius: 16,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _singleLineText(String text, TextStyle? style) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _buildAiMetadataRow(BuildContext context) {
    final metadata = clip.aiMetadata;
    final vendor = metadata.vendor;
    final model = metadata.model;
    return Tooltip(
      message: _aiMetadataTooltip,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          dragDevices: const <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (metadata.hasC2pa)
                _buildAiTag(
                  context,
                  'C2PA',
                  trailing: Icon(
                    Icons.circle,
                    size: 9,
                    color: _c2paStatusColor(metadata.c2paStatus),
                  ),
                ),
              if (metadata.hasC2pa && vendor != null) const SizedBox(width: 6),
              if (vendor != null) _buildAiTag(context, vendor),
              if ((metadata.hasC2pa || vendor != null) && model != null)
                const SizedBox(width: 6),
              if (model != null) _buildAiTag(context, model),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiTag(BuildContext context, String label, {Widget? trailing}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF7A5A50)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _singleLineText(
              label,
              Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF7A5A50),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 1),
              trailing,
            ],
          ],
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
          width: 64,
          height: 64,
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
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xD9000000),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 14,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Center(
                          child: Text(
                            _clipMediaType,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
          ? _visibleAreaLabel
          : '$_visibleAreaLabel • ${formatDuration(clip.duration)} • ${formatFrameRate(clip.frameRate)}';
    }
    if (clip.isPhoto) {
      return '${clip.width}×${clip.height} • $_visibleAreaLabel';
    }
    final trimLabel = clip.isTrimmed ? ' • trimmed' : '';
    return '${clip.width}×${clip.height} • $_visibleAreaLabel • ${formatDuration(clip.duration)} • ${formatFrameRate(clip.frameRate)}$trimLabel';
  }

  String get _visibleAreaLabel => '${(visibleAreaFraction * 100).round()}%';

  String get _aiMetadataTooltip {
    final metadata = clip.aiMetadata;
    final parts = <String>[
      if (metadata.hasC2pa) 'C2PA',
      if (metadata.c2paStatus == C2paStatus.trusted) 'Trust',
      if (metadata.c2paStatus == C2paStatus.untrusted) 'Untrust',
      if (metadata.c2paStatus == C2paStatus.invalid) 'Invalid',
      if (metadata.vendor != null) metadata.vendor!,
      if (metadata.model != null) metadata.model!,
    ];
    return parts.join(' • ');
  }

  String get _clipMediaType => shortMediaTypeLabel(clip.path, clip.mediaKind);
}

Color _c2paStatusColor(C2paStatus status) => switch (status) {
  C2paStatus.invalid => const Color(0xFFC62828),
  C2paStatus.untrusted => const Color(0xFFF9A825),
  C2paStatus.trusted => const Color(0xFF2E7D32),
  C2paStatus.unknown || C2paStatus.absent => const Color(0xFF8C98A8),
};

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
