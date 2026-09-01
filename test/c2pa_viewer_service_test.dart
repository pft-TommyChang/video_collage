import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_collage_mac/src/services/c2pa_viewer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('video_collage/c2pa_viewer');

  test('passes the selected media path to Perfect C2PA', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await const C2paViewerService().open('/tmp/signed.png');

    expect(receivedCall?.method, 'openMedia');
    expect(receivedCall?.arguments, <String, String>{
      'path': '/tmp/signed.png',
    });
  });

  test('surfaces a useful message when Perfect C2PA is missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'viewer-not-installed');
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      () => const C2paViewerService().open('/tmp/signed.png'),
      throwsA(
        isA<C2paViewerException>().having(
          (error) => error.message,
          'message',
          contains('not installed'),
        ),
      ),
    );
  });
}
