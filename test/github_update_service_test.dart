import 'package:flutter_test/flutter_test.dart';

import 'package:video_collage_mac/src/services/github_update_service.dart';

void main() {
  test('detects a newer GitHub release', () {
    expect(
      GitHubUpdateService.isNewerVersion(
        currentVersion: '1.5.0',
        releaseTag: 'v1.6.0',
      ),
      isTrue,
    );
    expect(
      GitHubUpdateService.isNewerVersion(
        currentVersion: '1.9.9',
        releaseTag: 'v2.0.0',
      ),
      isTrue,
    );
  });

  test('does not report the same or an older release as newer', () {
    expect(
      GitHubUpdateService.isNewerVersion(
        currentVersion: '1.5.0',
        releaseTag: 'v1.5.0',
      ),
      isFalse,
    );
    expect(
      GitHubUpdateService.isNewerVersion(
        currentVersion: '1.5.0',
        releaseTag: 'v1.4.9',
      ),
      isFalse,
    );
  });

  test('accepts build metadata in the local version', () {
    expect(
      GitHubUpdateService.isNewerVersion(
        currentVersion: '1.5.0+150',
        releaseTag: 'v1.5.1',
      ),
      isTrue,
    );
  });
}
