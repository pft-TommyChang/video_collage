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
- Write in Traditional Chinese.
- Include only user-visible features and bug fixes. Mention packaging, compatibility,
  or release workflow changes only when they directly affect users.
- Do not invent changes that are not supported by the repository history.
- Keep every bullet to one short sentence and remove implementation details.
- Group changes under these headings:
  ## ✨ 新增功能
  ## 🚀 體驗改善
  ## 🐛 修正問題
  ## 🔧 維護更新
- Under each heading, use concise bullets in this format:
  - **短標題**：一句話說明。
- Omit a section when there are no matching changes.
- Use 維護更新 only for changes that directly affect installation, compatibility, or delivery.
- Put an important user-facing limitation in a Markdown note instead of a change section:
  > [!NOTE]
  > 一句話注意事項。
- Omit the note when there is no important limitation.
- Do not use Major changes, Minor changes, Highlights, or a summary paragraph.
- Output Markdown only, with no code fences.
- End with exactly one comparison link in this format when a previous tag exists:
  **完整變更**：https://github.com/pft-TommyChang/video_collage/compare/${previous_tag:-PREVIOUS_TAG}...${release_tag}
- For the first release, omit the comparison link.
- If the history is sparse, report only changes that can be verified; do not add filler text.
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

"$ROOT_DIR/scripts/install_c2patool_macos.sh" \
  "$ROOT_DIR/build/macos/Build/Products/Release/Perfect Collage.app"

"$ROOT_DIR/scripts/package_macos_dmg.sh" \
  "$ROOT_DIR/build/macos/Build/Products/Release/Perfect Collage.app" \
  "$BUILD_NAME" \
  "$ROOT_DIR/dist"

generate_release_notes_with_codex || true
