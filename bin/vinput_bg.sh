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

# Whisper 解码参数 — 任何一项设置为空字符串即跳过对应 flag
#
# 历史踩坑：v1.1.3 默认把 no-speech-thold 调到 0.5 / logprob-thold 调到 -0.8（都比
# whisper.cpp 默认值更严），在普通麦的边缘音质下会**整段被丢**，外显是"未识别到有效语音"。
# v1.1.6 起改回 whisper.cpp 默认值 —— 留空即不传 flag，由 whisper.cpp 自己挑默认。
# 想再调严，自己在 vinput.conf 里设回 0.5 / -0.8。
WHISPER_BEAM_SIZE="${WHISPER_BEAM_SIZE:-5}"           # beam search 还是开着，对同音字有用
WHISPER_TEMPERATURE="${WHISPER_TEMPERATURE:-}"        # 留空 = whisper.cpp 默认 (0)
WHISPER_TEMPERATURE_INC="${WHISPER_TEMPERATURE_INC:-0.2}"  # 失败时温度递增重试，避免空输出
WHISPER_NO_SPEECH_THOLD="${WHISPER_NO_SPEECH_THOLD:-}"     # 留空 = whisper.cpp 默认 (0.6)
WHISPER_LOGPROB_THOLD="${WHISPER_LOGPROB_THOLD:-}"         # 留空 = whisper.cpp 默认 (-1.0)

# 动态 prompt 上下文（v1.1.4）— 拼接最近成功转写作为 Whisper 短期记忆
USE_RECENT_PROMPT="${USE_RECENT_PROMPT:-1}"
RECENT_PROMPT_COUNT="${RECENT_PROMPT_COUNT:-5}"
RECENT_PROMPT_FILE="${RECENT_PROMPT_FILE:-$HOME/.cache/vinput/recent.txt}"
# 上下文上限（字符数）。whisper.cpp 的 prompt token 上限 ≈ 224，按中文 1 字 = 1.5 token 估算
RECENT_PROMPT_MAX_CHARS="${RECENT_PROMPT_MAX_CHARS:-280}"

# SoX 录音预处理（v1.1.4 #20）— 提升任意场景下 Whisper 输入质量
USE_SOX_PREPROCESS="${USE_SOX_PREPROCESS:-1}"
SOX_HIGHPASS="${SOX_HIGHPASS:-80}"     # 切掉风扇 / 街道低频嗡嗡声
SOX_LOWPASS="${SOX_LOWPASS:-8000}"     # 切掉高频白噪 + 嘶嘶声
SOX_NORM_DB="${SOX_NORM_DB:--3}"       # 峰值归一化到 -3dB（替代旧的 gain -3 衰减）
REC_WARMUP_MS="${REC_WARMUP_MS:-150}"  # rec 启动后等待 buffer 就绪，避免首字丢失

# 屏幕中央 HUD（替代右上角通知）
HUD_BIN="${HUD_BIN:-$HOME/.whisper_models/hud}"

# 把 HUD_* 样式变量导出到环境，让子进程 hud 二进制能读到
# 任何未设置的会被 hud.swift 用内置默认值兜底
export HUD_Y_PERCENT HUD_HEIGHT HUD_FONT_SIZE HUD_FONT_WEIGHT \
       HUD_CORNER_RADIUS HUD_MATERIAL HUD_WIDTH_MIN HUD_WIDTH_MAX

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

# 热词 / 语境（v1.1.3）：直接使用文件原文作为 prompt。
# Whisper 的 --prompt 是 decoder context，对「带语境的句子」远比「孤立词列表」敏感。
# 例：写成「使用 Whisper 和 Ollama 做语音转写」比「Whisper, Ollama」命中率高 15-25%。
if [ -f "$HOTWORDS_FILE" ]; then
    HOTWORDS=$(cat "$HOTWORDS_FILE")
else
    HOTWORDS="使用 Whisper 和 Ollama 做语音转写，用 qwen2.5 整形 prompt。常用工具 Raycast、Claude、Cursor、Codex、Git、GitHub。"
fi

# 动态 prompt 拼接（v1.1.4 #17）：最近成功转写做 Whisper 短期记忆。
# 顺序：最近 → 远 → 热词。超出 RECENT_PROMPT_MAX_CHARS 截最旧的。
if [ "$USE_RECENT_PROMPT" = "1" ] && [ -f "$RECENT_PROMPT_FILE" ]; then
    # tail -n 取最后 N 条，再倒序成「最近在前」
    RECENT_CTX=$(tail -n "$RECENT_PROMPT_COUNT" "$RECENT_PROMPT_FILE" 2>/dev/null \
                  | awk 'NF' \
                  | tail -r 2>/dev/null \
                  | head -c "$RECENT_PROMPT_MAX_CHARS")
    if [ -n "$RECENT_CTX" ]; then
        HOTWORDS="$RECENT_CTX
$HOTWORDS"
    fi
fi

# 组装 SoX 后处理链（v1.1.4 #20）
# 顺序：channels/rate（必须靠前）→ highpass → lowpass → norm
if [ "$USE_SOX_PREPROCESS" = "1" ]; then
    SOX_TAIL=(channels 1 rate 16000)
    [ -n "$SOX_HIGHPASS" ] && SOX_TAIL+=(highpass "$SOX_HIGHPASS")
    [ -n "$SOX_LOWPASS" ]  && SOX_TAIL+=(lowpass "$SOX_LOWPASS")
    [ -n "$SOX_NORM_DB" ]  && SOX_TAIL+=(norm "$SOX_NORM_DB")
else
    # 兼容老行为：仅必要的下采样 + 固定 -3dB 衰减
    SOX_TAIL=(channels 1 rate 16000 gain -3)
fi

if [ "$USE_VAD" = "1" ]; then
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" \
        silence 1 0.1 "$SILENCE_START_THRESHOLD" 1 "$SILENCE_TAIL" "$SILENCE_STOP_THRESHOLD" \
        "${SOX_TAIL[@]}" &
else
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" \
        "${SOX_TAIL[@]}" &
fi
REC_PID=$!
echo "$REC_PID" > "$REC_PID_FILE"

# Warmup：等 rec 真正打开音频设备后再给用户「开始」信号，避免首字被 buffer 抖动吃掉。
if [ "$REC_WARMUP_MS" -gt 0 ] 2>/dev/null; then
    sleep "$(awk "BEGIN {print $REC_WARMUP_MS / 1000}")"
fi
afplay /System/Library/Sounds/Pop.aiff 2>/dev/null &
hud "🎙️ 录音中... (再按快捷键停止)" 60

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

# 解码参数（v1.1.3）：
#   --beam-size 5            5 路 beam search，减少同音字误选
#   --temperature 0          + --temperature-inc 0.2 失败时温度递增重试（避免空输出）
#   --no-speech-thold 0.5    静音段不再被填充成幻觉
#   --logprob-thold -0.8     低置信度段直接丢
WHISPER_ARGS=(-t "$WHISPER_THREADS" -m "$MODEL_PATH" -f "$AUDIO_PATH" -l "$WHISPER_LANG")
[ -n "$WHISPER_BEAM_SIZE" ]       && WHISPER_ARGS+=(--beam-size "$WHISPER_BEAM_SIZE")
[ -n "$WHISPER_TEMPERATURE" ]     && WHISPER_ARGS+=(--temperature "$WHISPER_TEMPERATURE")
[ -n "$WHISPER_TEMPERATURE_INC" ] && WHISPER_ARGS+=(--temperature-inc "$WHISPER_TEMPERATURE_INC")
[ -n "$WHISPER_NO_SPEECH_THOLD" ] && WHISPER_ARGS+=(--no-speech-thold "$WHISPER_NO_SPEECH_THOLD")
[ -n "$WHISPER_LOGPROB_THOLD" ]   && WHISPER_ARGS+=(--logprob-thold "$WHISPER_LOGPROB_THOLD")
WHISPER_ARGS+=(--prompt "$HOTWORDS" -otxt -of "$TXT_PATH" -nt -np)

whisper-cli "${WHISPER_ARGS[@]}" > /dev/null 2>&1

RAW_RESULT=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null)

if [ -z "$RAW_RESULT" ] || [ ${#RAW_RESULT} -le 2 ]; then
    hud "❌ 未识别到有效语音" 3
    exit 1
fi

# 短文本阈值（v1.1.3）：用 wc -m 数字符数（中文 1 字 = 1），不再用字节数。
# 默认 8 字 ≈ 中文短指令的下限（"删除多余文件" 6 字仍走 LLM，"取消" 2 字跳过）。
RAW_CHARS=$(printf %s "$RAW_RESULT" | wc -m | tr -d ' ')
if [ "$RAW_CHARS" -lt "$SHORT_TEXT_THRESHOLD" ]; then
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

# 写入最近转写缓冲（v1.1.4 #17）— 下次启动时拼为 Whisper prompt 上下文。
# 用 RAW_RESULT（未经 LLM 改写）作 ASR 记忆，避免 LLM 风格污染上下文。
if [ "$USE_RECENT_PROMPT" = "1" ] && [ -n "$RAW_RESULT" ]; then
    mkdir -p "$(dirname "$RECENT_PROMPT_FILE")"
    # append + 仅保留最后 N 条
    printf '%s\n' "$RAW_RESULT" >> "$RECENT_PROMPT_FILE"
    if [ "$(wc -l < "$RECENT_PROMPT_FILE" 2>/dev/null)" -gt "$RECENT_PROMPT_COUNT" ]; then
        tail -n "$RECENT_PROMPT_COUNT" "$RECENT_PROMPT_FILE" > "${RECENT_PROMPT_FILE}.tmp" \
            && mv "${RECENT_PROMPT_FILE}.tmp" "$RECENT_PROMPT_FILE"
    fi
fi

hud "✓ 已完成" 1.2
