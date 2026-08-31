import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/services/ai_metadata_service.dart';
import 'package:video_collage_mac/src/services/c2pa_export_service.dart';

void main() {
  test('manifest identifies Perfect Collage and carries ingredients', () {
    final ingredient = <String, dynamic>{'title': 'source.jpg'};
    final manifest = C2paExportService.buildManifest(
      ingredients: <Map<String, dynamic>>[ingredient],
      signingCertificatePath: '/signing/perfect_collage_cert.pem',
      signingPrivateKeyPath: '/signing/perfect_collage_private.key',
    );

    expect(manifest['alg'], 'es256');
    expect(manifest['sign_cert'], '/signing/perfect_collage_cert.pem');
    expect(manifest['private_key'], '/signing/perfect_collage_private.key');
    expect(manifest['claim_generator'], 'Perfect Collage');
    expect(manifest['title'], 'pfc asset');
    expect(manifest['ingredients'], <Map<String, dynamic>>[ingredient]);
  });

  test(
    'does not run c2patool when every source is known to lack C2PA',
    () async {
      var processCalls = 0;
      final service = C2paExportService(
        aiMetadataService: const AiMetadataService(),
        toolLocator: () => '/tools/c2patool',
        processRunner: (executable, arguments) async {
          processCalls += 1;
          return ProcessResult(1, 0, '', '');
        },
      );

      final signed = await service.signExportIfNeeded(
        sources: const <C2paSourceAsset>[
          C2paSourceAsset(
            path: '/media/a.jpg',
            metadata: AiMediaMetadata(c2paStatus: C2paStatus.absent),
          ),
          C2paSourceAsset(
            path: '/media/b.mp4',
            metadata: AiMediaMetadata(c2paStatus: C2paStatus.absent),
          ),
        ],
        outputPath: '/exports/result.mp4',
      );

      expect(signed, isFalse);
      expect(processCalls, 0);
    },
  );

  test('requires c2patool when a source has C2PA', () async {
    final service = C2paExportService(
      aiMetadataService: const AiMetadataService(),
      toolLocator: () => null,
    );

    expect(
      () => service.signExportIfNeeded(
        sources: const <C2paSourceAsset>[
          C2paSourceAsset(
            path: '/media/a.jpg',
            metadata: AiMediaMetadata(c2paStatus: C2paStatus.conformant),
          ),
        ],
        outputPath: '/exports/result.jpg',
      ),
      throwsA(isA<C2paExportException>()),
    );
  });

  test(
    'does not publish unknown C2PA inspection as an unsigned result',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'c2pa_unknown_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final source = File('${directory.path}/source.jpg');
      final output = File('${directory.path}/output.jpg');
      await source.writeAsString('source');
      await output.writeAsString('rendered');
      final service = C2paExportService(
        aiMetadataService: const _UnknownAiMetadataService(),
        toolLocator: () => '/tools/c2patool',
      );

      expect(
        () => service.signExportIfNeeded(
          sources: <C2paSourceAsset>[
            C2paSourceAsset(
              path: source.path,
              metadata: const AiMediaMetadata(),
            ),
          ],
          outputPath: output.path,
        ),
        throwsA(isA<C2paExportException>()),
      );
    },
  );

  test(
    'preserves all inputs and replaces the export with signed media',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'c2pa_export_service_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final parent = File('${directory.path}/parent.jpg');
      final component = File('${directory.path}/component.jpg');
      final output = File('${directory.path}/output.jpg');
      await parent.writeAsString('parent');
      await component.writeAsString('component');
      await output.writeAsString('unsigned export');
      final calls = <List<String>>[];
      String? stagedParentContents;

      final service = C2paExportService(
        aiMetadataService: const AiMetadataService(),
        toolLocator: () => '/tools/c2patool',
        thumbnailGenerator: (sourcePath, outputPath) async {
          await File(outputPath).writeAsString('thumbnail');
          return true;
        },
        assetLoader: (assetPath) async => assetPath.endsWith('.key')
            ? 'test private key'
            : 'test signing certificate',
        processRunner: (executable, arguments) async {
          calls.add(arguments);
          final outputIndex = arguments.indexOf('--output');
          final destination = arguments[outputIndex + 1];
          if (arguments.contains('--ingredient')) {
            final ingredientDirectory = Directory(destination);
            await ingredientDirectory.create();
            await File(
              '${ingredientDirectory.path}/ingredient.json',
            ).writeAsString(
              '{"format":"image/jpeg","relationship":"componentOf"}',
            );
          } else {
            final parentIndex = arguments.indexOf('--parent');
            stagedParentContents = await File(
              '${arguments[parentIndex + 1]}/ingredient.json',
            ).readAsString();
            await File(destination).writeAsString('signed export');
          }
          return ProcessResult(1, 0, '', '');
        },
      );

      final signed = await service.signExportIfNeeded(
        sources: <C2paSourceAsset>[
          C2paSourceAsset(
            path: parent.path,
            metadata: const AiMediaMetadata(c2paStatus: C2paStatus.conformant),
          ),
          C2paSourceAsset(
            path: component.path,
            metadata: const AiMediaMetadata(c2paStatus: C2paStatus.absent),
          ),
        ],
        outputPath: output.path,
      );

      expect(signed, isTrue);
      expect(await output.readAsString(), 'signed export');
      expect(calls, hasLength(3));
      expect(calls.first, contains('--ingredient'));
      final parentIndex = calls.last.indexOf('--parent');
      expect(parentIndex, greaterThanOrEqualTo(0));
      final stagedParentPath = calls.last[parentIndex + 1];
      expect(stagedParentPath, isNot(parent.path));
      expect(stagedParentContents, contains('thumbnail.jpg'));
    },
  );
}

class _UnknownAiMetadataService extends AiMetadataService {
  const _UnknownAiMetadataService();

  @override
  Future<AiMediaMetadata> probeC2pa(String filePath) async {
    return const AiMediaMetadata();
  }
}
