import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/models.dart';

void main() {
  test('crop center fit mode uses cover preview fit', () {
    expect(ClipFitMode.cropCenter.previewFit, BoxFit.cover);
    expect(ClipFitMode.centerInside.previewFit, BoxFit.contain);
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
}
