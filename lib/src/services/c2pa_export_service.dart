import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import 'ai_metadata_service.dart';

typedef C2paProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef C2paThumbnailGenerator =
    Future<bool> Function(String sourcePath, String outputPath);
typedef C2paAssetLoader = Future<String> Function(String assetPath);

class C2paExportException implements Exception {
  const C2paExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class C2paSourceAsset {
  const C2paSourceAsset({required this.path, required this.metadata});

  final String path;
  final AiMediaMetadata metadata;
}

/// Adds provenance only when at least one source asset already has C2PA.
///
/// The first C2PA source becomes the parent. Every other unique source is
/// recorded as an ingredient, so the new claim carries both signed provenance
/// and the complete set of inputs used to create the export.
class C2paExportService {
  static const _signingCertificateAsset =
      'assets/c2pa/perfect_collage_cert.pem';
  static const _signingPrivateKeyAsset =
      'assets/c2pa/perfect_collage_private.key';

  C2paExportService({
    required AiMetadataService aiMetadataService,
    C2paProcessRunner? processRunner,
    C2paThumbnailGenerator? thumbnailGenerator,
    C2paAssetLoader? assetLoader,
    String? Function()? toolLocator,
  }) : _aiMetadataService = aiMetadataService,
       _processRunner = processRunner ?? _runProcess,
       _thumbnailGenerator = thumbnailGenerator,
       _assetLoader = assetLoader ?? rootBundle.loadString,
       _toolLocator = toolLocator ?? AiMetadataService.findC2paTool;

  final AiMetadataService _aiMetadataService;
  final C2paProcessRunner _processRunner;
  final C2paThumbnailGenerator? _thumbnailGenerator;
  final C2paAssetLoader _assetLoader;
  final String? Function() _toolLocator;

  Future<bool> signExportIfNeeded({
    required Iterable<C2paSourceAsset> sources,
    required String outputPath,
  }) async {
    final uniqueSources = <C2paSourceAsset>[];
    final seenPaths = <String>{};
    for (final source in sources) {
      final normalized = p.normalize(p.absolute(source.path));
      if (seenPaths.add(normalized)) {
        uniqueSources.add(
          C2paSourceAsset(path: normalized, metadata: source.metadata),
        );
      }
    }
    if (uniqueSources.isEmpty) return false;

    final hasKnownC2pa = uniqueSources.any((source) => source.metadata.hasC2pa);
    final needsProbe = uniqueSources.any(
      (source) => source.metadata.c2paStatus == C2paStatus.unknown,
    );
    if (!hasKnownC2pa && !needsProbe) return false;

    final executable = _toolLocator();
    if (executable == null) {
      throw const C2paExportException(
        'A source contains C2PA, but c2patool is not available to preserve it.',
      );
    }

    final workDirectory = await Directory.systemTemp.createTemp(
      'perfect_collage_c2pa_export_',
    );
    try {
      // A sandboxed child process does not reliably receive the temporary
      // Powerbox permissions granted to the parent app for files in Downloads
      // or other user-selected locations. Give c2patool only app-owned paths.
      final stagedSources = <C2paSourceAsset>[];
      for (var index = 0; index < uniqueSources.length; index += 1) {
        final source = uniqueSources[index];
        final stagedPath = p.join(
          workDirectory.path,
          'source_$index${p.extension(source.path).toLowerCase()}',
        );
        await File(source.path).copy(stagedPath);
        final metadata = source.metadata.c2paStatus == C2paStatus.unknown
            ? await _aiMetadataService.probeC2pa(stagedPath)
            : source.metadata;
        if (metadata.c2paStatus == C2paStatus.unknown) {
          throw const C2paExportException(
            'Could not inspect source Content Credentials with c2patool.',
          );
        }
        stagedSources.add(
          C2paSourceAsset(path: stagedPath, metadata: metadata),
        );
      }
      C2paSourceAsset? parent;
      for (final source in stagedSources) {
        if (source.metadata.hasC2pa) {
          parent = source;
          break;
        }
      }
      if (parent == null) return false;

      final ingredients = <Map<String, dynamic>>[];
      var ingredientIndex = 0;
      for (final source in stagedSources) {
        final isParent = source.path == parent.path;
        final folderName = isParent
            ? 'parent'
            : 'ingredient_${ingredientIndex++}';
        final ingredientDirectory = Directory(
          p.join(workDirectory.path, folderName),
        );
        final result = await _processRunner(executable, <String>[
          source.path,
          '--ingredient',
          '--output',
          ingredientDirectory.path,
        ]);
        _requireSuccess(result, 'Could not preserve a C2PA ingredient');
        final ingredientFile = File(
          p.join(ingredientDirectory.path, 'ingredient.json'),
        );
        final decoded = jsonDecode(await ingredientFile.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const C2paExportException(
            'c2patool produced an invalid ingredient definition.',
          );
        }
        await _ensureThumbnail(
          definition: decoded,
          sourcePath: source.path,
          directory: ingredientDirectory,
        );
        if (isParent) {
          // Parent ingredient resources are resolved from the main manifest's
          // base directory when c2patool combines the definitions.
          _prefixResourceIdentifiers(decoded, folderName);
          await ingredientFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(decoded),
          );
        } else {
          _prefixResourceIdentifiers(decoded, folderName);
          ingredients.add(decoded);
        }
      }

      final renderedPath = p.join(
        workDirectory.path,
        'rendered${p.extension(outputPath).toLowerCase()}',
      );
      await File(outputPath).copy(renderedPath);
      final claimThumbnailPath = p.join(
        workDirectory.path,
        'claim-thumbnail.jpg',
      );
      final generatedClaimThumbnail =
          await _thumbnailGenerator?.call(renderedPath, claimThumbnailPath) ??
          false;
      if (!generatedClaimThumbnail ||
          !await File(claimThumbnailPath).exists()) {
        throw const C2paExportException(
          'Could not create the Content Credentials thumbnail.',
        );
      }
      final signingCertificatePath = p.join(
        workDirectory.path,
        'perfect_collage_cert.pem',
      );
      final signingPrivateKeyPath = p.join(
        workDirectory.path,
        'perfect_collage_private.key',
      );
      await Future.wait(<Future<File>>[
        File(
          signingCertificatePath,
        ).writeAsString(await _assetLoader(_signingCertificateAsset)),
        File(
          signingPrivateKeyPath,
        ).writeAsString(await _assetLoader(_signingPrivateKeyAsset)),
      ]);
      final manifestFile = File(p.join(workDirectory.path, 'manifest.json'));
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          buildManifest(
            ingredients: ingredients,
            thumbnail: const <String, String>{
              'format': 'image/jpeg',
              'identifier': 'claim-thumbnail.jpg',
            },
            signingCertificatePath: signingCertificatePath,
            signingPrivateKeyPath: signingPrivateKeyPath,
          ),
        ),
      );
      final signedPath = p.join(
        workDirectory.path,
        'signed${p.extension(outputPath).toLowerCase()}',
      );
      final signResult = await _processRunner(executable, <String>[
        renderedPath,
        '--manifest',
        manifestFile.path,
        '--parent',
        p.join(workDirectory.path, 'parent'),
        '--force',
        '--output',
        signedPath,
      ]);
      _requireSuccess(signResult, 'Could not sign the exported media');
      await File(signedPath).copy(outputPath);
      return true;
    } on C2paExportException {
      rethrow;
    } on Object catch (error) {
      throw C2paExportException('Could not preserve C2PA provenance: $error');
    } finally {
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  static Map<String, dynamic> buildManifest({
    required List<Map<String, dynamic>> ingredients,
    Map<String, String>? thumbnail,
    String? signingCertificatePath,
    String? signingPrivateKeyPath,
  }) {
    final manifest = <String, dynamic>{
      'claim_generator': 'Perfect Collage',
      'claim_generator_info': <Map<String, String>>[
        <String, String>{'name': 'Perfect Collage'},
      ],
      'title': 'pfc asset',
      'assertions': <Object>[],
      if (ingredients.isNotEmpty) 'ingredients': ingredients,
    };
    if (signingCertificatePath != null) {
      manifest['sign_cert'] = signingCertificatePath;
    }
    if (signingPrivateKeyPath != null) {
      manifest['private_key'] = signingPrivateKeyPath;
    }
    if (signingCertificatePath != null || signingPrivateKeyPath != null) {
      manifest['alg'] = 'es256';
    }
    if (thumbnail != null) manifest['thumbnail'] = thumbnail;
    return manifest;
  }

  Future<void> _ensureThumbnail({
    required Map<String, dynamic> definition,
    required String sourcePath,
    required Directory directory,
  }) async {
    if (definition['thumbnail'] is Map) return;
    final thumbnailPath = p.join(directory.path, 'thumbnail.jpg');
    final generated =
        await _thumbnailGenerator?.call(sourcePath, thumbnailPath) ?? false;
    if (!generated || !await File(thumbnailPath).exists()) {
      throw C2paExportException(
        'Could not create a Content Credentials thumbnail for '
        '${p.basename(sourcePath)}.',
      );
    }
    definition['thumbnail'] = <String, String>{
      'format': 'image/jpeg',
      'identifier': 'thumbnail.jpg',
    };
  }

  static void _prefixResourceIdentifiers(
    Map<String, dynamic> ingredient,
    String folderName,
  ) {
    for (final key in const <String>['thumbnail', 'manifest_data']) {
      final resource = ingredient[key];
      if (resource is Map && resource['identifier'] is String) {
        resource['identifier'] = p.posix.join(
          folderName,
          resource['identifier'] as String,
        );
      }
    }
  }

  static void _requireSuccess(ProcessResult result, String message) {
    if (result.exitCode == 0) return;
    final details = '${result.stderr}'.trim();
    throw C2paExportException(details.isEmpty ? message : '$message: $details');
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }
}
