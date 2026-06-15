#!/bin/bash
# vinput.sh — 前台手动版（终端用：说完按 Ctrl+C 结束转录）。
#
# 与 Raycast 触发的 vinput_bg.sh 完全 parity：以「库模式」(VINPUT_LIB=1) source 后者，
# 复用同一套函数（apply_corrections / 长度感知 clean_with_llm / guard_critical_tokens /
# build_whisper_args）与同一套配置默认值，永不漂移。唯一区别是交互方式：
# 前台录音 + Ctrl+C 停 + 结果打印到终端并复制到剪贴板。
#
# 历史教训：本文件曾内嵌一份**陈旧**的 LLM 提炼逻辑（老 prompt、无 temperature、无纠错表、
# 无守卫、无长度感知），导致它与主路径质量脱节、还会语义反转。改为复用主路径后根治。

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# 库模式 source：只拿函数 + 配置默认值，不跑录音主流程（见 vinput_bg.sh 末尾的 return 守卫）。
# 末尾 "" 占位 $1，避免误命中 vinput_bg.sh 里的 --test-* 钩子。
# shellcheck source=/dev/null
VINPUT_LIB=1 source "$SELF_DIR/vinput_bg.sh" ""

# 热词：库模式不加载主流程里的 HOTWORDS 组装，这里自行读取供 build_whisper_args 用。
if [ -f "$HOTWORDS_FILE" ]; then
    HOTWORDS=$(cat "$HOTWORDS_FILE")
else
    HOTWORDS="使用 Whisper 和 Ollama 做语音转写，用 qwen2.5 整形 prompt。常用工具 Raycast、Claude、Cursor、Codex、Git、GitHub。"
fi

# 并发锁（与主路径同一把锁，互斥）
LOCK_DIR="/tmp/vinput.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "❌ 已有 vinput 任务正在运行，跳过本次"
    exit 0
fi
TMPDIR_RUN=$(mktemp -d -t vinput.XXXXXX)
AUDIO_PATH="$TMPDIR_RUN/voice.wav"
TXT_PATH="$TMPDIR_RUN/voice"
trap 'rm -rf "$LOCK_DIR" "$TMPDIR_RUN"' EXIT

# SoX 录音预处理链（与 vinput_bg.sh 非 VAD 路径一致，streaming-safe）
if [ "${USE_SOX_PREPROCESS:-1}" = "1" ]; then
    SOX_TAIL=(channels 1 rate 16000)
    [ -n "${SOX_HIGHPASS:-}" ] && SOX_TAIL+=(highpass "$SOX_HIGHPASS")
    [ -n "${SOX_LOWPASS:-}" ]  && SOX_TAIL+=(lowpass "$SOX_LOWPASS")
    [ -n "${SOX_GAIN_DB:-}" ]  && SOX_TAIL+=(gain "$SOX_GAIN_DB")
else
    SOX_TAIL=(channels 1 rate 16000 gain -3)
fi

# Ctrl+C 优雅切断录音
trap 'echo -e "\n🛑 录音结束，正在转录..."; break' SIGINT
echo "🎙️  正在录音... 说完后按 [Ctrl + C] 结束并转录"
echo "------------------------------------------------"
while true; do
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" "${SOX_TAIL[@]}" 2>/dev/null
    break
done
trap - SIGINT

if [ ! -f "$AUDIO_PATH" ] || [ ! -s "$AUDIO_PATH" ]; then
    echo "❌ 未捕获到有效的音频信号"
    exit 1
fi

echo "🤖 正在本地转录..."
build_whisper_args "$AUDIO_PATH" "$TXT_PATH"
whisper-cli "${WHISPER_ARGS[@]}" > /dev/null 2>&1

# UTF-8 救援（与主路径同处理）
RAW_RESULT=$(LC_ALL=C sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null)
if ! echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    RAW_RESULT=$(echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)
fi
if [ -z "$RAW_RESULT" ] || [ ${#RAW_RESULT} -le 2 ]; then
    echo "❌ 未识别到有效语音"
    exit 1
fi

# 谐音纠错（与主路径同一张表）
RAW_RESULT=$(apply_corrections "$RAW_RESULT")
echo "📝 原始输入: \"$RAW_RESULT\""

# 长度感知 LLM 整形（与主路径同逻辑：短文本跳过；否则 clean_with_llm 内部按 LONG_TEXT_THRESHOLD 选模板）
RAW_CHARS=$(printf %s "$RAW_RESULT" | wc -m | tr -d ' ')
if [ "$RAW_CHARS" -lt "$SHORT_TEXT_THRESHOLD" ]; then
    echo "⚡ 短文本，跳过 AI 润色"
    CLEANED_RESULT="$RAW_RESULT"
    MODE="short"
else
    echo "🧠 AI 意图重构与去噪（temperature=0，忠实不臆测）..."
    CLEANED_RESULT=$(clean_with_llm "$RAW_RESULT")
    MODE="full"
fi

# 关键 token 丢失守卫（与主路径同）：数字被静默吞掉 → 回退到纠错后的原文
if ! guard_critical_tokens "$MODE" "$RAW_RESULT" "$CLEANED_RESULT"; then
    CLEANED_RESULT="$RAW_RESULT"
    echo "⚠️  润色疑似丢了数字，已回退到原文"
fi

echo "✨ 最终意图: \"$CLEANED_RESULT\""
printf '%s' "$CLEANED_RESULT" | pbcopy
echo "📋 已复制到剪贴板！"
