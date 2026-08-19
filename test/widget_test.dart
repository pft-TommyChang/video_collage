import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Widget buildTestApp() => const VideoCollageApp(
    checkForUpdatesOnLaunch: false,
    refreshC2paTrustListOnLaunch: false,
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

  Future<void> expandLayoutAdvancedSettings(WidgetTester tester) async {
    final advanced = find.text('More styling options');
    await scrollSettingsIntoView(tester, advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
  }

  Future<void> choosePreviewAutoLayout(
    WidgetTester tester,
    String option,
  ) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('preview-auto-layout-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  Future<void> openResetAllDialog(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('preview-reset-button')),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('renders app shell', (WidgetTester tester) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Perfect Collage'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('open-release-page')),
      findsOneWidget,
    );
    expect(find.byTooltip('Open GitHub Releases'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey<String>('open-release-page')),
          )
          .onTap,
      isNotNull,
    );
    expect(
      find.byKey(const ValueKey<String>('update-available-indicator')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('preview-auto-layout-menu')),
      findsOneWidget,
    );
    expect(find.text('0:00 / 0:00'), findsNothing);
    expect(find.text('Start your collage'), findsOneWidget);
    expect(find.text('Add photos or videos'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('add-media-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey<String>('empty-media-add-target')),
          )
          .onTap,
      isNotNull,
    );
    expect(find.byTooltip('Add media'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-reset-button')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey<String>('media-reset-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const ValueKey<String>('merge-videos-button')),
      findsOneWidget,
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey<String>('merge-videos-button')))
          .dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey<String>('add-media-button')))
            .dx,
      ),
    );
    final mergeLabel = tester.widget<Text>(find.text('Merge videos'));
    expect(mergeLabel.maxLines, 1);
    expect(mergeLabel.softWrap, isFalse);
    expect(find.byTooltip('Media actions'), findsNothing);
    expect(find.text('Export'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('status-message')),
      findsOneWidget,
    );
    expect(find.text('Ready.'), findsOneWidget);
  });

  testWidgets('external drag reveals slot hover behind onboarding', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    final details = DropEventDetails(
      localPosition: Offset(900, 500),
      globalPosition: Offset(900, 500),
    );
    final rootDropTarget = tester.widget<DropTarget>(
      find.byType(DropTarget).first,
    );
    final slotDropTarget = tester.widget<DropTarget>(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropTarget &&
            widget.child.key == const ValueKey<String>('preview-slot-0'),
      ),
    );

    rootDropTarget.onDragEntered?.call(details);
    slotDropTarget.onDragEntered?.call(details);
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      find.byKey(const ValueKey<String>('empty-preview-onboarding')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('preview-drop-hover')),
      findsOneWidget,
    );

    slotDropTarget.onDragExited?.call(details);
    rootDropTarget.onDragExited?.call(details);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('empty-preview-onboarding')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('preview-drop-hover')),
      findsNothing,
    );
  });

  testWidgets('empty preview uses the real grid and centers onboarding', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('preview-slot-3')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('preview-slot-4')), findsNothing);
    final operationArea = find.byKey(
      const ValueKey<String>('preview-operation-area'),
    );
    final onboardingCard = find.byKey(
      const ValueKey<String>('empty-preview-onboarding-card'),
    );
    expect(
      tester.getCenter(onboardingCard).dx,
      closeTo(tester.getCenter(operationArea).dx, 0.1),
    );
    expect(
      tester.getCenter(onboardingCard).dy,
      closeTo(tester.getCenter(operationArea).dy, 0.1),
    );

    final rowsStepper = find
        .ancestor(of: find.text('Rows'), matching: find.byType(Row))
        .first;
    final addRowButton = find.descendant(
      of: rowsStepper,
      matching: find.widgetWithIcon(IconButton, Icons.add_circle_outline),
    );
    await tester.tap(addRowButton);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('preview-slot-5')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('preview-slot-6')), findsNothing);
  });

  testWidgets('advanced styling expansion has no borders or tap background', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    final tile = tester.widget<ExpansionTile>(
      find.byKey(const PageStorageKey<String>('layout-advanced-settings')),
    );
    expect(tile.shape, const Border());
    expect(tile.collapsedShape, const Border());
    expect(tile.backgroundColor, Colors.transparent);
    expect(tile.collapsedBackgroundColor, Colors.transparent);

    final tileTheme = Theme.of(
      tester.element(
        find.byKey(const PageStorageKey<String>('layout-advanced-settings')),
      ),
    );
    expect(tileTheme.hoverColor, Colors.transparent);
    expect(tileTheme.highlightColor, Colors.transparent);
    expect(tileTheme.splashColor, Colors.transparent);
    expect(tileTheme.splashFactory, NoSplash.splashFactory);
  });

  testWidgets('section reset stays visible when its content is collapsed', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('media-reset-button')),
      findsOneWidget,
    );
  });

  testWidgets('enter applies custom width and height', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    Finder resolutionField(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

    await scrollSettingsIntoView(tester, resolutionField('Width'));
    await tester.enterText(resolutionField('Width'), '1201');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(resolutionField('Width')).controller?.text,
      '1202',
    );

    await tester.enterText(resolutionField('Height'), '721');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(resolutionField('Height')).controller?.text,
      '722',
    );
  });

  testWidgets('makes only the version row clickable when an update is found', (
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
        refreshC2paTrustListOnLaunch: false,
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
      find.byKey(const ValueKey<String>('update-available-indicator')),
    );

    expect(find.byTooltip('Perfect Collage 1.6.0 available'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('update-available-indicator')),
      findsOneWidget,
    );
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey<String>('update-available-indicator')),
          )
          .dx,
      greaterThan(tester.getCenter(find.text('Version 1.5.0 (150)')).dx),
    );
  });

  testWidgets('opens the video merge tool', (WidgetTester tester) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('merge-videos-button')));
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
    expect(
      find.ancestor(
        of: find.text('Cancel'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    final mergeCancelButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Cancel'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(
      mergeCancelButton.style?.side?.resolve(<WidgetState>{})?.color,
      Theme.of(tester.element(find.text('Cancel'))).colorScheme.primary,
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
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(
              const ValueKey<String>('merge-thumbnail-cursor-merge-video-1'),
            ),
          )
          .cursor,
      SystemMouseCursors.grab,
    );
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(
              const ValueKey<String>('merge-main-video-cursor-merge-video-1'),
            ),
          )
          .cursor,
      SystemMouseCursors.click,
    );
    expect(find.text('0:03'), findsOneWidget);
    expect(find.text('0:04'), findsOneWidget);
    expect(find.byTooltip('Main video: missing-first.mp4'), findsOneWidget);
    expect(
      find.byTooltip('Set missing-second.mp4 as main video'),
      findsOneWidget,
    );
    final mainCrown = tester.widget<Icon>(
      find.byKey(const ValueKey<String>('merge-main-crown')),
    );
    expect(mainCrown.color, const Color(0xFFFFC107));
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

    await tester.tap(
      find.byKey(const ValueKey<String>('merge-main-video-merge-video-2')),
    );
    await tester.pump();

    expect(find.byTooltip('Main video: missing-second.mp4'), findsOneWidget);
    expect(find.textContaining('Export: 1280×720'), findsOneWidget);
    final mainVideoPreviewSize = tester.getSize(
      find.byKey(const ValueKey<String>('merge-output-frame')),
    );
    expect(
      mainVideoPreviewSize.width / mainVideoPreviewSize.height,
      closeTo(1280 / 720, 0.01),
    );

    final firstThumbnail = find.byKey(
      const ValueKey<String>('merge-thumbnail-merge-video-1'),
    );
    final firstThumbnailCenter =
        tester.getTopLeft(firstThumbnail) + const Offset(65, 45);
    const mergeDragPointer = 99;
    final drag = await tester.createGesture(
      pointer: mergeDragPointer,
      kind: PointerDeviceKind.mouse,
    );
    await drag.addPointer(location: firstThumbnailCenter);
    await drag.moveTo(firstThumbnailCenter + const Offset(1, 0));
    await tester.pump();
    await drag.down(firstThumbnailCenter + const Offset(1, 0));
    await tester.pump();
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(
              const ValueKey<String>('merge-thumbnail-cursor-merge-video-1'),
            ),
          )
          .cursor,
      SystemMouseCursors.grabbing,
    );
    await drag.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(const ValueKey<String>('merge-reorder-proxy-cursor')),
          )
          .cursor,
      SystemMouseCursors.grabbing,
    );
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
    expect(find.byTooltip('Main video: missing-second.mp4'), findsOneWidget);
  });

  test(
    'merge previews prefer probed display dimensions for rotated videos',
    () {
      const portraitMov = VideoClipInfo(
        path: '/portrait.mov',
        name: 'Portrait MOV',
        duration: Duration(seconds: 3),
        width: 1080,
        height: 1920,
        hasAudio: true,
        mediaKind: MediaKind.video,
      );

      expect(
        mergeVideoPreviewDisplaySize(
          video: portraitMov,
          decodedSize: const Size(1920, 1080),
        ),
        const Size(1080, 1920),
      );
    },
  );

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
    await tester.tap(
      find.byKey(const ValueKey<String>('merge-main-video-merge-video-2')),
    );
    await tester.pump();
    await tester.tap(find.text('Merge & Save'));
    await tester.pumpAndSettle();

    expect(exportService.mergeCalls, 1);
    expect(dialogService.suggestedName, 'missing-second_merged.mp4');
    expect(exportService.mainVideo?.path, '/missing-second.mp4');
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
      find.byKey(const ValueKey<String>('preview-reset-button')),
      findsOneWidget,
    );
    expect(find.text('Reset all'), findsNothing);

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
      lessThan(
        tester
            .getCenter(
              find.byKey(const ValueKey<String>('preview-auto-layout-menu')),
            )
            .dx,
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('status-message')),
      findsOneWidget,
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

  testWidgets('compact photo preview hides playback without overflowing', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(800, 640));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('0:00 / 0:00'), findsNothing);
    expect(find.text('Start your collage'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.text('Export video'), findsOneWidget);
    expect(find.text('Export audio'), findsNothing);
    expect(
      tester.getCenter(find.text('Apply trim')).dx,
      lessThan(tester.getCenter(find.text('Cancel')).dx),
    );
    expect(
      find.ancestor(
        of: find.text('Cancel'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    final trimCancelButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Cancel'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(
      trimCancelButton.style?.side?.resolve(<WidgetState>{})?.color,
      Theme.of(tester.element(find.text('Cancel'))).colorScheme.primary,
    );
    await tester.tap(find.byTooltip('Export options'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Export video'), findsWidgets);
    expect(find.text('Export audio'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem && !widget.enabled,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('trim export split button switches export type', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(800, 640));

    const clip = VideoClipInfo(
      path: '/missing-test-video-with-audio.mp4',
      name: 'Test clip',
      duration: Duration(seconds: 8),
      width: 1280,
      height: 720,
      hasAudio: true,
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
    await tester.tap(find.byTooltip('Export options'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Export audio'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Export audio'), findsOneWidget);
    expect(find.text('Export video'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Finder-opened media is imported and auto-laid out', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(32), appIconPath(64)]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.text('Auto layout picked 1×2 • 16:9.'));

    expect(find.text('2 loaded • 2 collage slots'), findsOneWidget);
    expect(find.text('Auto layout picked 1×2 • 16:9.'), findsOneWidget);
    expect(find.byTooltip('Mute preview'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('preview-duration')),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('ai-metadata-row-clip-1')))
          .height,
      16,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('ai-metadata-row-clip-2')))
          .height,
      16,
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey<String>('remove-media-clip-1')))
          .dx,
      tester
          .getCenter(find.byKey(const ValueKey<String>('remove-media-clip-2')))
          .dx,
    );

    await choosePreviewAutoLayout(tester, 'Vertical layout');

    expect(find.text('2 loaded • 2 collage slots'), findsOneWidget);
    expect(find.text('Vertical Auto picked 2×1 • 9:16.'), findsOneWidget);

    await choosePreviewAutoLayout(tester, 'Horizontal layout');

    expect(find.text('2 loaded • 2 collage slots'), findsOneWidget);
    expect(find.text('Horizontal Auto picked 1×2 • 16:9.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dropping media onto a slot updates an unchanged label', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(32)]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.textContaining('Auto layout picked'));

    final firstSlot = find.byKey(const ValueKey<String>('preview-slot-0'));
    final rootDropTarget = find.byType(DropTarget).first;
    final dropPosition = tester.getCenter(firstSlot);
    tester.widget<DropTarget>(rootDropTarget).onDragDone!(
      DropDoneDetails(
        files: <DropItem>[DropItemFile(appIconPath(64))],
        localPosition: dropPosition,
        globalPosition: dropPosition,
      ),
    );

    await pumpUntilFound(
      tester,
      find.descendant(of: firstSlot, matching: find.text('app_icon_64')),
    );

    expect(
      find.descendant(of: firstSlot, matching: find.text('app_icon_64')),
      findsWidgets,
    );
    expect(
      find.descendant(of: firstSlot, matching: find.text('app_icon_32')),
      findsNothing,
    );
    expect(find.textContaining('1 loaded •'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('preview media uses grab and grabbing cursors for move mode', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(32)]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.textContaining('Auto layout picked'));

    final moveCursor = find.byKey(
      const ValueKey<String>('preview-move-cursor-0'),
    );
    final mouse = await tester.createGesture(
      pointer: 101,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(moveCursor));
    await tester.pump();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );

    await mouse.down(tester.getCenter(moveCursor));
    await tester.pump(const Duration(milliseconds: 221));

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grabbing,
    );

    await mouse.up();
    await tester.pump();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dropping media preserves a custom slot label', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[appIconPath(32)]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.textContaining('Auto layout picked'));

    final firstSlot = find.byKey(const ValueKey<String>('preview-slot-0'));
    await tester.tap(
      find.descendant(of: firstSlot, matching: find.text('app_icon_32')).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'My custom label');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rootDropTarget = find.byType(DropTarget).first;
    final dropPosition = tester.getCenter(firstSlot);
    tester.widget<DropTarget>(rootDropTarget).onDragDone!(
      DropDoneDetails(
        files: <DropItem>[DropItemFile(appIconPath(64))],
        localPosition: dropPosition,
        globalPosition: dropPosition,
      ),
    );

    await pumpUntilFound(
      tester,
      find.descendant(of: firstSlot, matching: find.text('My custom label')),
    );

    expect(find.textContaining('1 loaded •'), findsOneWidget);
    expect(
      find.descendant(of: firstSlot, matching: find.text('app_icon_64')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dropping multiple media replaces slots in wrapped order', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[
      appIconPath(32),
      appIconPath(64),
      appIconPath(128),
    ]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.text('3 loaded • 3 collage slots'));

    final firstSlot = find.byKey(const ValueKey<String>('preview-slot-0'));
    final secondSlot = find.byKey(const ValueKey<String>('preview-slot-1'));
    final thirdSlot = find.byKey(const ValueKey<String>('preview-slot-2'));
    final dropPosition = tester.getCenter(secondSlot);
    tester.widget<DropTarget>(find.byType(DropTarget).first).onDragDone!(
      DropDoneDetails(
        files: <DropItem>[
          DropItemFile(appIconPath(256)),
          DropItemFile(appIconPath(512)),
          DropItemFile(appIconPath(1024)),
          DropItemFile(appIconPath(16)),
        ],
        localPosition: dropPosition,
        globalPosition: dropPosition,
      ),
    );

    await pumpUntilFound(tester, find.text('4 loaded • 3 collage slots'));

    expect(
      find.descendant(of: secondSlot, matching: find.text('app_icon_256')),
      findsWidgets,
    );
    expect(
      find.descendant(of: thirdSlot, matching: find.text('app_icon_512')),
      findsWidgets,
    );
    expect(
      find.descendant(of: firstSlot, matching: find.text('app_icon_1024')),
      findsWidgets,
    );
    expect(
      find.descendant(of: firstSlot, matching: find.text('app_icon_16')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('multi-drop outside the grid starts replacement at slot one', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));
    mockPendingMediaFiles(tester, <String>[
      appIconPath(32),
      appIconPath(64),
      appIconPath(128),
    ]);

    await tester.pumpWidget(buildTestApp());
    await pumpUntilFound(tester, find.text('3 loaded • 3 collage slots'));

    tester.widget<DropTarget>(find.byType(DropTarget).first).onDragDone!(
      DropDoneDetails(
        files: <DropItem>[
          DropItemFile(appIconPath(256)),
          DropItemFile(appIconPath(512)),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );

    final firstSlot = find.byKey(const ValueKey<String>('preview-slot-0'));
    final secondSlot = find.byKey(const ValueKey<String>('preview-slot-1'));
    final thirdSlot = find.byKey(const ValueKey<String>('preview-slot-2'));
    await pumpUntilFound(
      tester,
      find.descendant(of: secondSlot, matching: find.text('app_icon_512')),
    );

    expect(
      find.descendant(of: firstSlot, matching: find.text('app_icon_256')),
      findsWidgets,
    );
    expect(
      find.descendant(of: secondSlot, matching: find.text('app_icon_512')),
      findsWidgets,
    );
    expect(
      find.descendant(of: thirdSlot, matching: find.text('app_icon_128')),
      findsWidgets,
    );
    expect(find.text('3 loaded • 3 collage slots'), findsOneWidget);

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
    await pumpUntilFound(tester, find.text('2 loaded • 2 collage slots'));

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

    expect(find.text('1 loaded • 2 collage slots'), findsOneWidget);
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
    await pumpUntilFound(tester, find.text('3 loaded • 3 collage slots'));

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

    await openResetAllDialog(tester);

    expect(find.text('What would you like to reset?'), findsOneWidget);
    expect(
      find.text('Export history and exported files will be kept.'),
      findsOneWidget,
    );
    expect(find.text('Reset Settings Only'), findsOneWidget);
    expect(find.text('Reset Settings + Media'), findsOneWidget);

    await tester.tap(find.text('Reset Settings Only'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('1 loaded • 4 collage slots'), findsOneWidget);
    expect(find.text('Settings reset. Loaded media kept.'), findsOneWidget);

    await openResetAllDialog(tester);
    await tester.tap(find.text('Reset Settings + Media'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('0 loaded • 4 collage slots'), findsOneWidget);
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

      for (var value = 2; value < 8; value++) {
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

    await expandLayoutAdvancedSettings(tester);
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

    expect(find.text('Fill & crop'), findsWidgets);
    expect(find.text('Fit inside'), findsWidgets);
  });

  testWidgets('palette selection updates the canvas color', (
    WidgetTester tester,
  ) async {
    useTestWindow(tester, const Size(1600, 1000));

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await expandLayoutAdvancedSettings(tester);
    await scrollSettingsIntoView(tester, find.text('Collage background'));

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
  VideoClipInfo? mainVideo;

  @override
  Future<double> probeVideoFrameRate(String path) async {
    return path.contains('second') ? 60 : 29.97;
  }

  @override
  Future<void> mergeVideos({
    required List<VideoClipInfo> videos,
    required String outputPath,
    VideoClipInfo? mainVideo,
    ClipFitMode fitMode = ClipFitMode.cropCenter,
    VideoMergeFrameRateMode frameRateMode = VideoMergeFrameRateMode.firstVideo,
    void Function(VideoExportProgress progress)? onProgress,
  }) async {
    mergeCalls += 1;
    this.videos = List<VideoClipInfo>.of(videos);
    this.mainVideo = mainVideo;
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
