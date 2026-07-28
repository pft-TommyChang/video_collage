import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/video_collage_app.dart';

void main() {
  Future<void> scrollSettingsIntoView(
    WidgetTester tester,
    Finder finder,
  ) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

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

  testWidgets('last export is disabled at the start of each app session', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    final lastExportButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('No last export yet'),
        matching: find.byType(IconButton),
      ),
    );
    expect(lastExportButton.onPressed, isNull);
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

    await scrollSettingsIntoView(
      tester,
      find.byWidgetPredicate((widget) {
        return widget is DropdownButtonFormField<ClipFitMode>;
      }),
    );
    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is DropdownButtonFormField<ClipFitMode>;
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crop'), findsWidgets);
    expect(find.text('Inside'), findsWidgets);
  });
}
