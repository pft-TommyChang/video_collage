import 'dart:ui';

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
}

class VideoClipInfo {
  const VideoClipInfo({
    required this.path,
    required this.name,
    required this.duration,
    required this.width,
    required this.height,
  });

  final String path;
  final String name;
  final Duration duration;
  final int width;
  final int height;

  VideoClipInfo copyWith({
    String? path,
    String? name,
    Duration? duration,
    int? width,
    int? height,
  }) {
    return VideoClipInfo(
      path: path ?? this.path,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
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
    required this.includeClipLabelsInOutput,
    required this.clipLabelFontSize,
  });

  final int rows;
  final int columns;
  final int outputWidth;
  final int outputHeight;
  final double borderThickness;
  final double tileCornerRadius;
  final ColorChoice backgroundColor;
  final ColorChoice borderColor;
  final bool includeClipLabelsInOutput;
  final double clipLabelFontSize;

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
  });

  final double margin;
  final double horizontalPadding;
  final double verticalPadding;
  final double fontSize;
}

double overlayLabelScaleForExportScale(double scaleFactor) {
  return scaleFactor * 1.2;
}

ClipLabelStyle clipLabelStyleForOverlayScale(
  double overlayLabelScale, {
  required double baseFontSize,
}) {
  final fontScale = baseFontSize / 12;
  return ClipLabelStyle(
    margin: 8 * overlayLabelScale * fontScale,
    horizontalPadding: 8 * overlayLabelScale * fontScale,
    verticalPadding: 4 * overlayLabelScale * fontScale,
    fontSize: baseFontSize * overlayLabelScale,
  );
}

class CollageSlotClip {
  const CollageSlotClip({required this.slotIndex, required this.clip});

  final int slotIndex;
  final VideoClipInfo clip;
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
