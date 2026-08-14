import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

class AiMetadataService {
  const AiMetadataService();

  Future<AiMediaMetadata> probe(String filePath) async {
    final results = await Future.wait<AiMediaMetadata>(
      <Future<AiMediaMetadata>>[
        _probeC2pa(filePath),
        _probeContainerMetadata(filePath),
      ],
    );
    return merge(results[0], results[1]);
  }

  static AiMediaMetadata merge(
    AiMediaMetadata c2pa,
    AiMediaMetadata container,
  ) {
    return AiMediaMetadata(
      c2paStatus: c2pa.c2paStatus,
      vendor: c2pa.vendor ?? container.vendor,
      model: c2pa.model ?? container.model,
    );
  }

  Future<AiMediaMetadata> _probeC2pa(String filePath) async {
    final executable = _findC2paTool();
    if (executable == null) {
      return const AiMediaMetadata();
    }

    try {
      final result = await Process.run(executable, <String>[filePath]);
      if (result.exitCode != 0) {
        final message = '${result.stdout}\n${result.stderr}'.toLowerCase();
        return AiMediaMetadata(
          c2paStatus: message.contains('no claim found')
              ? C2paStatus.absent
              : C2paStatus.unknown,
        );
      }
      return parseC2paJson(result.stdout as String);
    } on FormatException {
      return const AiMediaMetadata(c2paStatus: C2paStatus.present);
    } on ProcessException {
      return const AiMediaMetadata();
    }
  }

  String? _findC2paTool() {
    final executableDirectory = p.dirname(Platform.resolvedExecutable);
    final executableName = Platform.isWindows ? 'c2patool.exe' : 'c2patool';
    final pathCandidates = (Platform.environment['PATH'] ?? '')
        .split(Platform.isWindows ? ';' : ':')
        .where((directory) => directory.isNotEmpty)
        .map((directory) => p.join(directory, executableName));
    final candidates = <String>[
      p.join(executableDirectory, executableName),
      p.normalize(
        p.join(executableDirectory, '..', 'Resources', executableName),
      ),
      '/opt/homebrew/bin/c2patool',
      '/usr/local/bin/c2patool',
      ...pathCandidates,
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<AiMediaMetadata> _probeContainerMetadata(String filePath) async {
    if (_isPhotoPath(filePath)) {
      return const AiMediaMetadata();
    }
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final returnCode = await session.getReturnCode();
      final information = session.getMediaInformation();
      if (!ReturnCode.isSuccess(returnCode) || information == null) {
        return const AiMediaMetadata();
      }
      return parseContainerTags(information.getTags());
    } catch (_) {
      return const AiMediaMetadata();
    }
  }

  static AiMediaMetadata parseC2paJson(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('C2PA output is not an object.');
    }
    final manifests = root['manifests'];
    if (manifests is! Map || manifests.isEmpty) {
      return const AiMediaMetadata(c2paStatus: C2paStatus.absent);
    }

    final activeLabel = root['active_manifest'];
    final active = manifests[activeLabel] ?? manifests.values.first;
    if (active is! Map) {
      return const AiMediaMetadata(c2paStatus: C2paStatus.present);
    }

    String? vendor;
    String? model;
    final signatureInfo = active['signature_info'];
    if (signatureInfo is Map) {
      vendor = _canonicalVendor(
        _nonEmptyString(signatureInfo['issuer']) ??
            _nonEmptyString(signatureInfo['common_name']),
      );
    }

    final assertions = active['assertions'];
    if (assertions is List) {
      for (final assertion in assertions.whereType<Map>()) {
        final label = _nonEmptyString(assertion['label']);
        final data = assertion['data'];
        if (label == 'c2pa.ai-disclosure' && data is Map) {
          model ??= _nonEmptyString(data['modelName']);
        }
        if (label == 'c2pa.creative_work' && data is Map) {
          final authors = data['author'];
          if (authors is List && authors.isNotEmpty && authors.first is Map) {
            vendor ??= _canonicalVendor(
              _nonEmptyString((authors.first as Map)['name']),
            );
          }
        }
        if (label != 'c2pa.actions.v2' || data is! Map) {
          continue;
        }
        final actions = data['actions'];
        if (actions is! List) {
          continue;
        }
        for (final action in actions.whereType<Map>()) {
          final parameters = action['parameters'];
          if (parameters is Map) {
            model ??= _nonEmptyString(parameters['model_name']);
          }
          final softwareAgent = action['softwareAgent'];
          final agentName = softwareAgent is Map
              ? _nonEmptyString(softwareAgent['name'])
              : _nonEmptyString(softwareAgent);
          vendor ??= _vendorFromAgent(agentName);
          model ??= _modelFromAgent(agentName, softwareAgent);
        }
      }
    }

    final validationStatuses = root['validation_status'];
    final validationCodes = validationStatuses is List
        ? validationStatuses
              .whereType<Map>()
              .map((item) => _nonEmptyString(item['code']))
              .whereType<String>()
              .toSet()
        : const <String>{};
    final validationResults = root['validation_results'];
    final activeManifest = validationResults is Map
        ? validationResults['activeManifest']
        : null;
    final successes = activeManifest is Map ? activeManifest['success'] : null;
    final successCodes = successes is List
        ? successes
              .whereType<Map>()
              .map((item) => _nonEmptyString(item['code']))
              .whereType<String>()
              .toSet()
        : const <String>{};
    final status =
        validationCodes.any(
          (code) => code.contains('mismatch') || code.contains('invalid'),
        )
        ? C2paStatus.invalid
        : successCodes.contains('claimSignature.validated')
        ? C2paStatus.signed
        : C2paStatus.present;

    return AiMediaMetadata(c2paStatus: status, vendor: vendor, model: model);
  }

  static AiMediaMetadata parseContainerTags(Map<dynamic, dynamic>? tags) {
    if (tags == null) {
      return const AiMediaMetadata();
    }
    final normalized = <String, dynamic>{
      for (final entry in tags.entries)
        entry.key.toString().toLowerCase(): entry.value,
    };

    final heygen = _decodeJsonMap(normalized['heygen-wm']);
    if (heygen != null) {
      return AiMediaMetadata(
        vendor: _nonEmptyString(heygen['provider']) ?? 'HeyGen',
        model: _nonEmptyString(heygen['model']),
      );
    }

    final aigc = _decodeJsonMap(normalized['aigc']);
    if (aigc != null) {
      final produceId = _nonEmptyString(aigc['ProduceID'] ?? aigc['produceId']);
      if (produceId != null && produceId.startsWith('character2video-')) {
        final match = RegExp(
          r'^(character2video-[0-9]+(?:\.[0-9]+)?)',
        ).firstMatch(produceId);
        return AiMediaMetadata(
          vendor: 'Vidu',
          model: match?.group(1) ?? 'character2video',
        );
      }
    }

    return const AiMediaMetadata();
  }

  static Map<String, dynamic>? _decodeJsonMap(dynamic value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is! String || value.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      return decoded is Map
          ? decoded.map((key, item) => MapEntry(key.toString(), item))
          : null;
    } on FormatException {
      return null;
    }
  }

  static String? _modelFromAgent(String? name, dynamic softwareAgent) {
    if (name == null ||
        !(name.startsWith('gpt-image') ||
            name.startsWith('FLUX') ||
            name == 'Grok Imagine')) {
      return null;
    }
    final version = softwareAgent is Map
        ? _nonEmptyString(softwareAgent['version'])
        : null;
    return version == null ? name : '$name $version';
  }

  static String? _vendorFromAgent(String? name) {
    if (name == null) {
      return null;
    }
    if (name.contains('BytePlus')) return 'BytePlus';
    if (name.contains('Runway')) return 'Runway';
    if (name.contains('Grok')) return 'xAI';
    if (name.startsWith('gpt-image')) return 'OpenAI';
    if (name.startsWith('FLUX')) return 'Black Forest Labs';
    return null;
  }

  static String? _canonicalVendor(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    if (lower.contains('self-signed') || lower.contains('local use only')) {
      return null;
    }
    if (lower.contains('byteplus')) return 'BytePlus';
    if (lower.contains('black forest')) return 'Black Forest Labs';
    if (lower.contains('google')) return 'Google';
    if (lower.contains('openai')) return 'OpenAI';
    if (lower.contains('runway')) return 'Runway';
    if (lower.contains('spacexai') || lower.contains('xai')) return 'xAI';
    if (lower.contains('heygen')) return 'HeyGen';
    return value;
  }

  static String? _nonEmptyString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isPhotoPath(String path) {
    return const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp',
      '.gif',
      '.heic',
      '.heif',
    }.contains(p.extension(path).toLowerCase());
  }
}
