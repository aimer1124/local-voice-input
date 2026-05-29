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
CORRECTIONS_FILE="${CORRECTIONS_FILE:-$HOME/.config/vinput_corrections.tsv}"
HISTORY_FILE="${HISTORY_FILE:-$HOME/.cache/vinput/history.jsonl}"
HISTORY_MAX_LINES="${HISTORY_MAX_LINES:-1000}"

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

# SoX 录音预处理（v1.1.4 #20，v1.1.7 重写）— 提升任意场景下 Whisper 输入质量
#
# ⚠️ v1.1.4 用 `norm -3` 做峰值归一化，但 `norm` 在 streaming rec 下会先 buffer 整段
# 找 peak —— 用户按"停录"时 rec 被 SIGINT 杀掉，buffer 还没 flush → WAV 0 帧 →
# whisper-cli 报 "failed to read the frames of the audio data" → 外显 "未识别到有效语音"。
# v1.1.7 改成 `gain -3` 固定衰减（streaming 友好），失去了"小声放大"的能力，但稳定。
#
# 想要峰值归一化效果，需要先录完再后处理（v1.3.0 #18 计划方向之一）。
USE_SOX_PREPROCESS="${USE_SOX_PREPROCESS:-1}"
SOX_HIGHPASS="${SOX_HIGHPASS:-80}"     # 切掉风扇 / 街道低频嗡嗡声
SOX_LOWPASS="${SOX_LOWPASS:-8000}"     # 切掉高频白噪 + 嘶嘶声
SOX_GAIN_DB="${SOX_GAIN_DB:--3}"       # 固定增益（负值 = 衰减；正值 = 放大）。streaming OK
REC_WARMUP_MS="${REC_WARMUP_MS:-150}"  # rec 启动后等待 buffer 就绪，避免首字丢失

# 屏幕中央 HUD（替代右上角通知）
HUD_BIN="${HUD_BIN:-$HOME/.whisper_models/hud}"

# 把 HUD_* 样式变量导出到环境，让子进程 hud 二进制能读到
# 任何未设置的会被 hud.swift 用内置默认值兜底
export HUD_Y_PERCENT HUD_HEIGHT HUD_FONT_SIZE HUD_FONT_WEIGHT \
       HUD_CORNER_RADIUS HUD_MATERIAL HUD_WIDTH_MIN HUD_WIDTH_MAX \
       HUD_ON_UP_CMD

# ──────────────────────────────────────────────────────────────
# 谐音/同音纠错表（v1.2.0 #18）— 应用在 Whisper 输出之后、LLM 整形之前。
#
# 格式: <correct><TAB><wrong1><TAB><wrong2>...，# 开头注释。详见
# config/vinput_corrections.example.tsv。
#
# 实现：把整张表编译成一个 sed 脚本（一条规则一个 s|wrong|correct|gI），单次 sed 调用
# 处理整段文本。100 条规则 ~5ms on M1。
# ──────────────────────────────────────────────────────────────
apply_corrections() {
    local text="$1"
    local file="${CORRECTIONS_FILE:-$HOME/.config/vinput_corrections.tsv}"
    [ ! -f "$file" ] && { printf '%s' "$text"; return; }

    local sed_script="" line correct rest wrong c_esc w_esc
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        IFS=$'\t' read -r correct rest <<< "$line"
        [ -z "$correct" ] && continue
        c_esc=$(printf '%s' "$correct" | sed 's/[\\|&]/\\&/g')
        local IFS=$'\t'
        for wrong in $rest; do
            [ -z "$wrong" ] && continue
            w_esc=$(printf '%s' "$wrong" | sed 's/[\\|&]/\\&/g')
            sed_script+="s|$w_esc|$c_esc|gI;"
        done
        unset IFS
    done < "$file"

    if [ -z "$sed_script" ]; then
        printf '%s' "$text"
    else
        printf '%s' "$text" | sed "$sed_script"
    fi
}

# ──────────────────────────────────────────────────────────────
# 列出在给定文本上"应该会命中"的纠错规则（用于 history 日志，#19）。
# 输出每行 "correct\twrong"；空规则集 / 空文本 / 无纠错文件 → 空输出。
# 注意：是 substring 检查（case-insensitive ASCII），不实际改文本。
# ──────────────────────────────────────────────────────────────
list_fired_corrections() {
    local raw="$1"
    local file="${CORRECTIONS_FILE:-$HOME/.config/vinput_corrections.tsv}"
    [ -z "$raw" ] && return 0
    [ ! -f "$file" ] && return 0
    local line correct rest wrong raw_lc wrong_lc
    raw_lc=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        IFS=$'\t' read -r correct rest <<< "$line"
        [ -z "$correct" ] && continue
        local IFS=$'\t'
        for wrong in $rest; do
            [ -z "$wrong" ] && continue
            wrong_lc=$(printf '%s' "$wrong" | tr '[:upper:]' '[:lower:]')
            case "$raw_lc" in
                *"$wrong_lc"*) printf '%s\t%s\n' "$correct" "$wrong" ;;
            esac
        done
        unset IFS
    done < "$file"
}

# ──────────────────────────────────────────────────────────────
# 历史日志（#19）— 每次成功转写后 append 一行到 history.jsonl。
# 字段：ts, raw (Whisper 原文), corrected (纠错后), cleaned (LLM 后),
#       mode (full|raw|short), rules_fired, audio_ms。
# 文件超 HISTORY_MAX_LINES 时翻转到 .old。
# ──────────────────────────────────────────────────────────────
append_history() {
    local raw_pre="$1" corrected="$2" cleaned="$3" mode="$4" audio_path="$5"
    [ -z "$cleaned" ] && return 0
    mkdir -p "$(dirname "$HISTORY_FILE")"

    local audio_ms="0"
    if [ -f "$audio_path" ] && command -v soxi >/dev/null 2>&1; then
        audio_ms=$(soxi -D "$audio_path" 2>/dev/null \
                   | awk '{printf "%d", $1*1000}' \
                   | head -c 10)
        [ -z "$audio_ms" ] && audio_ms="0"
    fi

    local rules_json
    rules_json=$(list_fired_corrections "$raw_pre" \
        | awk -F'\t' 'NF==2 {print $1"←"$2}' \
        | jq -R . | jq -sc .)
    [ -z "$rules_json" ] && rules_json="[]"

    jq -n -c \
        --arg ts "$(date +"%Y-%m-%dT%H:%M:%S%z")" \
        --arg raw "$raw_pre" \
        --arg corrected "$corrected" \
        --arg cleaned "$cleaned" \
        --arg mode "$mode" \
        --argjson rules_fired "$rules_json" \
        --argjson audio_ms "$audio_ms" \
        '{ts:$ts, raw:$raw, corrected:$corrected, cleaned:$cleaned, mode:$mode, rules_fired:$rules_fired, audio_ms:$audio_ms}' \
        >> "$HISTORY_FILE"

    # 轮转：超过上限时把当前切走，开新文件
    if [ "$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)" -gt "$HISTORY_MAX_LINES" ]; then
        mv "$HISTORY_FILE" "${HISTORY_FILE}.old"
    fi
}

# ──────────────────────────────────────────────────────────────
# LLM 整形（#21）— 给定 raw Whisper 文本，调 Ollama 返回去噪后的指令。
# 失败/空响应时返回原文（永不丢用户输入）。
#
# Prompt 的迭代有 tests/llm/ 套件 gate：改这里之前先跑 bash tests/llm/run.sh。
# ──────────────────────────────────────────────────────────────
clean_with_llm() {
    local raw="$1"
    local llm_prompt payload response_json cleaned

    llm_prompt="你是一个口语 → 书面指令的提炼器。把下面用户的口语碎碎念清理成简洁、准确的书面指令。

【硬规则】
1. 删除语气词和无意义重复（嗯、那个、就是、我想说的是…）。
2. 若说话人中途自我纠正（"啊不对，应该是…"），只保留最终意图，丢弃被纠正的部分。
3. **绝对保留数字、否定词、专有名词**：'5个按钮' 不能变成 '几个按钮'；'不要硬编码' 不能变成 '硬编码'；'src/lib' 不能变成 'src 库'。
4. **绝对不要生成代码块**：用户说"写一个组件"——你输出的是\"写一个 React 组件 UserList 渲染 props 数组\"这样的指令，**不是** \`\`\`function UserList() {...} \`\`\`。
5. 保留列表结构（'第一…第二…第三…' 或'1.…2.…3.…'）。
6. 严禁输出任何解释、寒暄、'以下是清理后的指令'之类的引导语。**只输出最终文本本身**。

【示例】
输入: 嗯，那个，我想说的是，帮我改一下这个函数，让它返回数组
输出: 把这个函数改成返回数组

输入: 把它先放到 utils 目录下，啊不对，应该是放到 src/lib 目录下
输出: 把它放到 src/lib 目录下

输入: 帮我写一个 React 组件叫 UserList，从 props 接收数组并渲染列表
输出: 写一个 React 组件 UserList，从 props 接收数组并渲染列表

输入: 把页面上的 5 个按钮去掉吧
输出: 把页面上的 5 个按钮去掉

输入: 记得不要把数据库密码硬编码到代码里
输出: 不要把数据库密码硬编码到代码里

【现在轮到你】
输入: ${raw}
输出:"

    payload=$(jq -n \
        --arg model "$OLLAMA_MODEL" \
        --arg prompt "$llm_prompt" \
        --arg keep_alive "30m" \
        '{model:$model, prompt:$prompt, stream:false, keep_alive:$keep_alive}')

    response_json=$(curl -s -X POST "$OLLAMA_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "$payload")

    cleaned=$(echo "$response_json" | jq -r '.response // empty' \
              | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    if [ -z "$cleaned" ]; then
        printf '%s' "$raw"
    else
        printf '%s' "$cleaned"
    fi
}

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

# ──────────────────────────────────────────────────────────────
# 录音电平 (#4) — 返回 WAV 的 RMS amplitude（0–1，越大越响），无 sox/无文件返回空。
# 只在转写为空的失败路径调用：把含糊的「未识别到有效语音」按实际电平升级成可操作
# 提示。最典型的静默失败是插着只能听的 3 极耳机时，macOS 把输入路由到无信号的耳机口，
# rec 录到一段死寂 WAV，whisper 吐空 —— 用户却完全不知道是麦克风没接上。
# 复用 `vinput --doctor` 同款 sox stat 逻辑，成功路径上一次都不跑。
# ──────────────────────────────────────────────────────────────
audio_rms() {
    local wav="$1"
    [ -f "$wav" ] || return 0
    command -v sox >/dev/null 2>&1 || return 0
    sox "$wav" -n stat 2>&1 | awk '/RMS *amplitude/ {print $3; exit}'
}

# ──────────────────────────────────────────────────────────────
# 首启权限引导 (#8) — 直接打开对应「系统设置 → 隐私」面板，但每个面板只主动开一次
# （flag 落在 ~/.cache/vinput/.<key>），避免每次没授权都把设置窗怼到用户脸上。
# 用法: open_settings_pane <flag-key> <x-apple.systempreferences URL>
# 返回 0 = 这次开了，1 = 之前开过、跳过。
# ──────────────────────────────────────────────────────────────
open_settings_pane() {
    local key="$1" url="$2"
    local flag="$HOME/.cache/vinput/.${key}"
    [ -f "$flag" ] && return 1
    mkdir -p "$(dirname "$flag")" 2>/dev/null
    open "$url" 2>/dev/null
    : > "$flag" 2>/dev/null
    return 0
}

# ──────────────────────────────────────────────────────────────
# Test-only fast path (used by tests/asr/run.sh).
# Skips lock/HUD/rec/pbcopy: feed a WAV, get the raw Whisper output (after
# UTF-8 rescue, before LLM cleaning) on stdout. Exits non-zero on empty.
#
# Keep this branch in sync with the production whisper-cli invocation below —
# both should call the same flags + prompt. The regression suite depends on it.
# ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "--test-llm-clean" ] && [ -n "${2:-}" ]; then
    # tests/llm/run.sh 用：直接喂文本，返回 LLM 整形后的输出。
    clean_with_llm "$2"
    echo
    exit 0
fi

if [ "${1:-}" = "--test-transcribe" ] && [ -n "${2:-}" ]; then
    test_wav="$2"
    [ ! -f "$test_wav" ] && { echo "vinput_bg: no such wav: $test_wav" >&2; exit 2; }

    TMPDIR_RUN=$(mktemp -d -t vinput-test.XXXXXX)
    TXT_PATH="$TMPDIR_RUN/voice"
    trap 'rm -rf "$TMPDIR_RUN"' EXIT

    if [ -f "$HOTWORDS_FILE" ]; then
        HOTWORDS=$(cat "$HOTWORDS_FILE")
    else
        HOTWORDS=""
    fi

    WHISPER_ARGS=(-t "$WHISPER_THREADS" -m "$MODEL_PATH" -f "$test_wav" -l "$WHISPER_LANG")
    [ -n "$WHISPER_BEAM_SIZE" ]       && WHISPER_ARGS+=(--beam-size "$WHISPER_BEAM_SIZE")
    [ -n "$WHISPER_TEMPERATURE" ]     && WHISPER_ARGS+=(--temperature "$WHISPER_TEMPERATURE")
    [ -n "$WHISPER_TEMPERATURE_INC" ] && WHISPER_ARGS+=(--temperature-inc "$WHISPER_TEMPERATURE_INC")
    [ -n "$WHISPER_NO_SPEECH_THOLD" ] && WHISPER_ARGS+=(--no-speech-thold "$WHISPER_NO_SPEECH_THOLD")
    [ -n "$WHISPER_LOGPROB_THOLD" ]   && WHISPER_ARGS+=(--logprob-thold "$WHISPER_LOGPROB_THOLD")
    WHISPER_ARGS+=(--prompt "$HOTWORDS" -otxt -of "$TXT_PATH" -nt -np)

    whisper-cli "${WHISPER_ARGS[@]}" > /dev/null 2>&1 || true

    RAW_RESULT=$(LC_ALL=C sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null || echo "")
    if ! echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        RAW_RESULT=$(echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || echo "")
    fi

    RAW_RESULT=$(apply_corrections "$RAW_RESULT")
    printf '%s\n' "$RAW_RESULT"
    exit 0
fi

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

# 组装 SoX 后处理链（v1.1.7：streaming-safe effects only）
# 顺序：channels/rate（必须靠前）→ highpass → lowpass → gain
# 注意：禁止用 `norm`、`gain -n` 这些需要 buffer 整流的效果 —— 见上面 v1.1.7 注释。
if [ "$USE_SOX_PREPROCESS" = "1" ]; then
    SOX_TAIL=(channels 1 rate 16000)
    [ -n "$SOX_HIGHPASS" ] && SOX_TAIL+=(highpass "$SOX_HIGHPASS")
    [ -n "$SOX_LOWPASS" ]  && SOX_TAIL+=(lowpass "$SOX_LOWPASS")
    [ -n "$SOX_GAIN_DB" ]  && SOX_TAIL+=(gain "$SOX_GAIN_DB")
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

# VINPUT_DEBUG_KEEP=1 时保留最近一次录音 + whisper 输出到 /tmp/vinput-last.*，便于排错。
if [ "${VINPUT_DEBUG_KEEP:-0}" = "1" ]; then
    whisper-cli "${WHISPER_ARGS[@]}" > /tmp/vinput-debug-whisper.out 2>&1
    cp "$AUDIO_PATH" /tmp/vinput-last.wav 2>/dev/null
    cp "${TXT_PATH}.txt" /tmp/vinput-last.txt 2>/dev/null
else
    whisper-cli "${WHISPER_ARGS[@]}" > /dev/null 2>&1
fi

# Whisper 在某些 prompt/audio 组合下会输出损坏 UTF-8（见 v1.1.7 hotwords 迁移注释）。
# sed -E 默认会因非法字节序列退出 1，导致 RAW_RESULT 空 → 误报"未识别到有效语音"。
# 这里用 LC_ALL=C 让 sed 按字节处理，再单独验证 UTF-8 合法性。
RAW_RESULT=$(LC_ALL=C sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null)
# 如果输出包含非法 UTF-8（比如孤立的 continuation byte），用 iconv 过滤掉
if ! echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    RAW_RESULT=$(echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)
fi

if [ -z "$RAW_RESULT" ] || [ ${#RAW_RESULT} -le 2 ]; then
    # #4 静默失败救援：转写为空时先看录音电平，把含糊的失败提示换成可操作诊断。
    # 阈值与 `vinput --doctor` 对齐：<=0.002 几乎死寂、<0.01 偏弱、否则信号正常。
    RMS=$(audio_rms "$AUDIO_PATH")
    if [ -n "$RMS" ] && awk "BEGIN {exit !($RMS <= 0.002)}"; then
        hud "🎤 麦克风几乎没声音 — 拔掉无麦耳机，或检查 系统设置 → 声音 → 输入" 5
    elif [ -n "$RMS" ] && awk "BEGIN {exit !($RMS < 0.01)}"; then
        hud "🔈 声音太小没听清 — 靠近麦克风，或调大 vinput.conf 里的 SOX_GAIN_DB" 5
    else
        # 信号正常却没转出文字：大概率是真没说话 / 纯环境噪声，保留原提示。
        hud "❌ 未识别到有效语音" 3
    fi
    exit 1
fi

# 保留 pre-correction 副本，给 history.jsonl 用（看哪条规则在这次转写中救了场）
RAW_PRE_CORRECTIONS="$RAW_RESULT"

# 谐音/同音纠错（#18）：在 LLM 整形前先打用户自维护的纠错表。
# Whisper 中文模型对英文产品名（Claude/Cloud、Cursor/Cursors）极易混淆，
# 这些 LLM 也救不回来（语义上下文一样），只能靠用户级映射表根治。
RAW_RESULT=$(apply_corrections "$RAW_RESULT")

# 短文本阈值（v1.1.3）：用 wc -m 数字符数（中文 1 字 = 1），不再用字节数。
# 默认 8 字 ≈ 中文短指令的下限（"删除多余文件" 6 字仍走 LLM，"取消" 2 字跳过）。
RAW_CHARS=$(printf %s "$RAW_RESULT" | wc -m | tr -d ' ')
if [ "${VINPUT_RAW:-0}" = "1" ]; then
    MODE="raw"
    CLEANED_RESULT="$RAW_RESULT"
elif [ "$RAW_CHARS" -lt "$SHORT_TEXT_THRESHOLD" ]; then
    MODE="short"
    CLEANED_RESULT="$RAW_RESULT"
else
    MODE="full"
    hud "🤖 AI 润色中..." 30
    CLEANED_RESULT=$(clean_with_llm "$RAW_RESULT")
fi

printf '%s' "$CLEANED_RESULT" | pbcopy

# 自动粘贴 + 辅助功能权限检测 (#8)。
# 没授「辅助功能」时 keystroke 会被拒并返回 -1719（errAEEventNotPermitted，
# 错误码与系统语言无关）。以前这里静默失败：文本只进了剪贴板没贴出去，HUD 还显示
# "✓ 已完成" —— 用户一脸懵。现在捕获这个错误，下面据此给可操作引导。
AX_DENIED=0
if [ "$AUTO_PASTE" = "1" ]; then
    PASTE_ERR=$(osascript -e 'tell application "System Events" to keystroke "v" using command down' 2>&1)
    if [ $? -ne 0 ]; then
        case "$PASTE_ERR" in
            *-1719*|*assistive*) AX_DENIED=1 ;;
        esac
    fi
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

# 历史日志（#19）— 不影响主流程，失败也不报错
append_history "$RAW_PRE_CORRECTIONS" "$RAW_RESULT" "$CLEANED_RESULT" "$MODE" "$AUDIO_PATH" 2>/dev/null || true

# 辅助功能权限缺失 (#8)：文本已在剪贴板，只是没能自动 ⌘V。给可操作引导而不是假装成功，
# 并在第一次遇到时顺手打开「隐私 → 辅助功能」面板（之后不再打扰）。
if [ "$AX_DENIED" = "1" ]; then
    open_settings_pane accessibility \
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    hud "📋 已复制到剪贴板 · 自动粘贴需在「设置 → 隐私 → 辅助功能」勾选 Raycast，先按 ⌘V 用着" 6
    exit 0
fi

# HUD 最终态（#23）— 显示真正粘贴的内容（截断 60 字），给用户视觉确认
HUD_SHOW_RESULT="${HUD_SHOW_RESULT:-1}"
HUD_FINAL_DURATION="${HUD_FINAL_DURATION:-2.5}"
if [ "$HUD_SHOW_RESULT" = "1" ] && [ -n "$CLEANED_RESULT" ]; then
    # 按字符截断（中文 1 字 = 1），不按字节。LC_ALL 让 cut/wc 按 UTF-8 计数。
    HUD_TEXT=$(printf '%s' "$CLEANED_RESULT" | LC_ALL=en_US.UTF-8 cut -c1-60)
    CLEAN_CHARS=$(printf '%s' "$CLEANED_RESULT" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    [ "$CLEAN_CHARS" -gt 60 ] && HUD_TEXT="${HUD_TEXT}…"

    # ↑ 重录 (#23)：HUD_RERUN_ON_UP=1 时把当前脚本路径喂给 hud，HUD 在用户按 ↑ 时
    # 重新启动一次完整流水线。第一次启用需要在系统设置里把 hud 二进制加进输入监控。
    HUD_RERUN_ON_UP="${HUD_RERUN_ON_UP:-0}"
    if [ "$HUD_RERUN_ON_UP" = "1" ]; then
        export HUD_ON_UP_CMD="$0"
    fi

    hud "✓ ${HUD_TEXT}" "$HUD_FINAL_DURATION"
else
    hud "✓ 已完成" 1.2
fi
