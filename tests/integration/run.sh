#!/bin/bash
# Lightweight CLI integration tests.
#
# This suite avoids microphone, network, HUD display, pbcopy, and Ollama calls.
# It verifies that the public CLI entrypoints render usable output and that the
# quick doctor includes the config/runtime/Raycast diagnostics that protect the
# three-layer project layout.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
VINPUT="$ROOT/bin/vinput"

[ -x "$VINPUT" ] || { echo "missing $VINPUT"; exit 1; }

TMP_HOME="$(mktemp -d -t vinput-integration.XXXXXX)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.config/raycast-scripts" "$TMP_HOME/.cache/vinput" "$TMP_HOME/.whisper_models"
printf 'fake model\n' > "$TMP_HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin"
printf '#!/bin/bash\nexit 0\n' > "$TMP_HOME/.whisper_models/hud"
chmod +x "$TMP_HOME/.whisper_models/hud"
ln -s "$ROOT/bin/vinput" "$TMP_HOME/.whisper_models/vinput"
ln -s "$ROOT/bin/vinput_bg.sh" "$TMP_HOME/.whisper_models/vinput_bg.sh"
ln -s "$ROOT/bin/vinput.sh" "$TMP_HOME/.whisper_models/vinput.sh"
cp "$ROOT/raycast/"*.sh "$TMP_HOME/.config/raycast-scripts/"
chmod +x "$TMP_HOME/.config/raycast-scripts/"*.sh

cat > "$TMP_HOME/.config/vinput.conf" <<EOF
MODEL_PATH="$TMP_HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin"
HUD_BIN="$TMP_HOME/.whisper_models/hud"
RAYCAST_DIR="$TMP_HOME/.config/raycast-scripts"
AUTO_PASTE=0
EOF

cat > "$TMP_HOME/.config/vinput_corrections.tsv" <<'EOF'
Codex	Code X
EOF

cat > "$TMP_HOME/.cache/vinput/history.jsonl" <<'EOF'
{"ts":"2026-06-01T00:00:00+0800","raw":"Code X","corrected":"Codex","cleaned":"Codex","mode":"raw","rules_fired":["Codex←Code X"],"audio_ms":1000}
EOF

FAIL=0

run_case() {
    local name="$1"
    shift
    echo "▶ $name"
    if "$@"; then
        echo "  PASS"
    else
        echo "  FAIL"
        FAIL=1
    fi
}

contains() {
    local haystack="$1" needle="$2"
    case "$haystack" in
        *"$needle"*) return 0 ;;
        *) return 1 ;;
    esac
}

run_case "version" bash -c '
    out=$(HOME="$1" "$2" --version)
    case "$out" in *"local-voice-input 1.7.2"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

run_case "help includes new commands" bash -c '
    out=$(HOME="$1" "$2" --help)
    case "$out" in *"--doctor [--quick]"*"vinput config"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

run_case "config prints effective paths" bash -c '
    out=$(HOME="$1" "$2" config)
    case "$out" in *"有效配置"*"$1/.config/raycast-scripts"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

run_case "corrections reads configured TSV" bash -c '
    out=$(HOME="$1" "$2" corrections)
    case "$out" in *"Codex"*"Code X"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

run_case "history reads JSONL" bash -c '
    out=$(HOME="$1" "$2" history --tail 1)
    case "$out" in *"raw"*"Code X"*"Codex"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

run_case "quick doctor shows structural diagnostics" bash -c '
    out=$(HOME="$1" "$2" doctor --quick 2>&1 || true)
    case "$out" in *"有效配置"*"运行目录"*"Raycast 命令"*"quick 模式"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

if [ "$FAIL" = "0" ]; then
    echo "✓ integration tests pass"
    exit 0
fi

echo "✗ integration tests failed"
exit 1
