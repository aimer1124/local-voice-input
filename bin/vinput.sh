#!/bin/bash

# ============================================================
# 加载用户配置（可选，文件不存在时使用默认值）
# 用户可在 ~/.config/vinput.conf 中覆盖任意变量，例如：
#   OLLAMA_MODEL="qwen2.5:1.5b"
#   WHISPER_LANG="zh"
#   SHORT_TEXT_THRESHOLD=20
# ============================================================
CONFIG_FILE="$HOME/.config/vinput.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

MODEL_PATH="${MODEL_PATH:-$HOME/.whisper_models/ggml-small.bin}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
WHISPER_LANG="${WHISPER_LANG:-zh}"
WHISPER_THREADS="${WHISPER_THREADS:-8}"
SHORT_TEXT_THRESHOLD="${SHORT_TEXT_THRESHOLD:-15}"
HOTWORDS_FILE="${HOTWORDS_FILE:-$HOME/.config/vinput_hotwords.txt}"

# 并发锁：mkdir 在 macOS 上比 flock 更可靠（flock 非默认安装）
LOCK_DIR="/tmp/vinput.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "❌ 已有 vinput 任务正在运行，跳过本次"
    exit 0
fi

# 隔离临时文件，防并发互踩
TMPDIR_RUN=$(mktemp -d -t vinput.XXXXXX)
AUDIO_PATH="$TMPDIR_RUN/voice.wav"
TXT_PATH="$TMPDIR_RUN/voice"
trap 'rm -rf "$LOCK_DIR" "$TMPDIR_RUN"' EXIT

# 加载热词：优先读外部文件，每行一个或逗号分隔
if [ -f "$HOTWORDS_FILE" ]; then
    HOTWORDS=$(tr '\n' ',' < "$HOTWORDS_FILE" | sed 's/,/, /g; s/, *$//')
else
    HOTWORDS="API, const, function, Promise, Playwright, Claude, Codex, Git, URL, PostgreSQL"
fi
WHISPER_PROMPT="这是一段程序员的日常对话，包含 $HOTWORDS 等代码术语和简体中文。请输出带标点的简体中文。"

# Ctrl+C 优雅切断录音
trap 'echo -e "\n🛑 录音结束，正在全力转录..."; break' SIGINT

echo "🎙️  正在录音... 说完后请按下 [Ctrl + C] 结束并转录"
echo "------------------------------------------------"

while true; do
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" channels 1 rate 16000 gain -3 2>/dev/null
    break
done
trap - SIGINT

if [ ! -f "$AUDIO_PATH" ] || [ ! -s "$AUDIO_PATH" ]; then
    echo "❌ 未捕获到有效的音频信号"
    exit 1
fi

echo "🤖 正在进行本地高精度文本转录..."
whisper-cli -t "$WHISPER_THREADS" -m "$MODEL_PATH" -f "$AUDIO_PATH" \
    -l "$WHISPER_LANG" \
    --prompt "$WHISPER_PROMPT" \
    -otxt -of "$TXT_PATH" -nt -np > /dev/null 2>&1

# sed trim 替代 xargs：不会因引号/反斜杠丢字符
RAW_RESULT=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null)

if [ -z "$RAW_RESULT" ] || [ ${#RAW_RESULT} -le 2 ]; then
    echo "❌ 未识别到有效语音"
    exit 1
fi

echo "📝 原始输入: \"$RAW_RESULT\""

# 短文本直接跳过 LLM，避免冷启动开销
if [ ${#RAW_RESULT} -lt "$SHORT_TEXT_THRESHOLD" ]; then
    echo "⚡ 短文本，跳过 AI 润色"
    CLEANED_RESULT="$RAW_RESULT"
else
    echo "🧠 正在进行 AI 意图重构与去噪..."

    LLM_PROMPT="你是一个高效率的程序员指令提炼器。请将下面这段口语碎碎念进行去噪。

规则：
1. 过滤所有语气词（呃、那个、啊）。
2. 如果说话人中途自我纠正（例如'改成A...不对改成B'），请只保留最终修正后的正确书面意图。
3. 将口语表达转化为书面、具有逻辑性的硬核 Prompt 格式，不要生成大段代码，只输出提炼后的中文Prompt指令请求。
4. 严格禁止输出任何解释、寒暄，直接输出提炼后的最终文本。

输入文本：$RAW_RESULT"

    # 用 jq 安全构造 JSON，防止引号/换行/反斜杠注入；keep_alive 让模型常驻 30 分钟，下次零启动
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
        echo "⚠️  AI 润色失败，回退到原始识别"
        CLEANED_RESULT="$RAW_RESULT"
    fi
fi

echo "✨ 最终意图: \"$CLEANED_RESULT\""

printf '%s' "$CLEANED_RESULT" | pbcopy
echo "📋 已成功复制到剪贴板！"
