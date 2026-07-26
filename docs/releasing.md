# Releasing Perfect Collage

## Versioning

- App version is defined in `pubspec.yaml`.
- The current release version is `1.0.0+1`.
- GitHub release tags must match the app version.
  - `v1.0.0` is valid for app version `1.0.0+1`.
  - `1.0.0` is also accepted by the workflow, but `v1.0.0` is the recommended format.

## What the release workflow does

When a GitHub Release is published, the workflow in `.github/workflows/release.yml` will:

1. Read the release tag.
2. Verify that the tag version matches `pubspec.yaml`.
3. Build a macOS release app with Flutter.
4. Package the app into a DMG file.
5. Generate a SHA-256 checksum file.
6. Upload both files back to the GitHub Release as assets.

Expected release assets:

- `PerfectCollage-<version>-macos-arm64.dmg`
- `PerfectCollage-<version>-macos-arm64.sha256`
- `PerfectCollage-<version>-macos-x64.dmg`
- `PerfectCollage-<version>-macos-x64.sha256`

## How to publish a release on GitHub

1. Confirm `pubspec.yaml` has the correct version.
2. Commit and push your changes to `main`.
3. In GitHub, open `Releases`.
4. Click `Draft a new release`.
5. Create a new tag using the app version, for example `v1.0.0`.
6. Choose the target branch or commit you want to release.
7. Set the release title, for example `v1.0.0`.
8. Publish the release.
9. Wait for the `Release macOS build` GitHub Actions workflow to finish.
10. Refresh the release page and download the generated DMG asset.

## Local build for verification

You can generate the same release asset locally:

```bash
./scripts/build_release_artifacts.sh
```

The generated files will be placed in:

```text
dist/
```

## Important note about signing

This workflow currently builds an unsigned macOS app and DMG.

That means:

- the release artifact is still distributable
- macOS may show Gatekeeper warnings on another machine

If you want a smoother end-user install flow later, the next step is to add:

- Apple code signing
- notarization
- stapling
