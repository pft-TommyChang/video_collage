import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/services/editor_settings_store.dart';

void main() {
  test('short media types use canonical labels instead of extensions', () {
    expect(shortMediaTypeLabel('/media/photo.jpg', MediaKind.photo), 'JPG');
    expect(shortMediaTypeLabel('/media/photo.JPEG', MediaKind.photo), 'JPG');
    expect(shortMediaTypeLabel('/media/video.mp4', MediaKind.video), 'MP4');
    expect(shortMediaTypeLabel('/media/video.M4V', MediaKind.video), 'MP4');
    expect(shortMediaTypeLabel('/media/photo.raw', MediaKind.photo), 'IMAGE');
    expect(shortMediaTypeLabel('/media/video.xyz', MediaKind.video), 'VIDEO');
  });

  test('persisted settings use the current clip label defaults', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{});

    expect(settings.clipLabelPadding, 6);
    expect(
      settings.clipLabelVisualStyle,
      ClipLabelVisualStyle.transparentOutline,
    );
    expect(settings.isSidePanelCollapsed, isFalse);
    expect(settings.preferAiMetadataForClipLabels, isTrue);
  });

  test('persisted settings use the current layout defaults', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{});

    expect(settings.rows, 2);
    expect(settings.columns, 2);
    expect(settings.borderThickness, 10);
    expect(settings.tileCornerRadius, 10);
    expect(settings.aspectLabel, '1:1');
    expect(settings.outputWidth, 1080);
    expect(settings.outputHeight, 1080);
  });

  test('persisted settings restore the side panel state', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{
      'isSidePanelCollapsed': true,
    });

    expect(settings.isSidePanelCollapsed, isTrue);
    expect(settings.toJson()['isSidePanelCollapsed'], isTrue);
  });

  test('persisted settings restore the AI metadata label preference', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{
      'preferAiMetadataForClipLabels': false,
    });

    expect(settings.preferAiMetadataForClipLabels, isFalse);
    expect(settings.toJson()['preferAiMetadataForClipLabels'], isFalse);
  });

  test('persisted settings restore merge options', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{
      'mergeFitMode': 'centerInside',
      'mergeFrameRateMode': 'highest',
    });

    expect(settings.mergeFitMode, 'centerInside');
    expect(settings.mergeFrameRateMode, 'highest');
    expect(settings.toJson()['mergeFitMode'], 'centerInside');
    expect(settings.toJson()['mergeFrameRateMode'], 'highest');
  });

  test('persisted settings restore custom colors', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{
      'borderColorValue': 0xFF123456,
      'backgroundColorValue': 0x00000000,
    });

    expect(settings.borderColorValue, 0xFF123456);
    expect(settings.backgroundColorValue, 0x00000000);
    expect(settings.toJson(), isNot(contains('borderImagePath')));
  });

  test('legacy canvas image settings reset the canvas to white', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{
      'borderColorLabel': 'Ink',
      'borderColorValue': 0xFF101217,
      'borderImagePath': '/tmp/border.png',
    });

    expect(settings.borderColorLabel, 'White');
    expect(settings.borderColorValue, 0xFFFFFFFF);
    expect(settings.toJson(), isNot(contains('borderImagePath')));
  });

  test('transparent color choice is identified by its alpha channel', () {
    const choice = ColorChoice(
      label: 'Transparent',
      color: Color(0x00000000),
      ffmpegHex: 'black@0.0',
    );

    expect(choice.isTransparent, isTrue);
  });

  test('crop center fit mode uses cover preview fit', () {
    expect(ClipFitMode.cropCenter.previewFit, BoxFit.cover);
    expect(ClipFitMode.centerInside.previewFit, BoxFit.contain);
  });

  test('clip viewport defaults to centered framing', () {
    const viewport = ClipViewport();

    expect(viewport.zoom, 1);
    expect(viewport.focusX, 0.5);
    expect(viewport.focusY, 0.5);
    expect(viewport.previewAlignment, Alignment.center);
    expect(viewport.isDefault, isTrue);
  });

  test('clip viewport clamps zoom and focus to supported bounds', () {
    const viewport = ClipViewport();
    final adjusted = viewport.copyWith(zoom: 8, focusX: -1, focusY: 2);

    expect(adjusted.zoom, 4);
    expect(adjusted.focusX, 0);
    expect(adjusted.focusY, 1);
    expect(adjusted.previewAlignment, const Alignment(-1, 1));
    expect(adjusted.isDefault, isFalse);
  });

  test('visible area fraction reflects crop and inside fit modes', () {
    expect(
      visibleAreaFractionForFit(
        fitMode: ClipFitMode.cropCenter,
        sourceAspect: 9 / 16,
        targetAspect: 16 / 9,
      ),
      closeTo(81 / 256, 0.000001),
    );
    expect(
      visibleAreaFractionForFit(
        fitMode: ClipFitMode.centerInside,
        sourceAspect: 9 / 16,
        targetAspect: 16 / 9,
      ),
      1,
    );
  });

  test('bottom center label padding only affects the bottom edge', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 24,
      alignment: ClipLabelAlignment.bottomCenter,
      visualStyle: ClipLabelVisualStyle.dark,
    );

    expect(style.margin, const EdgeInsets.fromLTRB(5, 5, 5, 24));
  });

  test('top left label padding affects top and left edges', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 24,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: ClipLabelVisualStyle.dark,
    );

    expect(style.margin, const EdgeInsets.fromLTRB(24, 24, 5, 5));
  });

  test('label chip padding is smaller than before', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 4,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: ClipLabelVisualStyle.dark,
    );

    expect(style.horizontalPadding, 7);
    expect(style.verticalPadding, 2);
  });

  test('transparent style uses shadow without background', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 4,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: ClipLabelVisualStyle.transparentShadow,
    );

    expect(style.backgroundColor, isNull);
    expect(style.textShadowColor, const Color(0xCC000000));
  });

  test('transparent outline style uses text outline without background', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 4,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: ClipLabelVisualStyle.transparentOutline,
    );

    expect(style.backgroundColor, isNull);
    expect(style.textOutlineColor, const Color(0xFF000000));
    expect(style.textOutlineWidth, greaterThan(0));
  });

  test('square tag style uses smaller corner radius', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 4,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: ClipLabelVisualStyle.squareTag,
    );

    expect(style.backgroundColor, const Color(0xCC111111));
    expect(style.cornerRadius, 6);
  });

  test('trimmed video exposes source range and selected duration', () {
    const clip = VideoClipInfo(
      path: '/tmp/example.mp4',
      name: 'Example',
      duration: Duration(seconds: 4),
      width: 1920,
      height: 1080,
      hasAudio: true,
      mediaKind: MediaKind.video,
      sourceDuration: Duration(seconds: 10),
      trimStart: Duration(seconds: 2),
    );

    expect(clip.fullDuration, const Duration(seconds: 10));
    expect(clip.trimEnd, const Duration(seconds: 6));
    expect(clip.isTrimmed, isTrue);
  });

  test('clip instances can share a source path but keep separate identity', () {
    const first = VideoClipInfo(
      instanceId: 'clip-1',
      path: '/tmp/example.mp4',
      name: 'First use',
      duration: Duration(seconds: 4),
      width: 1920,
      height: 1080,
      hasAudio: true,
      mediaKind: MediaKind.video,
    );
    final second = first.copyWith(
      instanceId: 'clip-2',
      name: 'Second use',
      trimStart: const Duration(seconds: 1),
      duration: const Duration(seconds: 2),
      sourceDuration: const Duration(seconds: 4),
    );

    expect(first.path, second.path);
    expect(first.id, isNot(second.id));
    expect(first.name, 'First use');
    expect(second.name, 'Second use');
    expect(first.trimStart, Duration.zero);
    expect(second.trimStart, const Duration(seconds: 1));
  });

  test(
    'metadata clip label presets capitalize metadata and restore file name',
    () {
      const clip = VideoClipInfo(
        path: '/tmp/my_generated-video.mp4',
        name: 'Custom label',
        duration: Duration(seconds: 4),
        width: 1920,
        height: 1080,
        hasAudio: false,
        mediaKind: MediaKind.video,
        aiMetadata: AiMediaMetadata(vendor: 'openai', model: 'flux'),
      );

      expect(ClipLabelSourcePreset.vendorName.valueFor(clip), 'Openai');
      expect(ClipLabelSourcePreset.modelName.valueFor(clip), 'Flux');
      expect(
        ClipLabelSourcePreset.fileName.valueFor(clip),
        'my_generated-video',
      );
    },
  );

  test('default clip labels prefer model, then vendor, then file name', () {
    const modelClip = VideoClipInfo(
      path: '/tmp/example.mp4',
      name: 'example',
      duration: Duration(seconds: 4),
      width: 1920,
      height: 1080,
      hasAudio: false,
      mediaKind: MediaKind.video,
      aiMetadata: AiMediaMetadata(vendor: 'openai', model: 'sora'),
    );
    final vendorClip = modelClip.copyWith(
      aiMetadata: const AiMediaMetadata(vendor: 'runway'),
    );
    final fileClip = modelClip.copyWith(aiMetadata: const AiMediaMetadata());

    expect(defaultClipLabelFor(modelClip, preferAiMetadata: true), 'Sora');
    expect(defaultClipLabelFor(vendorClip, preferAiMetadata: true), 'Runway');
    expect(defaultClipLabelFor(fileClip, preferAiMetadata: true), 'example');
    expect(defaultClipLabelFor(modelClip, preferAiMetadata: false), 'example');
  });

  test(
    'async AI metadata updates default labels but preserves custom labels',
    () {
      const defaultClip = VideoClipInfo(
        path: '/tmp/example.png',
        name: 'example',
        duration: Duration.zero,
        width: 1024,
        height: 1024,
        hasAudio: false,
        mediaKind: MediaKind.photo,
        useAiMetadataLabel: true,
      );
      final customClip = defaultClip.copyWith(
        name: 'My label',
        hasCustomLabel: true,
      );
      const metadata = AiMediaMetadata(
        vendor: 'openai',
        model: 'gpt-image 2.0',
      );

      expect(
        applyAiMetadataToClipLabel(defaultClip, metadata).name,
        'Gpt-image 2.0',
      );
      expect(applyAiMetadataToClipLabel(customClip, metadata).name, 'My label');
      expect(
        applyAiMetadataToClipLabel(
          defaultClip.copyWith(useAiMetadataLabel: false),
          metadata,
        ).name,
        'example',
      );
      expect(
        applyAiMetadataLabelPreference(defaultClip, false).name,
        'example',
      );
      expect(
        applyAiMetadataLabelPreference(customClip, false).name,
        'My label',
      );
      expect(
        applyAiMetadataLabelPreference(customClip, false).useAiMetadataLabel,
        isFalse,
      );
    },
  );

  test(
    'metadata clip label presets are unavailable when metadata is missing',
    () {
      const clip = VideoClipInfo(
        path: '/tmp/example.mp4',
        name: 'Example',
        duration: Duration(seconds: 4),
        width: 1920,
        height: 1080,
        hasAudio: false,
        mediaKind: MediaKind.video,
      );

      expect(ClipLabelSourcePreset.vendorName.valueFor(clip), isNull);
      expect(ClipLabelSourcePreset.modelName.valueFor(clip), isNull);
      expect(ClipLabelSourcePreset.fileName.valueFor(clip), 'example');
    },
  );

  test(
    'file name preset button truncates display but keeps the full value',
    () {
      const clip = VideoClipInfo(
        path: '/tmp/12345678901234567890extra.mp4',
        name: 'Example',
        duration: Duration(seconds: 4),
        width: 1920,
        height: 1080,
        hasAudio: false,
        mediaKind: MediaKind.video,
      );

      expect(
        ClipLabelSourcePreset.fileName.buttonLabelFor(clip),
        '12345678901234567890...',
      );
      expect(
        ClipLabelSourcePreset.fileName.valueFor(clip),
        '12345678901234567890extra',
      );
    },
  );

  test('trimmed duration participates in export duration calculation', () {
    const clip = VideoClipInfo(
      path: '/tmp/example.mp4',
      name: 'Example',
      duration: Duration(seconds: 4),
      width: 1920,
      height: 1080,
      hasAudio: true,
      mediaKind: MediaKind.video,
      sourceDuration: Duration(seconds: 10),
      trimStart: Duration(seconds: 2),
    );

    expect(
      exportDurationForClips(
        const <CollageSlotClip>[CollageSlotClip(slotIndex: 0, clip: clip)],
        ExportDurationMode.longest,
        PlayMode.parallel,
      ),
      const Duration(seconds: 4),
    );
  });

  test('formats integer and fractional video frame rates', () {
    expect(formatFrameRate(30), '30 FPS');
    expect(formatFrameRate(29.97), '29.97 FPS');
    expect(formatFrameRate(0), 'FPS unavailable');
  });
}
