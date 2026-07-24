import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/video_collage_app.dart';

void main() {
  testWidgets('renders app shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoCollageApp());
    await tester.pumpAndSettle();

    expect(find.text('Video Collage Studio'), findsWidgets);
    expect(find.text('Preview'), findsOneWidget);
  });
}
