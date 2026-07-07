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
BG="$ROOT/bin/vinput_bg.sh"

[ -x "$VINPUT" ] || { echo "missing $VINPUT"; exit 1; }
[ -f "$BG" ] || { echo "missing $BG"; exit 1; }

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

# 'Code X' 行保持在最后一行：history --tail 1 用例依赖它；前面两行让 corrections --suggest
# 能挖出高频未跟踪英文词 'Cursor'（出现 2 次、不在纠错表/热词里）。
cat > "$TMP_HOME/.cache/vinput/history.jsonl" <<'EOF'
{"ts":"2026-05-30T00:00:00+0800","raw":"用 Cursor 跑一下","corrected":"用 Cursor 跑一下","cleaned":"用 Cursor 跑一下","mode":"full","rules_fired":[],"audio_ms":1200}
{"ts":"2026-05-31T00:00:00+0800","raw":"Cursor 真好用","corrected":"Cursor 真好用","cleaned":"Cursor 真好用","mode":"raw","rules_fired":[],"audio_ms":1100}
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
    case "$out" in *"local-voice-input 1.11.0"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
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

run_case "corrections --suggest mines history" bash -c '
    out=$(HOME="$1" "$2" corrections --suggest 2>&1)
    case "$out" in *"Codex←Code X"*"Cursor"*) exit 0 ;; *) printf "%s\n" "$out"; exit 1 ;; esac
' _ "$TMP_HOME" "$VINPUT"

# 关键 token 丢失守卫（v1.8.0）— 确定性，无需 Ollama。喂 <mode> <raw> <cleaned>，期望 drop|ok。
run_case "guard flags dropped number (full)" bash -c '
    out=$(bash "$1" --test-guard full "把页面上的5个按钮去掉" "把页面上的按钮去掉")
    [ "$out" = "drop" ]
' _ "$BG"

# v1.8.1: negation guard removed (false-fired on conversational 不/没). Numbers-only now.
run_case "guard ignores dropped negation (numbers-only, v1.8.1)" bash -c '
    out=$(bash "$1" --test-guard full "不要硬编码密码" "硬编码密码")
    [ "$out" = "ok" ]
' _ "$BG"

run_case "guard ignores conversational 不/没 drop (v1.8.1)" bash -c '
    out=$(bash "$1" --test-guard full "那我看不懂能不能弄清晰一点" "把这个说得更清楚一点")
    [ "$out" = "ok" ]
' _ "$BG"

run_case "guard passes preserved number (full)" bash -c '
    out=$(bash "$1" --test-guard full "把5个按钮去掉" "把 5 个按钮去掉")
    [ "$out" = "ok" ]
' _ "$BG"

run_case "guard passes cn/arabic numeral swap (full)" bash -c '
    out=$(bash "$1" --test-guard full "把5个按钮去掉" "把五个按钮去掉")
    [ "$out" = "ok" ]
' _ "$BG"

run_case "guard passes en number, skips negation (en)" bash -c '
    out=$(bash "$1" --test-guard en "不要删掉5个按钮" "remove the 5 buttons")
    [ "$out" = "ok" ]
' _ "$BG"

run_case "guard skips non-LLM modes (short)" bash -c '
    out=$(bash "$1" --test-guard short "5个" "取消")
    [ "$out" = "ok" ]
' _ "$BG"

# 按 App 模式覆盖（#43）— 确定性，喂 <bundle-id>，期望 raw|en|default。
cat > "$TMP_HOME/.config/vinput_app_modes.tsv" <<'EOF'
# comment line
com.googlecode.iterm2	raw
com.apple.Terminal	raw
com.tencent.xinWeChat	en
EOF

run_case "app-mode maps terminal to raw" bash -c '
    out=$(APP_MODES_FILE="$1/.config/vinput_app_modes.tsv" bash "$2" --test-app-mode com.googlecode.iterm2)
    [ "$out" = "raw" ]
' _ "$TMP_HOME" "$BG"

run_case "app-mode maps configured app to en" bash -c '
    out=$(APP_MODES_FILE="$1/.config/vinput_app_modes.tsv" bash "$2" --test-app-mode com.tencent.xinWeChat)
    [ "$out" = "en" ]
' _ "$TMP_HOME" "$BG"

run_case "app-mode unmapped app stays default" bash -c '
    out=$(APP_MODES_FILE="$1/.config/vinput_app_modes.tsv" bash "$2" --test-app-mode com.apple.Safari)
    [ "$out" = "default" ]
' _ "$TMP_HOME" "$BG"

run_case "app-mode explicit hotkey wins over map" bash -c '
    out=$(VINPUT_RAW=1 APP_MODES_FILE="$1/.config/vinput_app_modes.tsv" bash "$2" --test-app-mode com.tencent.xinWeChat)
    [ "$out" = "raw" ]
' _ "$TMP_HOME" "$BG"

run_case "app-mode missing file is a no-op" bash -c '
    out=$(APP_MODES_FILE="$1/.config/nonexistent.tsv" bash "$2" --test-app-mode com.googlecode.iterm2)
    [ "$out" = "default" ]
' _ "$TMP_HOME" "$BG"

if [ "$FAIL" = "0" ]; then
    echo "✓ integration tests pass"
    exit 0
fi

echo "✗ integration tests failed"
exit 1
