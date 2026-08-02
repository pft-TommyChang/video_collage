import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/services/video_export_service.dart';
import 'package:video_collage_mac/src/video_collage_app.dart';
import 'package:video_collage_mac/src/video_trimmer_dialog.dart';

void main() {
  const mediaOpenChannel = MethodChannel('video_collage/media_open');

  void useTestWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  String appIconPath(int size) => p.join(
    Directory.current.path,
    'macos',
    'Runner',
    'Assets.xcassets',
    'AppIcon.appiconset',
    'app_icon_$size.png',
  );

  void mockPendingMediaFiles(WidgetTester tester, List<String> mediaPaths) {
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
  }

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    fail('Timed out waiting for $finder.');
  }

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
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    expect(find.text('Perfect Collage'), findsWidgets);
    expect(find.byTooltip('Auto Layout'), findsOneWidget);
  });

  testWidgets('last export is disabled at the start of each app session', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));

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

  testWidgets('compact preview header keeps duration without overflowing', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(800, 640));

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    expect(find.text('0:00 / 0:00'), findsOneWidget);
  });

  testWidgets('trim dialog fits the minimum window height', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(800, 640));

    const clip = VideoClipInfo(
      path: '/missing-test-video.mp4',
      name: 'Test clip',
      duration: Duration(seconds: 8),
      width: 1280,
      height: 720,
      hasAudio: false,
      mediaKind: MediaKind.video,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => VideoTrimmerDialog(
                clip: clip,
                exportService: VideoExportService(),
              ),
            ),
            child: const Text('Open trimmer'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open trimmer'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Trim video'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Finder-opened media is imported and auto-laid out', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(32), appIconPath(64)]);

    await tester.pumpWidget(const VideoCollageApp());
    await pumpUntilFound(tester, find.text('Auto layout picked 1×2 • 16:9.'));

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

  testWidgets('removing a preview clip leaves its slot empty', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[
      appIconPath(32),
      appIconPath(64),
      appIconPath(128),
    ]);

    await tester.pumpWidget(const VideoCollageApp());
    await pumpUntilFound(tester, find.text('3 loaded • capacity 3'));

    final middleSlot = find.byKey(const ValueKey<String>('preview-slot-1'));
    final rightSlot = find.byKey(const ValueKey<String>('preview-slot-2'));
    expect(
      find.descendant(of: middleSlot, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rightSlot, matching: find.byType(Image)),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(middleSlot));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.descendant(of: middleSlot, matching: find.byTooltip('Remove')),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.descendant(of: middleSlot, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: middleSlot, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rightSlot, matching: find.byType(Image)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('reset options can keep or remove loaded media', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(32)]);

    await tester.pumpWidget(const VideoCollageApp());
    await pumpUntilFound(tester, find.textContaining('1 loaded'));

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
    useTestWindow(tester, const Size(1600, 1000));

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
    useTestWindow(tester, const Size(1600, 1000));

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
    useTestWindow(tester, const Size(1600, 1000));

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
