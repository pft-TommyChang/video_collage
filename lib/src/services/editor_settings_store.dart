import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PersistedEditorSettings {
  const PersistedEditorSettings({
    required this.rows,
    required this.columns,
    required this.borderThickness,
    required this.tileCornerRadius,
    required this.outputWidth,
    required this.outputHeight,
    required this.aspectLabel,
    required this.resolutionLabel,
    required this.borderColorLabel,
    required this.backgroundColorLabel,
  });

  final int rows;
  final int columns;
  final double borderThickness;
  final double tileCornerRadius;
  final int outputWidth;
  final int outputHeight;
  final String aspectLabel;
  final String resolutionLabel;
  final String borderColorLabel;
  final String backgroundColorLabel;

  Map<String, Object> toJson() {
    return <String, Object>{
      'rows': rows,
      'columns': columns,
      'borderThickness': borderThickness,
      'tileCornerRadius': tileCornerRadius,
      'outputWidth': outputWidth,
      'outputHeight': outputHeight,
      'aspectLabel': aspectLabel,
      'resolutionLabel': resolutionLabel,
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
      outputWidth: (json['outputWidth'] as num?)?.toInt() ?? 1920,
      outputHeight: (json['outputHeight'] as num?)?.toInt() ?? 1080,
      aspectLabel: json['aspectLabel'] as String? ?? '16:9',
      resolutionLabel: json['resolutionLabel'] as String? ?? 'Full HD 1080',
      borderColorLabel: json['borderColorLabel'] as String? ?? 'White',
      backgroundColorLabel: json['backgroundColorLabel'] as String? ?? 'Grey',
    );
  }
}

class EditorSettingsStore {
  const EditorSettingsStore();

  static const _settingsFileName = 'editor_settings.json';

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
        Map<String, dynamic>.from(decoded as Map),
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

  Future<File> _settingsFile() async {
    final homeDirectory = Platform.environment['HOME'];
    if (homeDirectory == null || homeDirectory.isEmpty) {
      throw const FileSystemException('HOME is not available.');
    }

    return File(
      p.join(
        homeDirectory,
        'Library',
        'Application Support',
        'video_collage_mac',
        _settingsFileName,
      ),
    );
  }
}
