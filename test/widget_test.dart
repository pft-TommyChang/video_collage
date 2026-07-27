import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/video_collage_app.dart';

void main() {
  testWidgets('renders app shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    expect(find.text('Perfect Collage'), findsWidgets);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('aspect ratio dropdown includes 9:21 and 21:9', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is DropdownButtonFormField<AspectRatioPreset>;
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('9:21'), findsWidgets);
    expect(find.text('21:9'), findsWidgets);
  });

  testWidgets('fit mode dropdown includes crop center and center inside', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is DropdownButtonFormField<ClipFitMode>;
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crop Center'), findsWidgets);
    expect(find.text('Center Inside'), findsWidgets);
  });
}
