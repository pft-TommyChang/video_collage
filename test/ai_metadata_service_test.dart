import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/services/ai_metadata_service.dart';

void main() {
  test('parses vendor, model, and conformant state from C2PA', () {
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'manifest-1',
      'manifests': <String, Object>{
        'manifest-1': <String, Object>{
          'signature_info': <String, Object>{'issuer': 'Byteplus Pte. Ltd.'},
          'assertions': <Object>[
            <String, Object>{
              'label': 'c2pa.actions.v2',
              'data': <String, Object>{
                'actions': <Object>[
                  <String, Object>{
                    'parameters': <String, Object>{
                      'model_name': 'dreamina-seedance-2-5',
                    },
                  },
                ],
              },
            },
          ],
        },
      },
      'validation_results': <String, Object>{
        'activeManifest': <String, Object>{
          'success': <Object>[
            <String, Object>{'code': 'claimSignature.validated'},
            <String, Object>{'code': 'signingCredential.trusted'},
          ],
        },
      },
    });

    final metadata = AiMetadataService.parseC2paJson(source);

    expect(metadata.c2paStatus, C2paStatus.conformant);
    expect(metadata.vendor, 'Byteplus Pte. Ltd.');
    expect(metadata.model, 'dreamina-seedance-2-5');
  });

  test('retains manifest history, actions, ingredients, and checks', () {
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'active',
      'manifests': <String, Object>{
        'active': <String, Object>{
          'title': 'collage.mp4',
          'format': 'video/mp4',
          'claim_generator': 'Perfect Collage/1.7.0',
          'signature_info': <String, Object>{
            'issuer': 'Example Studio',
            'alg': 'PS256',
            'time': '2026-08-31T10:00:00Z',
          },
          'ingredients': <Object>[
            <String, Object>{
              'title': 'source.png',
              'format': 'image/png',
              'relationship': 'parentOf',
              'active_manifest': 'source',
            },
          ],
          'assertions': <Object>[
            <String, Object>{
              'label': 'c2pa.actions.v2',
              'data': <String, Object>{
                'actions': <Object>[
                  <String, Object>{
                    'action': 'c2pa.edited',
                    'softwareAgent': 'Perfect Collage',
                  },
                ],
              },
            },
          ],
        },
        'source': <String, Object>{
          'title': 'source.png',
          'signature_info': <String, Object>{'issuer': 'OpenAI'},
        },
      },
      'validation_results': <String, Object>{
        'activeManifest': <String, Object>{
          'success': <Object>[
            <String, Object>{'code': 'claimSignature.validated'},
            <String, Object>{'code': 'signingCredential.trusted'},
          ],
          'failure': <Object>[
            <String, Object>{
              'code': 'ingredient.hashedURI.mismatch',
              'explanation': 'Ingredient bytes changed.',
            },
          ],
        },
      },
    });

    final metadata = AiMetadataService.parseC2paJson(source);
    final report = metadata.c2paReport!;

    expect(report.activeManifestLabel, 'active');
    expect(report.manifests, hasLength(2));
    expect(report.activeManifest?.title, 'collage.mp4');
    expect(report.activeManifest?.issuer, 'Example Studio');
    expect(report.activeManifest?.algorithm, 'PS256');
    expect(report.activeManifest?.actions.single.action, 'c2pa.edited');
    expect(report.activeManifest?.ingredients.single.manifestLabel, 'source');
    expect(report.passedCheckCount, 2);
    expect(report.failedCheckCount, 1);
    expect(report.rawJson, contains('ingredient.hashedURI.mismatch'));
  });

  test('resolves extracted manifest and ingredient thumbnail resources', () {
    final resources = Directory.systemTemp.createTempSync(
      'c2pa_thumbnail_test_',
    );
    addTearDown(() => resources.deleteSync(recursive: true));
    final assertionDirectory = Directory(
      '${resources.path}/urn_c2pa_active/c2pa.assertions',
    )..createSync(recursive: true);
    final claimThumbnail = File('${assertionDirectory.path}/claim-thumb')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final ingredientThumbnail = File(
      '${assertionDirectory.path}/ingredient-thumb',
    )..writeAsBytesSync(<int>[4, 5, 6]);
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'urn:c2pa:active',
      'manifests': <String, Object>{
        'urn:c2pa:active': <String, Object>{
          'thumbnail': <String, Object>{
            'identifier':
                'self#jumbf=/c2pa/urn:c2pa:active/c2pa.assertions/claim-thumb',
          },
          'ingredients': <Object>[
            <String, Object>{
              'thumbnail': <String, Object>{
                'identifier':
                    'self#jumbf=/c2pa/urn:c2pa:active/c2pa.assertions/ingredient-thumb',
              },
            },
          ],
        },
      },
      'validation_results': <String, Object>{
        'activeManifest': <String, Object>{
          'success': <Object>[
            <String, Object>{'code': 'claimSignature.validated'},
            <String, Object>{'code': 'signingCredential.trusted'},
          ],
        },
      },
    });

    final metadata = AiMetadataService.parseC2paJson(
      source,
      resourceDirectory: resources.path,
    );

    expect(metadata.c2paReport?.activeManifest?.thumbnailPath, claimThumbnail.path);
    expect(
      metadata.c2paReport?.activeManifest?.ingredients.single.thumbnailPath,
      ingredientThumbnail.path,
    );
  });

  test('marks a valid signature with an untrusted credential untrusted', () {
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'manifest-1',
      'manifests': <String, Object>{
        'manifest-1': <String, Object>{
          'signature_info': <String, Object>{'issuer': 'Example Inc.'},
        },
      },
      'validation_status': <Object>[
        <String, Object>{'code': 'signingCredential.untrusted'},
      ],
      'validation_results': <String, Object>{
        'activeManifest': <String, Object>{
          'success': <Object>[
            <String, Object>{'code': 'claimSignature.validated'},
          ],
        },
      },
    });

    final metadata = AiMetadataService.parseC2paJson(source);

    expect(metadata.c2paStatus, C2paStatus.untrusted);
  });

  test('does not confuse an untrusted timestamp with an untrusted signer', () {
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'manifest-1',
      'manifests': <String, Object>{
        'manifest-1': <String, Object>{
          'signature_info': <String, Object>{'issuer': 'OpenAI Media Service'},
        },
      },
      'validation_results': <String, Object>{
        'activeManifest': <String, Object>{
          'success': <Object>[
            <String, Object>{'code': 'claimSignature.validated'},
            <String, Object>{'code': 'signingCredential.trusted'},
          ],
          'informational': <Object>[
            <String, Object>{'code': 'timeStamp.untrusted'},
          ],
        },
      },
    });

    final metadata = AiMetadataService.parseC2paJson(source);

    expect(metadata.c2paStatus, C2paStatus.conformant);
    expect(metadata.vendor, 'OpenAI Media Service');
  });

  test('labels a credential trusted only by the legacy pass separately', () {
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'manifest-1',
      'manifests': <String, Object>{
        'manifest-1': <String, Object>{
          'signature_info': <String, Object>{'issuer': 'Legacy signer'},
        },
      },
      'validation_results': <String, Object>{
        'activeManifest': <String, Object>{
          'success': <Object>[
            <String, Object>{'code': 'claimSignature.validated'},
            <String, Object>{'code': 'signingCredential.trusted'},
          ],
        },
      },
    });

    final metadata = AiMetadataService.parseC2paJson(
      source,
      trustedStatus: C2paStatus.legacyTrusted,
    );

    expect(metadata.c2paStatus, C2paStatus.legacyTrusted);
  });

  test('marks a mismatched C2PA claim invalid', () {
    final source = jsonEncode(<String, Object>{
      'active_manifest': 'manifest-1',
      'manifests': <String, Object>{
        'manifest-1': <String, Object>{
          'signature_info': <String, Object>{'issuer': 'RUNWAY AI, INC.'},
        },
      },
      'validation_status': <Object>[
        <String, Object>{'code': 'claimSignature.mismatch'},
      ],
    });

    final metadata = AiMetadataService.parseC2paJson(source);

    expect(metadata.c2paStatus, C2paStatus.invalid);
    expect(metadata.vendor, 'RUNWAY AI, INC.');
  });

  test('parses HeyGen custom container metadata', () {
    final metadata = AiMetadataService.parseContainerTags(<String, Object>{
      'heygen-wm': jsonEncode(<String, Object>{
        'provider': 'HeyGen',
        'model': 'pacific_video',
      }),
    });

    expect(metadata.vendor, 'HeyGen');
    expect(metadata.model, 'pacific_video');
  });

  test('parses Vidu model from AIGC ProduceID', () {
    final metadata = AiMetadataService.parseContainerTags(<String, Object>{
      'AIGC': jsonEncode(<String, Object>{
        'ProduceID': 'character2video-3.2-10-720p-983237261082537984',
      }),
    });

    expect(metadata.vendor, 'Vidu');
    expect(metadata.model, 'character2video-3.2');
  });

  test('keeps container metadata when C2PA is absent', () {
    const c2pa = AiMediaMetadata(c2paStatus: C2paStatus.absent);
    const container = AiMediaMetadata(
      vendor: 'Vidu',
      model: 'character2video-3.2',
    );

    final metadata = AiMetadataService.merge(c2pa, container);

    expect(metadata.c2paStatus, C2paStatus.absent);
    expect(metadata.vendor, 'Vidu');
    expect(metadata.model, 'character2video-3.2');
    expect(metadata.hasC2pa, isFalse);
    expect(metadata.hasDisplayableInfo, isTrue);
  });

  test('model-only metadata remains displayable', () {
    const metadata = AiMediaMetadata(model: 'seedream-4-5');

    expect(metadata.hasDisplayableInfo, isTrue);
  });

  test('parses camera make, model, and lens from EXIF tags', () {
    final metadata = AiMetadataService.parseExifTags(<String, String>{
      'Image Make': 'SONY',
      'Image Model': 'ILCE-7M4',
      'EXIF LensModel': 'FE 24-70mm F2.8 GM II',
    });

    expect(metadata.cameraMake, 'SONY');
    expect(metadata.cameraModel, 'ILCE-7M4');
    expect(metadata.lensModel, 'FE 24-70mm F2.8 GM II');
    expect(metadata.hasDisplayableInfo, isTrue);
  });

  test('parses camera metadata from QuickTime container tags', () {
    final metadata = AiMetadataService.parseContainerTags(<String, String>{
      'com.apple.quicktime.make': 'Apple',
      'com.apple.quicktime.model': 'iPhone 17 Pro',
    });

    expect(metadata.cameraMake, 'Apple');
    expect(metadata.cameraModel, 'iPhone 17 Pro');
  });

  test('merges AI provenance with camera metadata', () {
    const provenance = AiMediaMetadata(
      c2paStatus: C2paStatus.conformant,
      vendor: 'OpenAI',
      model: 'Sora',
    );
    const camera = AiMediaMetadata(
      cameraMake: 'Canon',
      cameraModel: 'EOS R5',
      lensModel: 'RF24-70mm F2.8 L IS USM',
    );

    final metadata = AiMetadataService.merge(provenance, camera);

    expect(metadata.vendor, 'OpenAI');
    expect(metadata.model, 'Sora');
    expect(metadata.cameraMake, 'Canon');
    expect(metadata.cameraModel, 'EOS R5');
    expect(metadata.lensModel, 'RF24-70mm F2.8 L IS USM');
  });
}
