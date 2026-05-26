#!/bin/bash

LOG_FILE="/tmp/vinput_debug.log"
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
fi
exec 2>>"$LOG_FILE"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Raycast 启动的子进程不继承 Terminal 的 LANG → pbcopy 输出乱码
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

CONFIG_FILE="$HOME/.config/vinput.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

MODEL_PATH="${MODEL_PATH:-$HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
WHISPER_LANG="${WHISPER_LANG:-zh}"
WHISPER_THREADS="${WHISPER_THREADS:-8}"
SHORT_TEXT_THRESHOLD="${SHORT_TEXT_THRESHOLD:-15}"
AUTO_PASTE="${AUTO_PASTE:-1}"
USE_VAD="${USE_VAD:-0}"
SILENCE_TAIL="${SILENCE_TAIL:-1.5}"
SILENCE_START_THRESHOLD="${SILENCE_START_THRESHOLD:-0.5%}"
SILENCE_STOP_THRESHOLD="${SILENCE_STOP_THRESHOLD:-6%}"
MAX_REC_SECONDS="${MAX_REC_SECONDS:-30}"
HOTWORDS_FILE="${HOTWORDS_FILE:-$HOME/.config/vinput_hotwords.txt}"

# 屏幕中央 HUD（替代右上角通知）
HUD_BIN="${HUD_BIN:-$HOME/.whisper_models/hud}"
hud() {
    local msg="$1"
    local dur="${2:-2.0}"
    if [ -x "$HUD_BIN" ]; then
        # 杀掉上一个 HUD 进程，避免叠加
        if [ -f /tmp/vinput_hud.pid ]; then
            kill "$(cat /tmp/vinput_hud.pid 2>/dev/null)" 2>/dev/null
        fi
        "$HUD_BIN" "$msg" "$dur" >/dev/null 2>&1 &
        disown 2>/dev/null
    else
        # HUD 二进制不存在时降级到系统通知
        osascript -e "display notification \"$msg\" with title \"vinput\"" &
    fi
}

LOCK_DIR="/tmp/vinput.lock.d"
REC_PID_FILE="$LOCK_DIR/rec.pid"

if mkdir "$LOCK_DIR" 2>/dev/null; then
    MODE="record"
else
    MODE="toggle"
fi

if [ "$MODE" = "toggle" ]; then
    if [ -f "$REC_PID_FILE" ]; then
        REC_PID=$(cat "$REC_PID_FILE" 2>/dev/null)
        if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2>/dev/null; then
            kill -INT "$REC_PID" 2>/dev/null
            afplay /System/Library/Sounds/Tink.aiff 2>/dev/null &
            hud "🛑 已停止，转写中..." 60
            exit 0
        else
            rm -rf "$LOCK_DIR"
            if ! mkdir "$LOCK_DIR" 2>/dev/null; then
                hud "❌ 锁冲突，请重试" 2
                exit 1
            fi
            MODE="record"
        fi
    else
        hud "⏳ 正在处理上次录音" 2
        exit 0
    fi
fi

# ============================================================
# 录音模式
# ============================================================
TMPDIR_RUN=$(mktemp -d -t vinput.XXXXXX)
AUDIO_PATH="$TMPDIR_RUN/voice.wav"
TXT_PATH="$TMPDIR_RUN/voice"
trap 'rm -rf "$LOCK_DIR" "$TMPDIR_RUN"' EXIT

if [ -f "$HOTWORDS_FILE" ]; then
    HOTWORDS=$(tr '\n' ',' < "$HOTWORDS_FILE" | sed 's/,/, /g; s/, *$//')
else
    HOTWORDS="API, Playwright, Claude, Codex, Git, URL, PostgreSQL"
fi

afplay /System/Library/Sounds/Pop.aiff 2>/dev/null &
hud "🎙️ 录音中... (再按快捷键停止)" 60

if [ "$USE_VAD" = "1" ]; then
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" \
        silence 1 0.1 "$SILENCE_START_THRESHOLD" 1 "$SILENCE_TAIL" "$SILENCE_STOP_THRESHOLD" \
        channels 1 rate 16000 gain -3 &
else
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" \
        channels 1 rate 16000 gain -3 &
fi
REC_PID=$!
echo "$REC_PID" > "$REC_PID_FILE"

( sleep "$MAX_REC_SECONDS" && kill -INT "$REC_PID" 2>/dev/null ) &
GUARD_PID=$!

wait "$REC_PID" 2>/dev/null
kill "$GUARD_PID" 2>/dev/null
wait "$GUARD_PID" 2>/dev/null

rm -f "$REC_PID_FILE"

afplay /System/Library/Sounds/Tink.aiff 2>/dev/null &
hud "💭 转写中..." 30

if [ ! -f "$AUDIO_PATH" ] || [ ! -s "$AUDIO_PATH" ]; then
    hud "❌ 未捕获到有效音频" 3
    exit 1
fi

whisper-cli -t "$WHISPER_THREADS" -m "$MODEL_PATH" -f "$AUDIO_PATH" \
    -l "$WHISPER_LANG" \
    --prompt "$HOTWORDS" \
    -otxt -of "$TXT_PATH" -nt -np > /dev/null 2>&1

RAW_RESULT=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null)

if [ -z "$RAW_RESULT" ] || [ ${#RAW_RESULT} -le 2 ]; then
    hud "❌ 未识别到有效语音" 3
    exit 1
fi

if [ ${#RAW_RESULT} -lt "$SHORT_TEXT_THRESHOLD" ]; then
    CLEANED_RESULT="$RAW_RESULT"
else
    hud "🤖 AI 润色中..." 30

    LLM_PROMPT="你是一个高效率的程序员指令提炼器。请将下面这段口语碎碎念进行去噪。

规则：
1. 过滤所有语气词。
2. 如果说话人中途自我纠正，请只保留最终正确意图。
3. 将口语表达转化为书面、具有逻辑性的硬核 Prompt 格式，不要生成大段代码。
4. 严格禁止输出任何解释、寒暄，直接输出提炼后的最终文本。

输入文本：$RAW_RESULT"

    PAYLOAD=$(jq -n \
        --arg model "$OLLAMA_MODEL" \
        --arg prompt "$LLM_PROMPT" \
        --arg keep_alive "30m" \
        '{model:$model, prompt:$prompt, stream:false, keep_alive:$keep_alive}')

    RESPONSE_JSON=$(curl -s -X POST "$OLLAMA_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    CLEANED_RESULT=$(echo "$RESPONSE_JSON" | jq -r '.response // empty' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    if [ -z "$CLEANED_RESULT" ]; then
        CLEANED_RESULT="$RAW_RESULT"
    fi
fi

printf '%s' "$CLEANED_RESULT" | pbcopy

if [ "$AUTO_PASTE" = "1" ]; then
    osascript -e 'tell application "System Events" to keystroke "v" using command down'
fi

hud "✓ 已完成" 1.2
