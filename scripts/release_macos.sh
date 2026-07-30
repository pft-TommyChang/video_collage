#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/release_macos.sh <tag> [repo]

Build the macOS arm64 release artifact from the given git tag, create the
GitHub Release if it does not exist yet, and upload the generated assets.

Examples:
  ./scripts/release_macos.sh v1.4.0
  ./scripts/release_macos.sh v1.4.0 pft-TommyChang/video_collage
EOF
}

log() {
  printf '[release] %s\n' "$*"
}

fail() {
  printf '[release] %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

resolve_repo() {
  local explicit_repo="${1:-}"
  local repo=""

  if [[ -n "$explicit_repo" ]]; then
    printf '%s\n' "$explicit_repo"
    return 0
  fi

  if repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
    if [[ -n "$repo" ]]; then
      printf '%s\n' "$repo"
      return 0
    fi
  fi

  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  repo="$(printf '%s\n' "$remote_url" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"

  [[ -n "$repo" ]] || fail "Unable to determine GitHub repo. Pass it as the second argument."
  printf '%s\n' "$repo"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

TAG="$1"
REPO="$(resolve_repo "${2:-}")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/video-collage-release.XXXXXX")"
WORKTREE_DIR="${TMP_DIR}/source"
NORMALIZED_TAG="${TAG#v}"

cleanup() {
  git -C "$ROOT_DIR" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

require_command git
require_command gh
require_command flutter
require_command hdiutil
require_command shasum

[[ "$(uname -m)" == "arm64" ]] || fail "This script only supports arm64 macOS hosts."

gh auth status >/dev/null 2>&1 || fail "gh is not authenticated. Run: gh auth login"

cd "$ROOT_DIR"

log "Fetching tags from origin"
git fetch --tags origin

git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1 || \
  fail "Remote tag ${TAG} does not exist on origin."

git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1 || \
  fail "Local tag ${TAG} was not found after fetching."

log "Preparing temporary worktree for ${TAG}"
git worktree add --detach "$WORKTREE_DIR" "refs/tags/${TAG}" >/dev/null

VERSION_LINE="$(grep '^version:' "${WORKTREE_DIR}/pubspec.yaml" | awk '{print $2}')"
BUILD_NAME="${VERSION_LINE%%+*}"

[[ "$BUILD_NAME" == "$NORMALIZED_TAG" ]] || \
  fail "Tag version (${NORMALIZED_TAG}) does not match pubspec.yaml (${BUILD_NAME}) in ${TAG}."

log "Building macOS release artifacts from ${TAG}"
(
  cd "$WORKTREE_DIR"
  PACKAGE_ARCH=arm64 \
  RELEASE_TAG="$TAG" \
  TRY_CODEX_RELEASE_NOTES=1 \
    ./scripts/build_release_artifacts.sh
)

mkdir -p "${ROOT_DIR}/dist"

ASSET_PATHS=()
shopt -s nullglob
for asset in "${WORKTREE_DIR}"/dist/*.dmg "${WORKTREE_DIR}"/dist/*.sha256; do
  cp "$asset" "${ROOT_DIR}/dist/"
  ASSET_PATHS+=("${ROOT_DIR}/dist/$(basename "$asset")")
done
shopt -u nullglob

[[ "${#ASSET_PATHS[@]}" -gt 0 ]] || fail "No release assets were generated."

RELEASE_NOTES_FILE="${WORKTREE_DIR}/dist/release_notes.md"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  log "GitHub Release ${TAG} already exists in ${REPO}"
else
  log "Creating GitHub Release ${TAG} in ${REPO}"
  if [[ -s "$RELEASE_NOTES_FILE" ]]; then
    log "Using Codex-generated release notes from ${RELEASE_NOTES_FILE}"
    gh release create "$TAG" \
      --repo "$REPO" \
      --verify-tag \
      --notes-file "$RELEASE_NOTES_FILE" >/dev/null
  else
    log "Falling back to GitHub generated release notes"
    gh release create "$TAG" \
      --repo "$REPO" \
      --verify-tag \
      --generate-notes >/dev/null
  fi
fi

log "Uploading assets to GitHub Release ${TAG}"
gh release upload "$TAG" \
  --repo "$REPO" \
  "${ASSET_PATHS[@]}" \
  --clobber

log "Release completed"
printf '%s\n' "${ASSET_PATHS[@]}"
