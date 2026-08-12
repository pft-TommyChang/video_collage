part of '../video_collage_app.dart';

const _aspectPresets = <AspectRatioPreset>[
  AspectRatioPreset(label: '9:21', widthFactor: 9, heightFactor: 21),
  AspectRatioPreset(label: '9:16', widthFactor: 9, heightFactor: 16),
  AspectRatioPreset(label: '4:5', widthFactor: 4, heightFactor: 5),
  AspectRatioPreset(label: '3:4', widthFactor: 3, heightFactor: 4),
  AspectRatioPreset(label: '1:1', widthFactor: 1, heightFactor: 1),
  AspectRatioPreset(label: '5:4', widthFactor: 5, heightFactor: 4),
  AspectRatioPreset(label: '4:3', widthFactor: 4, heightFactor: 3),
  AspectRatioPreset(label: '16:9', widthFactor: 16, heightFactor: 9),
  AspectRatioPreset(label: '21:9', widthFactor: 21, heightFactor: 9),
];

const _resolutionPresets = <ResolutionPreset>[
  ResolutionPreset(label: 'HD 720', shortEdge: 720),
  ResolutionPreset(label: 'Full HD 1080', shortEdge: 1080),
  ResolutionPreset(label: '2K 1440', shortEdge: 1440),
  ResolutionPreset(label: '4K 2160', shortEdge: 2160),
];
const ResolutionPreset _customResolutionPreset = ResolutionPreset(
  label: 'Custom',
  shortEdge: 0,
);
const _resolutionOptions = <ResolutionPreset>[
  ..._resolutionPresets,
  _customResolutionPreset,
];

const _colorChoices = <ColorChoice>[
  ColorChoice(label: 'White', color: Color(0xFFFFFFFF), ffmpegHex: '0xFFFFFF'),
  ColorChoice(label: 'Grey', color: Color(0xFFD0D5DD), ffmpegHex: '0xD0D5DD'),
  ColorChoice(label: 'Ink', color: Color(0xFF101217), ffmpegHex: '0x101217'),
  ColorChoice(label: 'Coral', color: Color(0xFFFF7A59), ffmpegHex: '0xFF7A59'),
  ColorChoice(label: 'Aqua', color: Color(0xFF4CC9C0), ffmpegHex: '0x4CC9C0'),
];

const ColorChoice _transparentColor = ColorChoice(
  label: 'Transparent',
  color: Color(0x00000000),
  ffmpegHex: 'black@0.0',
);

ColorChoice _colorChoiceFromColor(Color color) {
  final argb = color.toARGB32();
  for (final choice in _colorChoices) {
    if (choice.color.toARGB32() == argb) {
      return choice;
    }
  }
  if (color.a == 0) {
    return _transparentColor;
  }
  final rgb = argb & 0xFFFFFF;
  final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  final alpha = (argb >> 24) & 0xFF;
  return ColorChoice(
    label: '#$hex',
    color: color,
    ffmpegHex: alpha == 255
        ? '0x$hex'
        : '0x$hex@${(alpha / 255).toStringAsFixed(3)}',
  );
}

const _supportedVideoExtensions = <String>{
  '.mp4',
  '.mov',
  '.m4v',
  '.avi',
  '.mkv',
};

const _supportedPhotoExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.heif',
};

final AspectRatioPreset _defaultAspectPreset = _aspectPresets.firstWhere(
  (preset) => preset.label == '1:1',
);
final ResolutionPreset _defaultResolutionPreset = _resolutionPresets[1];

ButtonStyle _sectionHeaderIconButtonStyle() {
  return IconButton.styleFrom(
    minimumSize: const Size(34, 34),
    maximumSize: const Size(34, 34),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
  );
}

final ColorChoice _defaultBorderColor = _colorChoices[0];
final ColorChoice _defaultBackgroundColor = _colorChoices[1];

const int _defaultRows = 2;
const int _defaultColumns = 2;
const int _maxGridDimension = 8;
const int _maxGridCapacity = _maxGridDimension * _maxGridDimension;
const double _defaultBorderThickness = 12;
const double _defaultTileCornerRadius = 12;
const double _defaultClipLabelFontSize = 16;
const double _defaultClipLabelPadding = 10;
const bool _defaultIncludeClipLabelsInOutput = true;
const ClipLabelDisplayMode _defaultClipLabelDisplayMode =
    ClipLabelDisplayMode.labelOnly;
const ClipLabelAlignment _defaultClipLabelAlignment =
    ClipLabelAlignment.topLeft;
const ClipLabelVisualStyle _defaultClipLabelVisualStyle =
    ClipLabelVisualStyle.transparentOutline;
const bool _defaultAppendDateTimeToExportName = true;
const PlayMode _defaultPlayMode = PlayMode.parallel;
const AudioMode _defaultAudioMode = AudioMode.firstClip;

enum _LastExportAction { openFile, showInFolder }

enum _AutoLayoutMode { automatic, verticalStack, horizontalStrip }

enum _ResetEverythingAction { settingsOnly, settingsAndMedia }

const ExportDurationMode _defaultDurationMode = ExportDurationMode.longest;
const ClipFitMode _defaultFitMode = ClipFitMode.cropCenter;
const int _minOutputDimensionExclusive = 360;
const int _maxOutputDimensionExclusive = 4096;
const double _maxBorderThickness = 100;
const double _maxTileCornerRadius = 100;
const double _maxClipLabelFontSize = 50;
const double _maxClipLabelPadding = 48;
const Duration _previewInitializationTimeout = Duration(seconds: 12);

String _previewErrorSummary(Object error) {
  if (error is TimeoutException) {
    return 'Preview timed out after '
        '${_previewInitializationTimeout.inSeconds} seconds.';
  }

  final rawMessage = switch (error) {
    VideoExportException() => error.message,
    PlatformException() => error.message ?? error.code,
    _ => error.toString(),
  };
  final message = rawMessage
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'^\w*Exception(?::\s*|\s+)'), '')
      .trim();
  if (message.isEmpty) {
    return 'Could not create a preview.';
  }

  const maxLength = 100;
  return message.length <= maxLength
      ? message
      : '${message.substring(0, maxLength - 1).trimRight()}…';
}
