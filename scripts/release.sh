#!/bin/bash
# Release coordinator for local-voice-input.
#
# This script keeps the source repo and Homebrew tap update path explicit:
# it validates the source version, optionally runs preflight, optionally builds
# the HUD binary, and can update the tap formula when the two release checksums
# are supplied.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=""
TAP_DIR="${TAP_DIR:-$HOME/homebrew-tap}"
SOURCE_SHA=""
HUD_SHA=""
APPLY=0
RUN_PREFLIGHT=1
BUILD_HUD=0

usage() {
    cat <<'EOF'
Usage: scripts/release.sh --version X.Y.Z [options]

Options:
  --tap DIR             Homebrew tap repo path (default: ~/homebrew-tap)
  --source-sha SHA      sha256 of https://github.com/aimer1124/local-voice-input/archive/refs/tags/vX.Y.Z.tar.gz
  --hud-sha SHA         sha256 of https://github.com/aimer1124/local-voice-input/releases/download/vX.Y.Z/hud
  --apply               Update Formula/local-voice-input.rb in the tap repo
  --build-hud           Build dist/hud from src/hud.swift
  --skip-preflight      Skip scripts/preflight.sh
  --dry-run             Validate and print planned release actions only (default)

Typical flow:
  scripts/release.sh --version 1.6.0 --build-hud
  # create GitHub release/tag and upload dist/hud, then collect checksums
  scripts/release.sh --version 1.6.0 --tap ~/homebrew-tap --source-sha ... --hud-sha ... --apply
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) shift; VERSION="${1:-}" ;;
        --tap) shift; TAP_DIR="${1:-}" ;;
        --source-sha) shift; SOURCE_SHA="${1:-}" ;;
        --hud-sha) shift; HUD_SHA="${1:-}" ;;
        --apply) APPLY=1 ;;
        --build-hud) BUILD_HUD=1 ;;
        --skip-preflight) RUN_PREFLIGHT=0 ;;
        --dry-run) APPLY=0 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

[ -n "$VERSION" ] || { echo "missing --version" >&2; usage; exit 2; }
case "$VERSION" in
    v*) echo "pass version without leading v, e.g. --version 1.6.0" >&2; exit 2 ;;
esac

FORMULA="$TAP_DIR/Formula/local-voice-input.rb"
SRC_VERSION=$(awk -F'"' '/^VERSION=/ {print $2; exit}' "$ROOT/bin/vinput")

if [ "$SRC_VERSION" != "$VERSION" ]; then
    echo "version mismatch: bin/vinput declares $SRC_VERSION, requested $VERSION" >&2
    exit 1
fi

if ! grep -Fq "v$VERSION" "$ROOT/CHANGELOG.md" && ! grep -Fq "[$VERSION]" "$ROOT/CHANGELOG.md"; then
    echo "CHANGELOG.md does not mention v$VERSION" >&2
    exit 1
fi

if [ "$RUN_PREFLIGHT" = "1" ]; then
    bash "$ROOT/scripts/preflight.sh"
fi

if [ "$BUILD_HUD" = "1" ]; then
    if ! command -v swiftc >/dev/null 2>&1; then
        echo "swiftc not found; cannot build HUD" >&2
        exit 1
    fi
    mkdir -p "$ROOT/dist"
    swiftc -O "$ROOT/src/hud.swift" -o "$ROOT/dist/hud"
    chmod +x "$ROOT/dist/hud"
    echo "built $ROOT/dist/hud"
    if command -v shasum >/dev/null 2>&1; then
        echo "hud sha256: $(shasum -a 256 "$ROOT/dist/hud" | awk '{print $1}')"
    fi
fi

echo ""
echo "Release plan for v$VERSION"
echo "  source tarball: https://github.com/aimer1124/local-voice-input/archive/refs/tags/v$VERSION.tar.gz"
echo "  HUD artifact:   https://github.com/aimer1124/local-voice-input/releases/download/v$VERSION/hud"
echo "  tap formula:    $FORMULA"

if [ "$APPLY" = "0" ]; then
    echo ""
    echo "dry-run only; pass --apply with --source-sha and --hud-sha to update the tap formula"
    exit 0
fi

[ -f "$FORMULA" ] || { echo "missing formula: $FORMULA" >&2; exit 1; }
[ -n "$SOURCE_SHA" ] || { echo "missing --source-sha for --apply" >&2; exit 2; }
[ -n "$HUD_SHA" ] || { echo "missing --hud-sha for --apply" >&2; exit 2; }

tmp_formula="$(mktemp -t local-voice-input-formula.XXXXXX)"
awk \
    -v version="$VERSION" \
    -v source_sha="$SOURCE_SHA" \
    -v hud_sha="$HUD_SHA" '
    /url "https:\/\/github.com\/aimer1124\/local-voice-input\/archive\/refs\/tags\/v/ {
        print "  url \"https://github.com/aimer1124/local-voice-input/archive/refs/tags/v" version ".tar.gz\""
        next
    }
    /^  sha256 "/ && source_done != 1 {
        print "  sha256 \"" source_sha "\""
        source_done = 1
        next
    }
    /url "https:\/\/github.com\/aimer1124\/local-voice-input\/releases\/download\/v/ {
        print "    url \"https://github.com/aimer1124/local-voice-input/releases/download/v" version "/hud\""
        next
    }
    /^    sha256 "/ && hud_done != 1 {
        print "    sha256 \"" hud_sha "\""
        hud_done = 1
        next
    }
    { print }
' "$FORMULA" > "$tmp_formula"
mv "$tmp_formula" "$FORMULA"

echo "updated $FORMULA"
echo "next: run brew audit --strict --online local-voice-input from the tap repo, then commit and push"
