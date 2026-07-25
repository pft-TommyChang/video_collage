import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    required this.borderThickness,
    required this.tileCornerRadius,
    required this.clipLabelFontSize,
    required this.includeClipLabelsInOutput,
    required this.showClipLabelIndex,
    required this.outputWidth,
    required this.outputHeight,
    required this.aspectLabel,
    required this.resolutionLabel,
    required this.audioMode,
    required this.durationMode,
    required this.appendDateTimeToExportName,
    required this.lastExportDirectory,
    required this.borderColorLabel,
    required this.backgroundColorLabel,
  });

  final int rows;
  final int columns;
  final double borderThickness;
  final double tileCornerRadius;
  final double clipLabelFontSize;
  final bool includeClipLabelsInOutput;
  final bool showClipLabelIndex;
  final int outputWidth;
  final int outputHeight;
  final String aspectLabel;
  final String resolutionLabel;
  final String audioMode;
  final String durationMode;
  final bool appendDateTimeToExportName;
  final String lastExportDirectory;
  final String borderColorLabel;
  final String backgroundColorLabel;

  Map<String, Object> toJson() {
    return <String, Object>{
      'rows': rows,
      'columns': columns,
      'borderThickness': borderThickness,
      'tileCornerRadius': tileCornerRadius,
      'clipLabelFontSize': clipLabelFontSize,
      'includeClipLabelsInOutput': includeClipLabelsInOutput,
      'showClipLabelIndex': showClipLabelIndex,
      'outputWidth': outputWidth,
      'outputHeight': outputHeight,
      'aspectLabel': aspectLabel,
      'resolutionLabel': resolutionLabel,
      'audioMode': audioMode,
      'durationMode': durationMode,
      'appendDateTimeToExportName': appendDateTimeToExportName,
      'lastExportDirectory': lastExportDirectory,
      'borderColorLabel': borderColorLabel,
      'backgroundColorLabel': backgroundColorLabel,
    };
  }

  factory PersistedEditorSettings.fromJson(Map<String, dynamic> json) {
    return PersistedEditorSettings(
      rows: (json['rows'] as num?)?.toInt() ?? 2,
      columns: (json['columns'] as num?)?.toInt() ?? 2,
      borderThickness: (json['borderThickness'] as num?)?.toDouble() ?? 12,
      tileCornerRadius: (json['tileCornerRadius'] as num?)?.toDouble() ?? 12,
      clipLabelFontSize: (json['clipLabelFontSize'] as num?)?.toDouble() ?? 12,
      includeClipLabelsInOutput:
          json['includeClipLabelsInOutput'] as bool? ?? false,
      showClipLabelIndex: json['showClipLabelIndex'] as bool? ?? false,
      outputWidth: (json['outputWidth'] as num?)?.toInt() ?? 1920,
      outputHeight: (json['outputHeight'] as num?)?.toInt() ?? 1080,
      aspectLabel: json['aspectLabel'] as String? ?? '16:9',
      resolutionLabel: json['resolutionLabel'] as String? ?? 'Full HD 1080',
      audioMode: json['audioMode'] as String? ?? 'firstClip',
      durationMode: json['durationMode'] as String? ?? 'longest',
      appendDateTimeToExportName:
          json['appendDateTimeToExportName'] as bool? ?? false,
      lastExportDirectory: json['lastExportDirectory'] as String? ?? '',
      borderColorLabel: json['borderColorLabel'] as String? ?? 'White',
      backgroundColorLabel: json['backgroundColorLabel'] as String? ?? 'Grey',
    );
  }
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
            (entry) => ExportHistoryEntry.fromJson(
              Map<String, dynamic>.from(entry),
            ),
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
        jsonEncode(updated.map((item) => item.toJson()).toList(growable: false)),
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
    return File(p.join((await _supportDirectory()).path, _exportHistoryFileName));
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
