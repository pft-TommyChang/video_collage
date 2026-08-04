import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

class ExportHistoryEntry {
  const ExportHistoryEntry({
    required this.path,
    required this.format,
    required this.timestampMillis,
  });

  final String path;
  final String format;
  final int timestampMillis;

  Map<String, Object> toJson() {
    return <String, Object>{
      'path': path,
      'format': format,
      'timestampMillis': timestampMillis,
    };
  }

  factory ExportHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ExportHistoryEntry(
      path: json['path'] as String? ?? '',
      format: json['format'] as String? ?? 'MP4',
      timestampMillis: (json['timestampMillis'] as num?)?.toInt() ?? 0,
    );
  }
}

class PersistedEditorSettings {
  const PersistedEditorSettings({
    required this.rows,
    required this.columns,
    required this.isMediaSectionCollapsed,
    required this.isLayoutSectionCollapsed,
    required this.isLabelSectionCollapsed,
    required this.isOutputSectionCollapsed,
    required this.isSidePanelCollapsed,
    required this.borderThickness,
    required this.tileCornerRadius,
    required this.clipLabelFontSize,
    required this.clipLabelAlignment,
    required this.clipLabelVisualStyle,
    required this.clipLabelPadding,
    required this.includeClipLabelsInOutput,
    required this.clipLabelDisplayMode,
    required this.fitMode,
    required this.outputWidth,
    required this.outputHeight,
    required this.aspectLabel,
    required this.resolutionLabel,
    required this.playMode,
    required this.audioMode,
    required this.durationMode,
    required this.appendDateTimeToExportName,
    required this.lastExportDirectory,
    required this.borderColorLabel,
    required this.backgroundColorLabel,
    required this.borderColorValue,
    required this.backgroundColorValue,
  });

  final int rows;
  final int columns;
  final bool isMediaSectionCollapsed;
  final bool isLayoutSectionCollapsed;
  final bool isLabelSectionCollapsed;
  final bool isOutputSectionCollapsed;
  final bool isSidePanelCollapsed;
  final double borderThickness;
  final double tileCornerRadius;
  final double clipLabelFontSize;
  final ClipLabelAlignment clipLabelAlignment;
  final ClipLabelVisualStyle clipLabelVisualStyle;
  final double clipLabelPadding;
  final bool includeClipLabelsInOutput;
  final ClipLabelDisplayMode clipLabelDisplayMode;
  final String fitMode;
  final int outputWidth;
  final int outputHeight;
  final String aspectLabel;
  final String resolutionLabel;
  final String playMode;
  final String audioMode;
  final String durationMode;
  final bool appendDateTimeToExportName;
  final String lastExportDirectory;
  final String borderColorLabel;
  final String backgroundColorLabel;
  final int borderColorValue;
  final int backgroundColorValue;
  Map<String, Object> toJson() {
    return <String, Object>{
      'rows': rows,
      'columns': columns,
      'isMediaSectionCollapsed': isMediaSectionCollapsed,
      'isLayoutSectionCollapsed': isLayoutSectionCollapsed,
      'isLabelSectionCollapsed': isLabelSectionCollapsed,
      'isOutputSectionCollapsed': isOutputSectionCollapsed,
      'isSidePanelCollapsed': isSidePanelCollapsed,
      'borderThickness': borderThickness,
      'tileCornerRadius': tileCornerRadius,
      'clipLabelFontSize': clipLabelFontSize,
      'clipLabelAlignment': clipLabelAlignment.name,
      'clipLabelVisualStyle': clipLabelVisualStyle.name,
      'clipLabelPadding': clipLabelPadding,
      'includeClipLabelsInOutput': includeClipLabelsInOutput,
      'clipLabelDisplayMode': clipLabelDisplayMode.name,
      'fitMode': fitMode,
      'outputWidth': outputWidth,
      'outputHeight': outputHeight,
      'aspectLabel': aspectLabel,
      'resolutionLabel': resolutionLabel,
      'playMode': playMode,
      'audioMode': audioMode,
      'durationMode': durationMode,
      'appendDateTimeToExportName': appendDateTimeToExportName,
      'lastExportDirectory': lastExportDirectory,
      'borderColorLabel': borderColorLabel,
      'backgroundColorLabel': backgroundColorLabel,
      'borderColorValue': borderColorValue,
      'backgroundColorValue': backgroundColorValue,
    };
  }

  factory PersistedEditorSettings.fromJson(Map<String, dynamic> json) {
    final hadPersistedCanvasImage =
        (json['borderImagePath'] as String?)?.isNotEmpty ?? false;
    final clipLabelDisplayModeName = json['clipLabelDisplayMode'] as String?;
    final clipLabelDisplayMode = ClipLabelDisplayMode.values.firstWhere(
      (mode) => mode.name == clipLabelDisplayModeName,
      orElse: () {
        final legacyShowClipLabelIndex =
            json['showClipLabelIndex'] as bool? ?? false;
        return legacyShowClipLabelIndex
            ? ClipLabelDisplayMode.indexAndLabel
            : ClipLabelDisplayMode.labelOnly;
      },
    );
    final clipLabelAlignmentName = json['clipLabelAlignment'] as String?;
    final clipLabelAlignment = ClipLabelAlignment.values.firstWhere(
      (alignment) => alignment.name == clipLabelAlignmentName,
      orElse: () => ClipLabelAlignment.topLeft,
    );
    final clipLabelVisualStyleName = json['clipLabelVisualStyle'] as String?;
    final clipLabelVisualStyle = ClipLabelVisualStyle.values.firstWhere(
      (style) => style.name == clipLabelVisualStyleName,
      orElse: () => ClipLabelVisualStyle.dark,
    );

    return PersistedEditorSettings(
      rows: (json['rows'] as num?)?.toInt() ?? 2,
      columns: (json['columns'] as num?)?.toInt() ?? 2,
      isMediaSectionCollapsed:
          json['isMediaSectionCollapsed'] as bool? ?? false,
      isLayoutSectionCollapsed:
          json['isLayoutSectionCollapsed'] as bool? ?? false,
      isLabelSectionCollapsed:
          json['isLabelSectionCollapsed'] as bool? ?? false,
      isOutputSectionCollapsed:
          json['isOutputSectionCollapsed'] as bool? ?? false,
      isSidePanelCollapsed: json['isSidePanelCollapsed'] as bool? ?? false,
      borderThickness: (json['borderThickness'] as num?)?.toDouble() ?? 12,
      tileCornerRadius: (json['tileCornerRadius'] as num?)?.toDouble() ?? 12,
      clipLabelFontSize: (json['clipLabelFontSize'] as num?)?.toDouble() ?? 12,
      clipLabelAlignment: clipLabelAlignment,
      clipLabelVisualStyle: clipLabelVisualStyle,
      clipLabelPadding: (json['clipLabelPadding'] as num?)?.toDouble() ?? 10,
      includeClipLabelsInOutput:
          json['includeClipLabelsInOutput'] as bool? ?? false,
      clipLabelDisplayMode: clipLabelDisplayMode,
      fitMode: json['fitMode'] as String? ?? 'cropCenter',
      outputWidth: (json['outputWidth'] as num?)?.toInt() ?? 1920,
      outputHeight: (json['outputHeight'] as num?)?.toInt() ?? 1080,
      aspectLabel: json['aspectLabel'] as String? ?? '16:9',
      resolutionLabel: json['resolutionLabel'] as String? ?? 'Full HD 1080',
      playMode: json['playMode'] as String? ?? 'parallel',
      audioMode: json['audioMode'] as String? ?? 'firstClip',
      durationMode: json['durationMode'] as String? ?? 'longest',
      appendDateTimeToExportName:
          json['appendDateTimeToExportName'] as bool? ?? true,
      lastExportDirectory: json['lastExportDirectory'] as String? ?? '',
      borderColorLabel: hadPersistedCanvasImage
          ? 'White'
          : json['borderColorLabel'] as String? ?? 'White',
      backgroundColorLabel: json['backgroundColorLabel'] as String? ?? 'Grey',
      borderColorValue: hadPersistedCanvasImage
          ? 0xFFFFFFFF
          : (json['borderColorValue'] as num?)?.toInt() ??
                _legacyColorValue(
                  json['borderColorLabel'] as String?,
                  0xFFFFFFFF,
                ),
      backgroundColorValue:
          (json['backgroundColorValue'] as num?)?.toInt() ??
          _legacyColorValue(
            json['backgroundColorLabel'] as String?,
            0xFFD0D5DD,
          ),
    );
  }

  static int _legacyColorValue(String? label, int fallback) => switch (label) {
    'White' => 0xFFFFFFFF,
    'Grey' => 0xFFD0D5DD,
    'Ink' => 0xFF101217,
    'Coral' => 0xFFFF7A59,
    'Aqua' => 0xFF4CC9C0,
    'Transparent' => 0x00000000,
    _ => fallback,
  };
}

class EditorSettingsStore {
  const EditorSettingsStore();

  static const _settingsFileName = 'editor_settings.json';
  static const _exportHistoryFileName = 'export_history.json';

  Future<PersistedEditorSettings?> load() async {
    try {
      final settingsFile = await _settingsFile();
      if (!await settingsFile.exists()) {
        return null;
      }

      final rawSettings = await settingsFile.readAsString();
      if (rawSettings.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(rawSettings);
      if (decoded is! Map) {
        return null;
      }
      return PersistedEditorSettings.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PersistedEditorSettings settings) async {
    try {
      final settingsFile = await _settingsFile();
      await settingsFile.parent.create(recursive: true);
      await settingsFile.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Ignore local persistence failures to keep the editor responsive.
    }
  }

  Future<List<ExportHistoryEntry>> loadExportHistory() async {
    try {
      final historyFile = await _exportHistoryFile();
      if (!await historyFile.exists()) {
        return const <ExportHistoryEntry>[];
      }

      final rawHistory = await historyFile.readAsString();
      if (rawHistory.isEmpty) {
        return const <ExportHistoryEntry>[];
      }

      final decoded = jsonDecode(rawHistory);
      if (decoded is! List) {
        return const <ExportHistoryEntry>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                ExportHistoryEntry.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((entry) => entry.path.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <ExportHistoryEntry>[];
    }
  }

  Future<List<ExportHistoryEntry>> addExportHistoryEntry(
    ExportHistoryEntry entry,
  ) async {
    try {
      final existing = await loadExportHistory();
      final updated = <ExportHistoryEntry>[
        entry,
        ...existing.where((candidate) => candidate.path != entry.path),
      ].take(5).toList(growable: false);

      final historyFile = await _exportHistoryFile();
      await historyFile.parent.create(recursive: true);
      await historyFile.writeAsString(
        jsonEncode(
          updated.map((item) => item.toJson()).toList(growable: false),
        ),
      );
      return updated;
    } catch (_) {
      return await loadExportHistory();
    }
  }

  Future<File> _settingsFile() async {
    return File(p.join((await _supportDirectory()).path, _settingsFileName));
  }

  Future<File> _exportHistoryFile() async {
    return File(
      p.join((await _supportDirectory()).path, _exportHistoryFileName),
    );
  }

  Future<Directory> _supportDirectory() async {
    final homeDirectory = Platform.environment['HOME'];
    if (homeDirectory == null || homeDirectory.isEmpty) {
      throw const FileSystemException('HOME is not available.');
    }

    return Directory(
      p.join(
        homeDirectory,
        'Library',
        'Application Support',
        'video_collage_mac',
      ),
    );
  }
}
