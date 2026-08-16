import 'dart:convert';

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
    expect(metadata.vendor, 'BytePlus');
    expect(metadata.model, 'dreamina-seedance-2-5');
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
    expect(metadata.vendor, 'OpenAI');
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
    expect(metadata.vendor, 'Runway');
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
}
