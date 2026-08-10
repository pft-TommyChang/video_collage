import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:video_collage_mac/src/models.dart';
import 'package:video_collage_mac/src/services/github_update_service.dart';
import 'package:video_collage_mac/src/services/system_dialog_service.dart';
import 'package:video_collage_mac/src/services/video_export_service.dart';
import 'package:video_collage_mac/src/video_merge_dialog.dart';
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

  Widget buildTestApp() =>
      const VideoCollageApp(checkForUpdatesOnLaunch: false);

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

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Perfect Collage'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('open-update-download-page')),
      findsNothing,
    );
    expect(find.byTooltip('Auto Layout'), findsOneWidget);
    expect(find.byTooltip('Merge videos'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('Merge videos')).dx,
      lessThan(tester.getCenter(find.byTooltip('Reset media')).dx),
    );
  });

  testWidgets('shows the update button only when a newer release is found', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    PackageInfo.setMockInitialValues(
      appName: 'Perfect Collage',
      packageName: 'video_collage_mac',
      version: '1.5.0',
      buildNumber: '150',
      buildSignature: '',
    );

    await tester.pumpWidget(
      VideoCollageApp(
        updateService: _FakeUpdateService(
          GitHubRelease(
            tagName: 'v1.6.0',
            pageUrl: Uri.parse(
              'https://github.com/pft-TommyChang/video_collage/releases/tag/v1.6.0',
            ),
          ),
        ),
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('open-update-download-page')),
    );

    expect(find.byTooltip('Perfect Collage 1.6.0 available'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('Perfect Collage 1.6.0 available')).dx,
      greaterThan(tester.getCenter(find.text('0:00 / 0:00')).dx),
    );
  });

  testWidgets('opens the video merge tool', (WidgetTester tester) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Merge videos'));
    await tester.pumpAndSettle();

    expect(find.text('Merge Videos'), findsOneWidget);
    expect(find.text('Add video'), findsNothing);
    expect(find.byTooltip('Add video'), findsOneWidget);
    expect(find.text('No videos selected'), findsOneWidget);
    expect(find.text('Center inside'), findsOneWidget);
    expect(find.text('Highest FPS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('merge-preview-play-button')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('merge-preview-play-button')),
      ),
      const Size.square(36),
    );
    expect(
      find.byKey(const ValueKey<String>('merge-seek-bar')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('merge-playback-time')),
        matching: find.text('0:00 / 0:00'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('merge-save-button'))),
      const Size(160, 40),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('merge-list-container')),
        matching: find.byKey(const ValueKey<String>('merge-add-video-tile')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('merge-add-video-button')),
      ),
      const Size.square(36),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('merge-add-video-tile')),
        matching: find.byType(OutlinedButton),
      ),
      findsNothing,
    );
    expect(
      tester.getCenter(find.text('Merge & Save')).dx,
      lessThan(tester.getCenter(find.text('Cancel')).dx),
    );
  });

  testWidgets('merge tool starts with supplied media and thumbnails', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1200, 800));
    const videos = <VideoClipInfo>[
      VideoClipInfo(
        path: '/missing-first.mp4',
        name: 'First',
        duration: Duration(seconds: 3),
        width: 1920,
        height: 1080,
        hasAudio: true,
        mediaKind: MediaKind.video,
      ),
      VideoClipInfo(
        path: '/missing-second.mp4',
        name: 'Second',
        duration: Duration(seconds: 4),
        width: 1280,
        height: 720,
        hasAudio: false,
        mediaKind: MediaKind.video,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: VideoMergeDialog(
          exportService: _FakeMergeExportService(),
          dialogService: const SystemDialogService(),
          initialVideos: videos,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byTooltip('missing-first.mp4\n1920×1080 • 29.97 FPS • 0:03'),
      findsNothing,
    );
    expect(
      find.text('Media: 1920×1080  •  29.97 FPS  •  0:03'),
      findsOneWidget,
    );
    expect(find.textContaining('Export: 1920×1080'), findsOneWidget);
    expect(find.textContaining('29.97 FPS'), findsWidgets);
    final mergeSubtitle = find.textContaining('Export: 1920×1080');
    expect(
      tester.getTopLeft(mergeSubtitle).dy -
          tester.getBottomLeft(find.text('Merge Videos')).dy,
      lessThan(24),
    );
    expect(find.textContaining('1920×1080'), findsWidgets);
    expect(find.textContaining('0:07 total'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey<String>('merge-center-inside-checkbox')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey<String>('merge-highest-fps-checkbox')),
          )
          .value,
      isFalse,
    );
    final mergeListContainer = tester.widget<Container>(
      find.byKey(const ValueKey<String>('merge-list-container')),
    );
    final mergeListDecoration = mergeListContainer.decoration! as BoxDecoration;
    expect(mergeListDecoration.color, const Color(0xFFF3EFE7));
    final mergeListBorder = mergeListDecoration.border! as Border;
    expect(mergeListBorder.top.width, 1);
    expect(mergeListBorder.top.color, const Color(0xFFD8D0C4));
    expect(find.text('0:00 / 0:07'), findsOneWidget);
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey<String>('merge-playback-controls')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('merge-list-container')),
            )
            .dy,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('merge-list-container')),
        matching: find.byKey(
          const ValueKey<String>('merge-preview-play-button'),
        ),
      ),
      findsNothing,
    );
    final firstThumbnailSize = tester.getSize(
      find.byKey(const ValueKey<String>('merge-thumbnail-merge-video-1')),
    );
    expect(firstThumbnailSize, const Size.square(90));
    expect(find.text('0:03'), findsOneWidget);
    expect(find.text('0:04'), findsOneWidget);
    final selectedThumbnail = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('merge-thumbnail-merge-video-1')),
    );
    final selectedDecoration =
        selectedThumbnail.foregroundDecoration! as BoxDecoration;
    final selectedBorder = selectedDecoration.border! as Border;
    expect(selectedBorder.top.width, 3);
    expect(selectedBorder.top.color, const Color(0xFFFF7A59));
    expect(selectedBorder.top, selectedBorder.right);
    expect(selectedBorder.top, selectedBorder.bottom);
    expect(selectedBorder.top, selectedBorder.left);
    final outputPreviewSize = tester.getSize(
      find.byKey(const ValueKey<String>('merge-output-frame')),
    );
    expect(
      outputPreviewSize.width / outputPreviewSize.height,
      closeTo(1920 / 1080, 0.01),
    );
    expect(outputPreviewSize.width, greaterThan(firstThumbnailSize.width));
    expect(
      tester
          .getCenter(find.byKey(const ValueKey<String>('merge-add-video-tile')))
          .dx,
      greaterThan(
        tester
            .getCenter(
              find.byKey(
                const ValueKey<String>('merge-thumbnail-merge-video-2'),
              ),
            )
            .dx,
      ),
    );

    final thumbnailListener = tester.widget<Listener>(
      find.byKey(const ValueKey<String>('merge-thumbnail-tap-merge-video-2')),
    );
    thumbnailListener.onPointerDown!(const PointerDownEvent());
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('merge-preview-merge-video-2')),
      findsOneWidget,
    );
    expect(find.text('Media: 1280×720  •  60 FPS  •  0:04'), findsOneWidget);
    expect(find.textContaining('1920×1080'), findsOneWidget);
    expect(find.textContaining('Preview missing-second.mp4'), findsNothing);
    final secondVideoPreviewSize = tester.getSize(
      find.byKey(const ValueKey<String>('merge-output-frame')),
    );
    expect(
      secondVideoPreviewSize.width / secondVideoPreviewSize.height,
      closeTo(1920 / 1080, 0.01),
    );

    final firstThumbnail = find.byKey(
      const ValueKey<String>('merge-thumbnail-merge-video-1'),
    );
    final drag = await tester.startGesture(tester.getCenter(firstThumbnail));
    await tester.pump();
    await drag.moveBy(const Offset(350, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pumpAndSettle();

    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey<String>('merge-thumbnail-merge-video-2')),
          )
          .dx,
      lessThan(tester.getCenter(firstThumbnail).dx),
    );
  });

  testWidgets('merge tool supports duplicate source video instances', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1200, 800));
    final exportService = _FakeMergeExportService();
    const repeatedVideo = VideoClipInfo(
      path: '/missing-repeated.mp4',
      name: 'Repeated',
      duration: Duration(seconds: 3),
      width: 1920,
      height: 1080,
      hasAudio: true,
      mediaKind: MediaKind.video,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoMergeDialog(
          exportService: exportService,
          dialogService: _FakeMergeDialogService(),
          initialVideos: const <VideoClipInfo>[repeatedVideo, repeatedVideo],
        ),
      ),
    );
    await tester.pump();

    final firstThumbnail = find.byKey(
      const ValueKey<String>('merge-thumbnail-merge-video-1'),
    );
    final secondThumbnail = find.byKey(
      const ValueKey<String>('merge-thumbnail-merge-video-2'),
    );
    expect(firstThumbnail, findsOneWidget);
    expect(secondThumbnail, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Merge & Save'));
    await tester.pumpAndSettle();

    expect(exportService.mergeCalls, 1);
    expect(exportService.videos, hasLength(2));
    expect(exportService.videos![0].path, exportService.videos![1].path);
    expect(exportService.videos![0].id, isNot(exportService.videos![1].id));

    await tester.tap(
      find.descendant(
        of: firstThumbnail,
        matching: find.byTooltip('Remove missing-repeated.mp4'),
      ),
    );
    await tester.pump();

    expect(firstThumbnail, findsNothing);
    expect(secondThumbnail, findsOneWidget);
    expect(find.textContaining('0:03 total'), findsOneWidget);
  });

  testWidgets('merge media thumbnail opens the shared trim dialog', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1200, 800));
    const video = VideoClipInfo(
      path: '/missing-trimmable.mp4',
      name: 'Trimmable',
      duration: Duration(seconds: 8),
      sourceDuration: Duration(seconds: 10),
      trimStart: Duration(seconds: 1),
      width: 1920,
      height: 1080,
      hasAudio: true,
      mediaKind: MediaKind.video,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoMergeDialog(
          exportService: _FakeMergeExportService(),
          dialogService: const SystemDialogService(),
          initialVideos: const <VideoClipInfo>[video],
        ),
      ),
    );
    await tester.pump();

    final thumbnail = find.byKey(
      const ValueKey<String>('merge-thumbnail-merge-video-1'),
    );
    final trimButton = find.byKey(
      const ValueKey<String>('merge-trim-merge-video-1'),
    );
    expect(trimButton, findsOneWidget);
    expect(find.byTooltip('Trim missing-trimmable.mp4'), findsOneWidget);
    expect(
      tester.getCenter(trimButton).dx,
      lessThan(tester.getCenter(thumbnail).dx),
    );
    expect(
      tester.getCenter(trimButton).dy,
      greaterThan(tester.getCenter(thumbnail).dy),
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: trimButton,
              matching: find.byIcon(Icons.content_cut_rounded),
            ),
          )
          .color,
      const Color(0xFFFFC107),
    );

    await tester.tap(trimButton);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Trim video'), findsOneWidget);
  });

  testWidgets('completed merge keeps the dialog open', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1200, 800));
    const videos = <VideoClipInfo>[
      VideoClipInfo(
        path: '/missing-first.mp4',
        name: 'First',
        duration: Duration(seconds: 3),
        width: 1920,
        height: 1080,
        hasAudio: true,
        mediaKind: MediaKind.video,
      ),
      VideoClipInfo(
        path: '/missing-second.mp4',
        name: 'Second',
        duration: Duration(seconds: 4),
        width: 1280,
        height: 720,
        hasAudio: false,
        mediaKind: MediaKind.video,
      ),
    ];
    final exportService = _FakeMergeExportService();
    final dialogService = _FakeMergeDialogService();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoMergeDialog(
          exportService: exportService,
          dialogService: dialogService,
          initialVideos: videos,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Center inside'));
    await tester.pump();
    await tester.tap(find.text('Highest FPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge & Save'));
    await tester.pumpAndSettle();

    expect(exportService.mergeCalls, 1);
    expect(dialogService.suggestedName, 'missing-first_merged.mp4');
    expect(exportService.fitMode, ClipFitMode.centerInside);
    expect(exportService.frameRateMode, VideoMergeFrameRateMode.highest);
    expect(find.text('Merge Videos'), findsOneWidget);
    expect(find.text('Saved'), findsWidgets);
    expect(find.byTooltip('Open File'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('merge-open-result-button')),
      ),
      const Size.square(40),
    );
    final openResultButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('merge-open-result-button')),
    );
    expect(
      openResultButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('cancelled merge does not add an error message row', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1200, 800));
    const videos = <VideoClipInfo>[
      VideoClipInfo(
        path: '/missing-first.mp4',
        name: 'First',
        duration: Duration(seconds: 3),
        width: 1920,
        height: 1080,
        hasAudio: true,
        mediaKind: MediaKind.video,
      ),
      VideoClipInfo(
        path: '/missing-second.mp4',
        name: 'Second',
        duration: Duration(seconds: 4),
        width: 1280,
        height: 720,
        hasAudio: false,
        mediaKind: MediaKind.video,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: VideoMergeDialog(
          exportService: _FakeMergeExportService(cancelMerge: true),
          dialogService: _FakeMergeDialogService(),
          initialVideos: videos,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Merge & Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Export cancelled'), findsNothing);
    expect(find.textContaining('Merge failed'), findsNothing);
    expect(find.text('Merge & Save'), findsOneWidget);
  });

  testWidgets('collapsed panel moves controls into the preview area', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collapse panel'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('collapsed-export-button')),
      findsNothing,
    );
    expect(
      tester.getCenter(find.byTooltip('Reset all')).dx,
      greaterThan(tester.getCenter(find.byTooltip('Horizontal Auto')).dx),
    );

    await tester.tap(find.byTooltip('Collapse panel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final collapsingWidth = tester
        .getSize(find.byKey(const ValueKey<String>('side-panel')))
        .width;
    expect(collapsingWidth, greaterThan(0));
    expect(collapsingWidth, lessThan(370));

    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('side-panel'))).width,
      0,
    );
    expect(find.byTooltip('Expand panel'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('collapsed-export-button')),
      findsOneWidget,
    );
    final collapsedExportGesture = tester.widget<GestureDetector>(
      find.byKey(const ValueKey<String>('collapsed-export-button')),
    );
    expect(collapsedExportGesture.onSecondaryTapDown, isNull);
    expect(
      tester.getCenter(find.byTooltip('Expand panel')).dx,
      lessThan(tester.getCenter(find.byTooltip('Auto Layout')).dx),
    );
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey<String>('collapsed-export-button')),
          )
          .dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey<String>('status-message')))
            .dx,
      ),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('collapsed-export-button')),
          )
          .height,
      tester
          .getSize(find.byKey(const ValueKey<String>('status-message')))
          .height,
    );

    await tester.tap(find.byTooltip('Expand panel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final expandingWidth = tester
        .getSize(find.byKey(const ValueKey<String>('side-panel')))
        .width;
    expect(expandingWidth, greaterThan(0));
    expect(expandingWidth, lessThan(370));

    await tester.pumpAndSettle();

    expect(find.text('Media'), findsOneWidget);
    expect(find.byTooltip('Collapse panel'), findsOneWidget);
  });

  testWidgets('last export is disabled at the start of each app session', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
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

    await tester.pumpWidget(buildTestApp());
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

    await tester.pumpWidget(buildTestApp());
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

  testWidgets('pan and zoom supports modified wheel and ten percent buttons', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(64)]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.textContaining('Auto layout picked'));

    final viewportControls = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'viewport-controls-',
          ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(viewportControls));
    await tester.pump();
    await tester.tap(find.byTooltip('Crop Area'));
    await tester.pump();

    final editingControls = find.byKey(
      const ValueKey<String>('viewport-editing-controls-full'),
    );
    final zoomSlider = find.descendant(
      of: editingControls,
      matching: find.byType(Slider),
    );
    final zoomOutButton = find.descendant(
      of: editingControls,
      matching: find.byIcon(Icons.remove_circle_outline),
    );
    final zoomInButton = find.descendant(
      of: editingControls,
      matching: find.byIcon(Icons.add_circle_outline),
    );
    expect(find.byTooltip('Zoom out 10%'), findsNothing);
    expect(find.byTooltip('Zoom in 10%'), findsNothing);
    expect(tester.widget<Slider>(zoomSlider).value, 1);

    await tester.tap(zoomInButton);
    await tester.pump();
    expect(tester.widget<Slider>(zoomSlider).value, closeTo(1.1, 0.0001));

    await tester.tap(zoomOutButton);
    await tester.pump();
    expect(tester.widget<Slider>(zoomSlider).value, 1);

    final panZoomSurface = find.byKey(
      const ValueKey<String>('viewport-pan-zoom-surface'),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(panZoomSurface),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pump();
    expect(tester.widget<Slider>(zoomSlider).value, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(panZoomSurface),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(tester.widget<Slider>(zoomSlider).value, closeTo(1.1, 0.0001));

    await tester.tap(find.text('Done'));
    await tester.pump();
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(viewportControls));
    await tester.pump();
    final activeCropIcon = find.byIcon(Icons.center_focus_strong_rounded);
    expect(activeCropIcon, findsOneWidget);
    expect(tester.widget<Icon>(activeCropIcon).color, const Color(0xFFFFC107));
  });

  testWidgets('the same source file can be added as independent instances', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    final repeatedPath = appIconPath(64);
    mockPendingMediaFiles(tester, <String>[repeatedPath, repeatedPath]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.text('2 loaded • capacity 2'));

    final firstSlot = find.byKey(const ValueKey<String>('preview-slot-0'));
    final secondSlot = find.byKey(const ValueKey<String>('preview-slot-1'));
    expect(
      find.descendant(of: firstSlot, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondSlot, matching: find.byType(Image)),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(firstSlot));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.descendant(of: firstSlot, matching: find.byTooltip('Remove')),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1 loaded • capacity 2'), findsOneWidget);
    expect(
      find.descendant(of: secondSlot, matching: find.byType(Image)),
      findsOneWidget,
    );

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

    await tester.pumpWidget(buildTestApp());
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

    await tester.pumpWidget(buildTestApp());
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

    await tester.pumpWidget(buildTestApp());
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

    await tester.pumpWidget(buildTestApp());
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

    await tester.pumpWidget(buildTestApp());
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

  testWidgets('palette selection updates the canvas color', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await scrollSettingsIntoView(tester, find.text('Canvas'));

    await tester.tap(find.byTooltip('Open color palette').first);
    await tester.pumpAndSettle();

    final palette = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(CustomPaint),
    );
    final paletteSize = tester.getSize(palette.first);
    await tester.tapAt(
      tester.getTopLeft(palette.first) +
          Offset(paletteSize.width * 0.72, paletteSize.height * 0.28),
    );
    await tester.pump();
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'^#[0-9A-F]{6}$')), findsOneWidget);
  });
}

class _FakeUpdateService extends GitHubUpdateService {
  _FakeUpdateService(this.release) : super(owner: 'test', repository: 'test');

  final GitHubRelease release;

  @override
  Future<GitHubRelease> fetchLatestRelease() async => release;
}

class _FakeMergeDialogService extends SystemDialogService {
  String? suggestedName;

  @override
  Future<String?> pickSavePath({
    required ExportFormat format,
    required String suggestedName,
    String? initialDirectory,
  }) async {
    this.suggestedName = suggestedName;
    return '/tmp/merged-video-test.mp4';
  }
}

class _FakeMergeExportService extends VideoExportService {
  _FakeMergeExportService({this.cancelMerge = false});

  final bool cancelMerge;
  int mergeCalls = 0;
  ClipFitMode? fitMode;
  VideoMergeFrameRateMode? frameRateMode;
  List<VideoClipInfo>? videos;

  @override
  Future<double> probeVideoFrameRate(String path) async {
    return path.contains('second') ? 60 : 29.97;
  }

  @override
  Future<void> mergeVideos({
    required List<VideoClipInfo> videos,
    required String outputPath,
    ClipFitMode fitMode = ClipFitMode.cropCenter,
    VideoMergeFrameRateMode frameRateMode = VideoMergeFrameRateMode.firstVideo,
    void Function(VideoExportProgress progress)? onProgress,
  }) async {
    mergeCalls += 1;
    this.videos = List<VideoClipInfo>.of(videos);
    if (cancelMerge) {
      throw const VideoExportException('Export cancelled.');
    }
    this.fitMode = fitMode;
    this.frameRateMode = frameRateMode;
    onProgress?.call(
      const VideoExportProgress(
        progress: 0.5,
        processed: Duration(milliseconds: 3500),
        total: Duration(seconds: 7),
      ),
    );
    onProgress?.call(
      const VideoExportProgress(
        progress: 1,
        processed: Duration(seconds: 7),
        total: Duration(seconds: 7),
      ),
    );
  }
}
