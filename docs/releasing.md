# Releasing Perfect Collage

## Versioning

- App version is defined in `pubspec.yaml`.
- The current release version is `1.4.0+140`.
- The format is `build-name+build-number`.
  - `1.4.0` is the user-facing version.
  - `+140` is the internal build number.
- GitHub release tags must match the app version.
  - `v1.4.0` is valid for app version `1.4.0+140`.
  - `1.4.0` is also accepted by the workflow, but `v1.4.0` is the recommended format.
- The release tag only matches the `build-name` part. It does not include the `+build-number`.
- Recommended build number policy:
  - Keep `build-name` semantic, for example `1.3.0`, `1.3.1`, `1.4.0`.
  - Keep `build-number` globally increasing across releases, for example `1.2.0+120`, `1.3.0+130`, `1.4.0+140`.
  - Avoid reusing the same build number forever if you may later add App Store, notarization, or other distribution tooling.

## What the release workflow does

When a GitHub Release is published, the workflow in `.github/workflows/release.yml` will:

1. Read the release tag.
2. Verify that the tag version matches `pubspec.yaml`.
3. Build the macOS and Windows release apps on native GitHub-hosted runners.
4. Package macOS as a DMG and Windows x64 as a portable ZIP.
5. Generate SHA-256 checksum files.
6. Upload all files back to the GitHub Release as assets.

Expected release assets:

- `PerfectCollage-<version>-macos-arm64.dmg`
- `PerfectCollage-<version>-macos-arm64.sha256`
- `PerfectCollage-<version>-windows-x64.zip`
- `PerfectCollage-<version>-windows-x64.sha256`

## How to publish a release on GitHub

1. Confirm `pubspec.yaml` has the correct version.
2. Commit and push your changes to `main`.
3. In GitHub, open `Releases`.
4. Click `Draft a new release`.
5. Create a new tag using the app version, for example `v1.4.0`.
6. Choose the target branch or commit you want to release.
7. Set the release title, for example `v1.4.0`.
8. Publish the release.
9. Wait for the `Release desktop builds` GitHub Actions workflow to finish.
10. Refresh the release page and download the generated desktop assets.

## Local build for verification

On macOS, generate the macOS release asset locally:

```bash
./scripts/build_release_artifacts.sh
```

The generated files will be placed in:

```text
dist/
```

On Windows, generate the Windows x64 portable release locally from PowerShell:

```powershell
.\scripts\build_windows_release.ps1
```

Flutter desktop builds are host-specific: macOS cannot run `flutter build
windows`. To produce Windows artifacts while working from a Mac, use this
repository's GitHub Actions release workflow or a Windows VM/machine with
Visual Studio's Desktop development with C++ workload installed.

## Local build and upload

If you want to build and publish from your local macOS arm64 machine instead of
GitHub Actions:

```bash
./scripts/release_macos.sh v1.4.0
```

This script will:

1. Fetch tags from `origin`.
2. Create a temporary worktree from the target tag.
3. Verify the tag version matches `pubspec.yaml`.
4. Build the macOS release app and package the DMG.
5. On a local machine, try to generate release notes with the system `codex` CLI first.
6. If Codex notes are unavailable, fall back to GitHub auto-generated release notes.
7. Create the GitHub Release if it does not exist yet.
8. Upload the DMG and SHA-256 files to that release.

Requirements:

- `gh` installed and authenticated
- Flutter installed locally
- macOS arm64 host

Notes:

- Codex-generated release notes are only attempted for the local upload flow in `./scripts/release_macos.sh`.
- If `codex` is not installed, not authenticated, or fails to return notes, the script keeps the old behavior and uses `gh release create --generate-notes`.

## Important note about signing

This workflow currently builds unsigned macOS and Windows artifacts.

That means:

- the release artifact is still distributable
- macOS may show Gatekeeper warnings on another machine
- Windows may show a Microsoft Defender SmartScreen warning

If you want a smoother end-user install flow later, the next step is to add:

- Apple code signing
- notarization
- stapling
- Windows Authenticode code signing
