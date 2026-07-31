import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  testWidgets('Finder-opened media is imported and auto-laid out', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const mediaOpenChannel = MethodChannel('video_collage/media_open');
    final mediaPaths = <String>[
      p.join(
        Directory.current.path,
        'macos',
        'Runner',
        'Assets.xcassets',
        'AppIcon.appiconset',
        'app_icon_32.png',
      ),
      p.join(
        Directory.current.path,
        'macos',
        'Runner',
        'Assets.xcassets',
        'AppIcon.appiconset',
        'app_icon_64.png',
      ),
    ];
    var didConsumeMedia = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      mediaOpenChannel,
      (call) async {
        if (call.method != 'consumePendingMediaFiles' || didConsumeMedia) {
          return <String>[];
        }
        didConsumeMedia = true;
        return mediaPaths;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        mediaOpenChannel,
        null,
      );
    });

    await tester.pumpWidget(const VideoCollageApp());
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Auto layout picked 1×2 • 16:9.').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('2 loaded • capacity 2'), findsOneWidget);
    expect(find.text('Auto layout picked 1×2 • 16:9.'), findsOneWidget);

    expect(find.byTooltip('Vertical Auto'), findsOneWidget);
    expect(find.byTooltip('Horizontal Auto'), findsOneWidget);

    await tester.tap(find.byTooltip('Vertical Auto'));
    await tester.pumpAndSettle();

    expect(find.text('2 loaded • capacity 2'), findsOneWidget);
    expect(find.text('Vertical Auto picked 2×1 • 9:16.'), findsOneWidget);

    await tester.tap(find.byTooltip('Horizontal Auto'));
    await tester.pumpAndSettle();

    expect(find.text('2 loaded • capacity 2'), findsOneWidget);
    expect(find.text('Horizontal Auto picked 1×2 • 16:9.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('reset options can keep or remove loaded media', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const mediaOpenChannel = MethodChannel('video_collage/media_open');
    final mediaPath = p.join(
      Directory.current.path,
      'macos',
      'Runner',
      'Assets.xcassets',
      'AppIcon.appiconset',
      'app_icon_32.png',
    );
    var didConsumeMedia = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      mediaOpenChannel,
      (call) async {
        if (call.method != 'consumePendingMediaFiles' || didConsumeMedia) {
          return <String>[];
        }
        didConsumeMedia = true;
        return <String>[mediaPath];
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        mediaOpenChannel,
        null,
      );
    });

    await tester.pumpWidget(const VideoCollageApp());
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('1 loaded').evaluate().isNotEmpty) {
        break;
      }
    }

    await tester.tap(find.byTooltip('Reset all'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('What would you like to reset?'), findsOneWidget);
    expect(
      find.text('Export history and exported files will be kept.'),
      findsOneWidget,
    );
    expect(find.text('Reset Settings Only'), findsOneWidget);
    expect(find.text('Reset Settings + Media'), findsOneWidget);

    await tester.tap(find.text('Reset Settings Only'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('1 loaded • capacity 3'), findsOneWidget);
    expect(find.text('Settings reset. Loaded media kept.'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset all'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Reset Settings + Media'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('0 loaded • capacity 3'), findsOneWidget);
    expect(find.text('Settings reset and all media removed.'), findsOneWidget);
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

  testWidgets('rows and columns can be increased to 8', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    for (final label in <String>['Rows', 'Columns']) {
      final stepper = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final addButton = find.descendant(
        of: stepper,
        matching: find.widgetWithIcon(IconButton, Icons.add_circle_outline),
      );

      for (var value = label == 'Rows' ? 1 : 3; value < 8; value++) {
        await tester.tap(addButton);
        await tester.pump();
      }

      expect(find.descendant(of: stepper, matching: find.text('8')), findsOne);
      expect(tester.widget<IconButton>(addButton).onPressed, isNull);
    }
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
