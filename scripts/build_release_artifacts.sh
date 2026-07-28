#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '[build] %s\n' "$*"
}

generate_release_notes_with_codex() {
  [[ "${TRY_CODEX_RELEASE_NOTES:-0}" == "1" ]] || return 1
  [[ -z "${CI:-}" ]] || return 1

  if ! command -v codex >/dev/null 2>&1; then
    log "Codex CLI not found; skipping local release note generation."
    return 1
  fi

  local release_tag="${RELEASE_TAG:-}"
  if [[ -z "$release_tag" ]]; then
    release_tag="$(git describe --tags --exact-match 2>/dev/null || true)"
  fi

  if [[ -z "$release_tag" ]]; then
    log "No release tag detected; skipping local release note generation."
    return 1
  fi

  local previous_tag
  previous_tag="$(git describe --tags --abbrev=0 "${release_tag}^" 2>/dev/null || true)"
  local git_range="$release_tag"
  if [[ -n "$previous_tag" ]]; then
    git_range="${previous_tag}..${release_tag}"
  fi

  local notes_file="${ROOT_DIR}/dist/release_notes.md"
  mkdir -p "$(dirname "$notes_file")"

  local prompt
  prompt="$(cat <<EOF
Generate GitHub release notes in Markdown for Perfect Collage.

Release tag: ${release_tag}
Previous tag: ${previous_tag:-none}
Git range: ${git_range}

Use the local git repository in the current working directory as the only source of truth.
Requirements:
- Focus on user-visible changes, packaging, release workflow, and compatibility changes.
- Do not invent changes that are not supported by the repository history.
- Keep it concise and readable for a GitHub Release description.
- Output Markdown only, with no code fences.
- Use this structure:
  ## Highlights
  - bullet
  ## Full Changelog
  - bullet
- If this is the first release or the history is sparse, say that briefly and still summarize the most important shipped items.
EOF
)"

  rm -f "$notes_file"
  if codex exec \
    -C "$ROOT_DIR" \
    -a never \
    -s read-only \
    --skip-git-repo-check \
    --output-last-message "$notes_file" \
    --ephemeral \
    "$prompt"; then
    if [[ -s "$notes_file" ]]; then
      log "Generated release notes with Codex at ${notes_file}."
      return 0
    fi
  fi

  rm -f "$notes_file"
  log "Codex release note generation failed; falling back to default release notes."
  return 1
}

VERSION_LINE="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
BUILD_NAME="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE#*+}"

if [[ "$BUILD_NAME" == "$VERSION_LINE" ]]; then
  BUILD_NUMBER="1"
fi

flutter pub get
flutter build macos \
  --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

"$ROOT_DIR/scripts/package_macos_dmg.sh" \
  "$ROOT_DIR/build/macos/Build/Products/Release/Perfect Collage.app" \
  "$BUILD_NAME" \
  "$ROOT_DIR/dist"

generate_release_notes_with_codex || true
