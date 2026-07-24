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
}

class ExportOptions {
  const ExportOptions({
    required this.rows,
    required this.columns,
    required this.outputWidth,
    required this.outputHeight,
    required this.borderThickness,
    required this.tileCornerRadius,
    required this.backgroundColor,
    required this.borderColor,
  });

  final int rows;
  final int columns;
  final int outputWidth;
  final int outputHeight;
  final double borderThickness;
  final double tileCornerRadius;
  final ColorChoice backgroundColor;
  final ColorChoice borderColor;

  double get aspectRatio => outputWidth / outputHeight;
  int get borderPx => borderThickness.round();
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
