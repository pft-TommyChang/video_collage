import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_collage_mac/src/services/c2pa_trust_list_service.dart';

void main() {
  final validPem = utf8.encode(
    '-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----\n',
  );

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
        expect(uri, C2paTrustListService.officialTrustListUri);
        return validPem;
      },
    );

    expect(await service.refreshIfNeeded(), isTrue);
    expect(downloadCount, 1);
    expect(await service.refreshIfNeeded(), isFalse);
    expect(downloadCount, 1);

    final settingsPath = await service.settingsPathFor('/tools/c2patool');
    expect(settingsPath, p.join(supportDirectory.path, 'c2pa', 'c2pa.toml'));
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
    final service = C2paTrustListService(
      supportDirectoryProvider: () async => supportDirectory,
    );

    expect(
      await service.settingsPathFor(p.join(toolDirectory.path, 'c2patool')),
      p.join(toolDirectory.path, 'c2pa.toml'),
    );
  });
}
