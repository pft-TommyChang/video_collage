import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/services/editor_settings_store.dart';

void main() {
  test('persisted settings default clip label padding is 10', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{});

    expect(settings.clipLabelPadding, 10);
    expect(settings.isSidePanelCollapsed, isFalse);
  });

  test('persisted settings restore the side panel state', () {
    final settings = PersistedEditorSettings.fromJson(<String, dynamic>{
      'isSidePanelCollapsed': true,
    });

    expect(settings.isSidePanelCollapsed, isTrue);
    expect(settings.toJson()['isSidePanelCollapsed'], isTrue);
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
}
