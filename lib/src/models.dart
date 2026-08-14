import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

class AspectRatioPreset {
  const AspectRatioPreset({
    required this.label,
    required this.widthFactor,
    required this.heightFactor,
  });

  final String label;
  final int widthFactor;
  final int heightFactor;

  double get value => widthFactor / heightFactor;
}

class ResolutionPreset {
  const ResolutionPreset({required this.label, required this.shortEdge});

  final String label;
  final int shortEdge;
}

class ColorChoice {
  const ColorChoice({
    required this.label,
    required this.color,
    required this.ffmpegHex,
  });

  final String label;
  final Color color;
  final String ffmpegHex;

  bool get isTransparent => color.a == 0;
}

enum MediaKind { video, photo }

enum C2paStatus { unknown, absent, untrusted, trusted, invalid }

class AiMediaMetadata {
  const AiMediaMetadata({
    this.c2paStatus = C2paStatus.unknown,
    this.vendor,
    this.model,
  });

  final C2paStatus c2paStatus;
  final String? vendor;
  final String? model;

  bool get hasC2pa => switch (c2paStatus) {
    C2paStatus.untrusted || C2paStatus.trusted || C2paStatus.invalid => true,
    C2paStatus.unknown || C2paStatus.absent => false,
  };

  bool get hasDisplayableInfo => hasC2pa || vendor != null;
}

enum AudioMode {
  firstClip,
  mixAll,
  longestClip,
  mute;

  String get label => switch (this) {
    AudioMode.firstClip => 'First clip audio',
    AudioMode.mixAll => 'Mix all audios',
    AudioMode.longestClip => 'Longest clip audio',
    AudioMode.mute => 'Mute',
  };
}

enum PlayMode {
  parallel,
  sequential;

  String get label => switch (this) {
    PlayMode.parallel => 'Together',
    PlayMode.sequential => 'One by one',
  };
}

enum ExportDurationMode {
  longest,
  shortest;

  String get label => switch (this) {
    ExportDurationMode.longest => 'Longest clip',
    ExportDurationMode.shortest => 'Shortest clip',
  };
}

enum ExportFormat {
  mp4,
  jpg;

  String get label => switch (this) {
    ExportFormat.mp4 => 'MP4',
    ExportFormat.jpg => 'JPG',
  };

  String get suggestedFileName => switch (this) {
    ExportFormat.mp4 => 'pfc_export.mp4',
    ExportFormat.jpg => 'pfc_export.jpg',
  };
}

enum ClipFitMode {
  cropCenter,
  centerInside;

  String get label => switch (this) {
    ClipFitMode.cropCenter => 'Crop',
    ClipFitMode.centerInside => 'Inside',
  };

  BoxFit get previewFit => switch (this) {
    ClipFitMode.cropCenter => BoxFit.cover,
    ClipFitMode.centerInside => BoxFit.contain,
  };
}

double visibleAreaFractionForFit({
  required ClipFitMode fitMode,
  required double sourceAspect,
  required double targetAspect,
}) {
  if (fitMode == ClipFitMode.centerInside) {
    return 1;
  }
  if (sourceAspect <= 0 || targetAspect <= 0) {
    return 0;
  }
  final aspectRatio = sourceAspect / targetAspect;
  return (aspectRatio <= 1 ? aspectRatio : 1 / aspectRatio).clamp(0.0, 1.0);
}

enum ClipLabelDisplayMode {
  labelOnly,
  indexOnly,
  indexAndLabel;

  String get label => switch (this) {
    ClipLabelDisplayMode.labelOnly => 'Label only',
    ClipLabelDisplayMode.indexOnly => 'Index only',
    ClipLabelDisplayMode.indexAndLabel => 'Index + label',
  };
}

enum ClipLabelAlignment {
  topLeft,
  topCenter,
  topRight,
  center,
  bottomLeft,
  bottomCenter,
  bottomRight;

  String get label => switch (this) {
    ClipLabelAlignment.topLeft => 'Top left',
    ClipLabelAlignment.topCenter => 'Top',
    ClipLabelAlignment.topRight => 'Top right',
    ClipLabelAlignment.center => 'Center',
    ClipLabelAlignment.bottomLeft => 'Bottom left',
    ClipLabelAlignment.bottomCenter => 'Bottom',
    ClipLabelAlignment.bottomRight => 'Bottom right',
  };

  Alignment get previewAlignment => switch (this) {
    ClipLabelAlignment.topLeft => Alignment.topLeft,
    ClipLabelAlignment.topCenter => Alignment.topCenter,
    ClipLabelAlignment.topRight => Alignment.topRight,
    ClipLabelAlignment.center => Alignment.center,
    ClipLabelAlignment.bottomLeft => Alignment.bottomLeft,
    ClipLabelAlignment.bottomCenter => Alignment.bottomCenter,
    ClipLabelAlignment.bottomRight => Alignment.bottomRight,
  };
}

enum ClipLabelVisualStyle {
  dark,
  light,
  transparentShadow,
  transparentOutline,
  squareTag;

  String get label => switch (this) {
    ClipLabelVisualStyle.dark => 'Black / white',
    ClipLabelVisualStyle.light => 'White / black',
    ClipLabelVisualStyle.transparentShadow => 'Transparent / shadow',
    ClipLabelVisualStyle.transparentOutline => 'Transparent / outline',
    ClipLabelVisualStyle.squareTag => 'Square tag',
  };
}

class VideoClipInfo {
  const VideoClipInfo({
    this.instanceId = '',
    required this.path,
    required this.name,
    required this.duration,
    required this.width,
    required this.height,
    required this.hasAudio,
    required this.mediaKind,
    this.frameRate = 0,
    this.sourceDuration,
    this.trimStart = Duration.zero,
    this.aiMetadata = const AiMediaMetadata(),
  });

  /// Identifies one use of a source file inside an editor session.
  ///
  /// Probe-only and legacy values may omit this and fall back to [path].
  final String instanceId;
  final String path;
  final String name;
  final Duration duration;
  final int width;
  final int height;
  final bool hasAudio;
  final MediaKind mediaKind;
  final double frameRate;
  final Duration? sourceDuration;
  final Duration trimStart;
  final AiMediaMetadata aiMetadata;

  String get id => instanceId.isEmpty ? path : instanceId;

  bool get isVideo => mediaKind == MediaKind.video;
  bool get isPhoto => mediaKind == MediaKind.photo;
  Duration get fullDuration => sourceDuration ?? duration;
  Duration get trimEnd => trimStart + duration;
  bool get isTrimmed =>
      isVideo && (trimStart > Duration.zero || duration < fullDuration);

  VideoClipInfo copyWith({
    String? instanceId,
    String? path,
    String? name,
    Duration? duration,
    int? width,
    int? height,
    bool? hasAudio,
    MediaKind? mediaKind,
    double? frameRate,
    Duration? sourceDuration,
    Duration? trimStart,
    AiMediaMetadata? aiMetadata,
  }) {
    return VideoClipInfo(
      instanceId: instanceId ?? this.instanceId,
      path: path ?? this.path,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      hasAudio: hasAudio ?? this.hasAudio,
      mediaKind: mediaKind ?? this.mediaKind,
      frameRate: frameRate ?? this.frameRate,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      trimStart: trimStart ?? this.trimStart,
      aiMetadata: aiMetadata ?? this.aiMetadata,
    );
  }
}

enum ClipLabelSourcePreset {
  vendorName,
  modelName,
  fileName;

  String? valueFor(VideoClipInfo clip) {
    final vendor = _capitalizeFirst(clip.aiMetadata.vendor);
    final model = _capitalizeFirst(clip.aiMetadata.model);

    return switch (this) {
      ClipLabelSourcePreset.vendorName => vendor,
      ClipLabelSourcePreset.modelName => model,
      ClipLabelSourcePreset.fileName => _nonEmpty(
        p.basenameWithoutExtension(clip.path),
      ),
    };
  }

  String? buttonLabelFor(VideoClipInfo clip) {
    final value = valueFor(clip);
    if (this != ClipLabelSourcePreset.fileName || value == null) {
      return value;
    }
    final characters = value.runes;
    if (characters.length <= 20) {
      return value;
    }
    return '${String.fromCharCodes(characters.take(20))}...';
  }
}

String? _capitalizeFirst(String? value) {
  final normalized = _nonEmpty(value);
  if (normalized == null) {
    return null;
  }
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class ExportOptions {
  static const double _referenceShortEdge = 720;

  const ExportOptions({
    required this.rows,
    required this.columns,
    required this.outputWidth,
    required this.outputHeight,
    required this.borderThickness,
    required this.tileCornerRadius,
    required this.backgroundColor,
    required this.borderColor,
    this.borderImagePath,
    required this.fitMode,
    required this.includeClipLabelsInOutput,
    required this.clipLabelDisplayMode,
    required this.clipLabelFontSize,
    required this.clipLabelAlignment,
    required this.clipLabelVisualStyle,
    required this.clipLabelPadding,
    required this.playMode,
    required this.audioMode,
    required this.durationMode,
  });

  final int rows;
  final int columns;
  final int outputWidth;
  final int outputHeight;
  final double borderThickness;
  final double tileCornerRadius;
  final ColorChoice backgroundColor;
  final ColorChoice borderColor;
  final String? borderImagePath;
  final ClipFitMode fitMode;
  final bool includeClipLabelsInOutput;
  final ClipLabelDisplayMode clipLabelDisplayMode;
  final double clipLabelFontSize;
  final ClipLabelAlignment clipLabelAlignment;
  final ClipLabelVisualStyle clipLabelVisualStyle;
  final double clipLabelPadding;
  final PlayMode playMode;
  final AudioMode audioMode;
  final ExportDurationMode durationMode;

  double get aspectRatio => outputWidth / outputHeight;
  double get shortEdge => outputWidth < outputHeight
      ? outputWidth.toDouble()
      : outputHeight.toDouble();
  double get scaleFactor => shortEdge / _referenceShortEdge;
  double get scaledBorderThickness => borderThickness * scaleFactor;
  double get scaledTileCornerRadius => tileCornerRadius * scaleFactor;
  int get borderPx => scaledBorderThickness.round();
  int get tileCornerRadiusPx => scaledTileCornerRadius.round();
}

class ClipLabelStyle {
  const ClipLabelStyle({
    required this.margin,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.fontSize,
    required this.backgroundColor,
    required this.textColor,
    required this.textShadowColor,
    required this.textOutlineColor,
    required this.textOutlineWidth,
    required this.cornerRadius,
  });

  final EdgeInsets margin;
  final double horizontalPadding;
  final double verticalPadding;
  final double fontSize;
  final Color? backgroundColor;
  final Color textColor;
  final Color? textShadowColor;
  final Color? textOutlineColor;
  final double textOutlineWidth;
  final double cornerRadius;
}

double overlayLabelScaleForExportScale(double scaleFactor) {
  return scaleFactor * 1.2;
}

ClipLabelStyle clipLabelStyleForOverlayScale(
  double overlayLabelScale, {
  required double baseFontSize,
  required double baseEdgePadding,
  required ClipLabelAlignment alignment,
  required ClipLabelVisualStyle visualStyle,
  double baseFixedPadding = 5,
}) {
  final fontScale = baseFontSize / 12;
  final resolvedEdgePadding = baseEdgePadding * overlayLabelScale * fontScale;
  final resolvedFixedPadding = baseFixedPadding * overlayLabelScale * fontScale;
  final (
    backgroundColor,
    textColor,
    textShadowColor,
    textOutlineColor,
    textOutlineWidth,
    cornerRadius,
  ) = switch (visualStyle) {
    ClipLabelVisualStyle.dark => (
      const Color(0x7A000000),
      const Color(0xFFFFFFFF),
      null,
      null,
      0.0,
      999.0,
    ),
    ClipLabelVisualStyle.light => (
      const Color(0xEFFFFFFF),
      const Color(0xFF111111),
      null,
      null,
      0.0,
      999.0,
    ),
    ClipLabelVisualStyle.transparentShadow => (
      null,
      const Color(0xFFFFFFFF),
      const Color(0xCC000000),
      null,
      0.0,
      999.0,
    ),
    ClipLabelVisualStyle.transparentOutline => (
      null,
      const Color(0xFFFFFFFF),
      null,
      const Color(0xFF000000),
      2.4 * overlayLabelScale * fontScale,
      999.0,
    ),
    ClipLabelVisualStyle.squareTag => (
      const Color(0xCC111111),
      const Color(0xFFFFFFFF),
      null,
      null,
      0.0,
      6.0 * overlayLabelScale * fontScale,
    ),
  };
  return ClipLabelStyle(
    margin: clipLabelMarginForAlignment(
      alignment: alignment,
      anchorPadding: resolvedEdgePadding,
      fixedPadding: resolvedFixedPadding,
    ),
    horizontalPadding: 7 * overlayLabelScale * fontScale,
    verticalPadding: 2 * overlayLabelScale * fontScale,
    fontSize: baseFontSize * overlayLabelScale,
    backgroundColor: backgroundColor,
    textColor: textColor,
    textShadowColor: textShadowColor,
    textOutlineColor: textOutlineColor,
    textOutlineWidth: textOutlineWidth,
    cornerRadius: cornerRadius,
  );
}

Color clipLabelHighlightedTextColor(ClipLabelVisualStyle visualStyle) {
  return switch (visualStyle) {
    ClipLabelVisualStyle.dark => const Color(0xFFFACC15),
    ClipLabelVisualStyle.light => const Color(0xFFC2410C),
    ClipLabelVisualStyle.transparentShadow => const Color(0xFFFACC15),
    ClipLabelVisualStyle.transparentOutline => const Color(0xFFFACC15),
    ClipLabelVisualStyle.squareTag => const Color(0xFFFACC15),
  };
}

EdgeInsets clipLabelMarginForAlignment({
  required ClipLabelAlignment alignment,
  required double anchorPadding,
  required double fixedPadding,
}) {
  return switch (alignment) {
    ClipLabelAlignment.topLeft => EdgeInsets.fromLTRB(
      anchorPadding,
      anchorPadding,
      fixedPadding,
      fixedPadding,
    ),
    ClipLabelAlignment.topCenter => EdgeInsets.fromLTRB(
      fixedPadding,
      anchorPadding,
      fixedPadding,
      fixedPadding,
    ),
    ClipLabelAlignment.topRight => EdgeInsets.fromLTRB(
      fixedPadding,
      anchorPadding,
      anchorPadding,
      fixedPadding,
    ),
    ClipLabelAlignment.center => EdgeInsets.all(fixedPadding),
    ClipLabelAlignment.bottomLeft => EdgeInsets.fromLTRB(
      anchorPadding,
      fixedPadding,
      fixedPadding,
      anchorPadding,
    ),
    ClipLabelAlignment.bottomCenter => EdgeInsets.fromLTRB(
      fixedPadding,
      fixedPadding,
      fixedPadding,
      anchorPadding,
    ),
    ClipLabelAlignment.bottomRight => EdgeInsets.fromLTRB(
      fixedPadding,
      fixedPadding,
      anchorPadding,
      anchorPadding,
    ),
  };
}

class CollageSlotClip {
  const CollageSlotClip({
    required this.slotIndex,
    required this.clip,
    this.viewport = const ClipViewport(),
  });

  final int slotIndex;
  final VideoClipInfo clip;
  final ClipViewport viewport;
}

class ClipViewport {
  const ClipViewport({this.zoom = 1, this.focusX = 0.5, this.focusY = 0.5});

  final double zoom;
  final double focusX;
  final double focusY;

  bool get isDefault =>
      (zoom - 1).abs() < 0.0001 &&
      (focusX - 0.5).abs() < 0.0001 &&
      (focusY - 0.5).abs() < 0.0001;

  Alignment get previewAlignment => Alignment(focusX * 2 - 1, focusY * 2 - 1);

  ClipViewport copyWith({double? zoom, double? focusX, double? focusY}) {
    return ClipViewport(
      zoom: (zoom ?? this.zoom).clamp(1.0, 4.0),
      focusX: (focusX ?? this.focusX).clamp(0.0, 1.0),
      focusY: (focusY ?? this.focusY).clamp(0.0, 1.0),
    );
  }
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatFrameRate(double frameRate) {
  if (frameRate <= 0 || !frameRate.isFinite) {
    return 'FPS unavailable';
  }
  final rounded = frameRate.round();
  final value = (frameRate - rounded).abs() < 0.005
      ? '$rounded'
      : frameRate.toStringAsFixed(2);
  return '$value FPS';
}

String buildClipLabelText({
  required int slotIndex,
  required String clipName,
  required ClipLabelDisplayMode mode,
}) {
  final trimmedName = clipName.trim();
  final indexLabel = '#${slotIndex + 1}';
  return switch (mode) {
    ClipLabelDisplayMode.labelOnly => trimmedName,
    ClipLabelDisplayMode.indexOnly => indexLabel,
    ClipLabelDisplayMode.indexAndLabel =>
      trimmedName.isEmpty ? indexLabel : '$indexLabel $trimmedName',
  };
}

ExportFormat exportFormatForClips(Iterable<CollageSlotClip> slotClips) {
  final clips = slotClips.toList(growable: false);
  if (clips.isNotEmpty && clips.every((entry) => entry.clip.isPhoto)) {
    return ExportFormat.jpg;
  }
  return ExportFormat.mp4;
}

Duration exportDurationForClips(
  Iterable<CollageSlotClip> slotClips,
  ExportDurationMode mode,
  PlayMode playMode,
) {
  final videoDurations = slotClips
      .map((entry) => entry.clip)
      .where((clip) => clip.isVideo && clip.duration > Duration.zero)
      .map((clip) => clip.duration)
      .toList(growable: false);

  if (videoDurations.isEmpty) {
    return Duration.zero;
  }

  if (playMode == PlayMode.sequential) {
    return videoDurations.fold(
      Duration.zero,
      (total, duration) => total + duration,
    );
  }

  return switch (mode) {
    ExportDurationMode.longest => videoDurations.reduce(
      (current, next) => next > current ? next : current,
    ),
    ExportDurationMode.shortest => videoDurations.reduce(
      (current, next) => next < current ? next : current,
    ),
  };
}
