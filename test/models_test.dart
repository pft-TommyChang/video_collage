import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/models.dart';

void main() {
  test('bottom center label padding only affects the bottom edge', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 24,
      alignment: ClipLabelAlignment.bottomCenter,
    );

    expect(style.margin, const EdgeInsets.fromLTRB(5, 5, 5, 24));
  });

  test('top left label padding affects top and left edges', () {
    final style = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 24,
      alignment: ClipLabelAlignment.topLeft,
    );

    expect(style.margin, const EdgeInsets.fromLTRB(24, 24, 5, 5));
  });
}
