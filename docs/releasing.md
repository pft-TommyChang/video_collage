# Releasing Perfect Collage

## Versioning

- App version is defined in `pubspec.yaml`.
- The current release version is `1.1.0+1`.
- The format is `build-name+build-number`.
  - `1.1.0` is the user-facing version.
  - `+1` is the internal build number.
- GitHub release tags must match the app version.
  - `v1.1.0` is valid for app version `1.1.0+1`.
  - `1.1.0` is also accepted by the workflow, but `v1.1.0` is the recommended format.
- The release tag only matches the `build-name` part. It does not include the `+build-number`.
- Recommended build number policy:
  - Keep `build-name` semantic, for example `1.1.0`, `1.1.1`, `1.2.0`.
  - Keep `build-number` globally increasing across releases, for example `1.0.0+100`, `1.1.0+101`, `1.2.0+120`.
  - Avoid reusing the same build number forever if you may later add App Store, notarization, or other distribution tooling.

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

## How to publish a release on GitHub

1. Confirm `pubspec.yaml` has the correct version.
2. Commit and push your changes to `main`.
3. In GitHub, open `Releases`.
4. Click `Draft a new release`.
5. Create a new tag using the app version, for example `v1.1.0`.
6. Choose the target branch or commit you want to release.
7. Set the release title, for example `v1.1.0`.
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

## Local build and upload

If you want to build and publish from your local macOS arm64 machine instead of
GitHub Actions:

```bash
./scripts/release_macos.sh v1.1.0
```

This script will:

1. Fetch tags from `origin`.
2. Create a temporary worktree from the target tag.
3. Verify the tag version matches `pubspec.yaml`.
4. Build the macOS release app and package the DMG.
5. Create the GitHub Release if it does not exist yet.
6. Upload the DMG and SHA-256 files to that release.

Requirements:

- `gh` installed and authenticated
- Flutter installed locally
- macOS arm64 host

## Important note about signing

This workflow currently builds an unsigned macOS app and DMG.

That means:

- the release artifact is still distributable
- macOS may show Gatekeeper warnings on another machine

If you want a smoother end-user install flow later, the next step is to add:

- Apple code signing
- notarization
- stapling
