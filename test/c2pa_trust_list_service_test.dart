import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_collage_mac/src/services/c2pa_trust_list_service.dart';

void main() {
  final validPem = utf8.encode(
    '-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----\n',
  );
  final validMetadata = utf8.encode(
    jsonEncode(<String, Object>{
      'LoTE': <String, Object>{
        'ListAndSchemeInformation': <String, Object>{
          'LoTEVersionIdentifier': 1,
          'LoTESequenceNumber': 7,
          'ListIssueDateTime': '2026-08-05T00:11:39Z',
        },
      },
    }),
  );
  final validAllowedList = utf8.encode(
    '${base64.encode(List<int>.filled(32, 1))}\n',
  );
  final validTrustConfig = utf8.encode('1.3.6.1.5.5.7.3.4\n');

  List<int> downloadFor(Uri uri) {
    if (uri == C2paTrustListService.officialTrustListUri ||
        uri == C2paTrustListService.legacyTrustAnchorsUri) {
      return validPem;
    }
    if (uri == C2paTrustListService.officialTrustListMetadataUri) {
      return validMetadata;
    }
    if (uri == C2paTrustListService.legacyAllowedListUri) {
      return validAllowedList;
    }
    if (uri == C2paTrustListService.legacyTrustConfigUri) {
      return validTrustConfig;
    }
    throw StateError('Unexpected URI: $uri');
  }

  test('downloads and selects the official trust list cache', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'c2pa_trust_test_',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    var downloadCount = 0;
    final service = C2paTrustListService(
      supportDirectoryProvider: () async => supportDirectory,
      downloader: (uri) async {
        downloadCount++;
        return downloadFor(uri);
      },
    );

    expect(await service.refreshIfNeeded(), isTrue);
    expect(downloadCount, 5);
    expect(await service.refreshIfNeeded(), isFalse);
    expect(downloadCount, 5);

    final settingsPath = await service.settingsPathFor('/tools/c2patool');
    expect(settingsPath, p.join(supportDirectory.path, 'c2pa', 'c2pa.toml'));
    final version = await service.versionFor('/tools/c2patool');
    expect(version?.label, 'v1.7');
    expect(version?.issueDate, DateTime.utc(2026, 8, 5, 0, 11, 39));
    final plan = await service.verificationPlanFor(
      '/tools/c2patool',
      '/media/video.mp4',
    );
    expect(plan.officialArguments, <String>[
      '/media/video.mp4',
      'trust',
      '--trust_anchors',
      p.join(supportDirectory.path, 'c2pa', 'c2pa-trust-list.pem'),
    ]);
    expect(plan.legacyArguments, <String>[
      '/media/video.mp4',
      'trust',
      '--trust_anchors',
      p.join(supportDirectory.path, 'c2pa', 'c2pa-trust-list-legacy.pem'),
      '--allowed_list',
      p.join(supportDirectory.path, 'c2pa', 'c2pa-trust-allowed.sha256.txt'),
      '--trust_config',
      p.join(supportDirectory.path, 'c2pa', 'c2pa-trust-store.cfg'),
    ]);
  });

  test('keeps a valid stale cache when downloading fails', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'c2pa_trust_test_',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final trustList = File(
      p.join(supportDirectory.path, 'c2pa', 'c2pa-trust-list.pem'),
    );
    await trustList.parent.create(recursive: true);
    await trustList.writeAsBytes(validPem);
    await trustList.setLastModified(DateTime(2020));
    final service = C2paTrustListService(
      supportDirectoryProvider: () async => supportDirectory,
      now: () => DateTime(2026),
      downloader: (_) async => throw const SocketException('offline'),
    );

    expect(await service.refreshIfNeeded(), isFalse);
    expect(await trustList.readAsBytes(), validPem);
    expect(
      await service.settingsPathFor('/tools/c2patool'),
      p.join(supportDirectory.path, 'c2pa', 'c2pa.toml'),
    );
  });

  test('rejects an invalid downloaded trust list', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'c2pa_trust_test_',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final service = C2paTrustListService(
      supportDirectoryProvider: () async => supportDirectory,
      downloader: (_) async => utf8.encode('<html>not a trust list</html>'),
    );

    expect(await service.refreshIfNeeded(), isFalse);
    expect(
      File(
        p.join(supportDirectory.path, 'c2pa', 'c2pa-trust-list.pem'),
      ).existsSync(),
      isFalse,
    );
  });

  test('falls back to the trust list bundled beside c2patool', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'c2pa_trust_test_',
    );
    final toolDirectory = await Directory.systemTemp.createTemp(
      'c2pa_tool_test_',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    addTearDown(() => toolDirectory.delete(recursive: true));
    await File(
      p.join(toolDirectory.path, 'c2pa-trust-list.pem'),
    ).writeAsBytes(validPem);
    await File(
      p.join(toolDirectory.path, 'c2pa-trust-list.json'),
    ).writeAsBytes(validMetadata);
    await File(
      p.join(toolDirectory.path, 'c2pa-trust-list-legacy.pem'),
    ).writeAsBytes(validPem);
    await File(
      p.join(toolDirectory.path, 'c2pa-trust-allowed.sha256.txt'),
    ).writeAsBytes(validAllowedList);
    await File(
      p.join(toolDirectory.path, 'c2pa-trust-store.cfg'),
    ).writeAsBytes(validTrustConfig);
    final service = C2paTrustListService(
      supportDirectoryProvider: () async => supportDirectory,
    );

    expect(
      await service.settingsPathFor(p.join(toolDirectory.path, 'c2patool')),
      p.join(toolDirectory.path, 'c2pa.toml'),
    );
    expect(
      (await service.versionFor(p.join(toolDirectory.path, 'c2patool')))?.label,
      'v1.7',
    );
    final plan = await service.verificationPlanFor(
      p.join(toolDirectory.path, 'c2patool'),
      '/media/video.mp4',
    );
    expect(
      plan.officialArguments,
      containsAllInOrder(<String>[
        '/media/video.mp4',
        'trust',
        '--trust_anchors',
        p.join(toolDirectory.path, 'c2pa-trust-list.pem'),
      ]),
    );
    expect(
      plan.legacyArguments,
      containsAllInOrder(<String>[
        '/media/video.mp4',
        'trust',
        '--trust_anchors',
        p.join(toolDirectory.path, 'c2pa-trust-list-legacy.pem'),
        '--allowed_list',
        p.join(toolDirectory.path, 'c2pa-trust-allowed.sha256.txt'),
        '--trust_config',
        p.join(toolDirectory.path, 'c2pa-trust-store.cfg'),
      ]),
    );
  });
}
