#!/bin/bash

# 被当作函数库 source 时（VINPUT_LIB=1，见文件末尾的 return 守卫）跳过 stderr 重定向 ——
# 否则会把 source 方（如前台版 vinput.sh）的报错也吞进调试日志、终端看不到。
if [ "${VINPUT_LIB:-0}" != "1" ]; then
    LOG_FILE="/tmp/vinput_debug.log"
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
    fi
    exec 2>>"$LOG_FILE"
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Raycast 启动的子进程不继承 Terminal 的 LANG → pbcopy 输出乱码
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

CONFIG_FILE="$HOME/.config/vinput.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

MODEL_PATH="${MODEL_PATH:-$HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
# LLM 整形调用(curl)的总超时秒数。ollama 卡死/正在重载模型时，超时即放弃整形，
# 回退粘贴「原始转写」，避免整条流水线无限挂起（曾因 ollama 后端损坏卡死 >4 分钟，
# 占住锁导致之后每次触发都误判「已停止」）。冷加载大模型慢的机器可调大。
OLLAMA_TIMEOUT="${OLLAMA_TIMEOUT:-15}"
# LLM 预热（v1.8.3）：录音一启动就后台预加载 OLLAMA_MODEL，把「模型冷加载」与「说话+whisper
# 转写」时间重叠。等转写完成时模型已常驻，clean_with_llm 不再吃首次冷启动那十几秒 —— 直接
# 缩短「停止→粘贴」期间的锁占用窗口（这段时间里再按快捷键会撞「⏳ 正在处理上次录音」、开不了新录音）。
# fire-and-forget：失败/超时都不影响录音。设 0 关闭。RAW 模式不过 LLM，下面会自动跳过预热。
OLLAMA_WARMUP="${OLLAMA_WARMUP:-1}"
WHISPER_LANG="${WHISPER_LANG:-zh}"
WHISPER_THREADS="${WHISPER_THREADS:-8}"
SHORT_TEXT_THRESHOLD="${SHORT_TEXT_THRESHOLD:-15}"
# 长内容阈值（v1.8.0）：转写字数 ≥ 此值时，LLM 整形从「提炼成一句」切到「整理+保结构、
# 不摘要、不丢内容」的长内容模板。介于 SHORT 与 LONG 之间走常规提炼。见 clean_with_llm。
LONG_TEXT_THRESHOLD="${LONG_TEXT_THRESHOLD:-80}"
AUTO_PASTE="${AUTO_PASTE:-1}"
# 粘贴成功后 ~1s 把用户原剪贴板内容还原，vinput 不再"吃掉"用户先前复制的文本。
# 仅纯文本可还原（pbpaste 拿不到图片等非文本内容，该场景跳过还原）。
# AUTO_PASTE=0 或自动粘贴失败时绝不还原——那时剪贴板里的结果正是用户要手动 ⌘V 的。
RESTORE_CLIPBOARD="${RESTORE_CLIPBOARD:-1}"
USE_VAD="${USE_VAD:-0}"
SILENCE_TAIL="${SILENCE_TAIL:-1.5}"
SILENCE_START_THRESHOLD="${SILENCE_START_THRESHOLD:-0.5%}"
SILENCE_STOP_THRESHOLD="${SILENCE_STOP_THRESHOLD:-6%}"
MAX_REC_SECONDS="${MAX_REC_SECONDS:-45}"
# Grace (seconds) before a STOP press force-kills a wedged recorder. Pressing the hotkey to stop
# sends rec SIGINT for a clean stop; if rec is still alive after this long it gets SIGKILL'd.
# Why: SoX/rec only checks for SIGINT between audio-buffer reads, so when the CoreAudio input
# device wedges it ignores INT and runs until the MAX_REC_SECONDS+3 hard-timeout KILL (~48s of
# dead lock, observed in the field). This bounds a wedged stop to a few seconds. Healthy stops
# honor INT in <1s, so the kill never fires on them.
STOP_KILL_GRACE="${STOP_KILL_GRACE:-3}"
# Debounce window (seconds) for Raycast double-fires. Raycast occasionally launches a Script
# Command twice for a single hotkey press (confirmed in the field via two same-second invocations);
# the twin that loses the lock race would otherwise stop the just-started recording or flash
# "正在处理上次录音" over the "录音中" HUD — making the press look like it did nothing. A toggle that
# arrives within this many seconds of the lock being created is treated as that duplicate launch
# and ignored. A real stop never lands this fast after a recording starts.
DOUBLE_FIRE_GRACE="${DOUBLE_FIRE_GRACE:-0.7}"
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

# 长音频解码调节（逃生舱，默认全空 = 维持 whisper.cpp 默认）——
# 录音超过 30s 时 whisper 内部按 30s 窗口逐段解码，下面几项控制窗间行为。
#
# ⚠️ 实测踩坑（tests/asr 的 07-zh-long, 66s 样本，见该目录 README「长音频调参」）：
#   这几项**都不是默认开**是有原因的。把 max-context 设小（64/32）不仅没救长句，反而
#   连单窗短句一起退化（截断了 --prompt 热词）：long CER 0.117→0.39、tech 0.025→0.15。
#   entropy-thold / carry-initial-prompt / 加大 beam 在该样本上均**零增益**。
#   也试过换模型（turbo-q8_0、完整 large-v3-q5_0）与静音切片重拼，均未改善甚至更差。
#   结论：长音频 raw CER 的地板是同音字 + 偶发窗口边界漏字，靠这些 flag 调不动 ——
#   真正的兜底在下游的谐音纠错表 + LLM 整形。保留这些 knob 只为手动实验，别当默认开。
WHISPER_ENTROPY_THOLD="${WHISPER_ENTROPY_THOLD:-}"     # 留空 = whisper.cpp 默认 (2.40)
WHISPER_MAX_CONTEXT="${WHISPER_MAX_CONTEXT:-}"         # 留空 = whisper.cpp 默认 (-1)；设小实测有害，见上
WHISPER_CARRY_PROMPT="${WHISPER_CARRY_PROMPT:-0}"      # 1 = 每个窗口都重带初始 prompt；实测无增益

# 动态 prompt 上下文（v1.1.4）— 拼接最近成功转写作为 Whisper 短期记忆
USE_RECENT_PROMPT="${USE_RECENT_PROMPT:-1}"
RECENT_PROMPT_COUNT="${RECENT_PROMPT_COUNT:-5}"
RECENT_PROMPT_FILE="${RECENT_PROMPT_FILE:-$HOME/.cache/vinput/recent.txt}"
# 上下文上限（字符数）。whisper.cpp 的 prompt token 上限 ≈ 224，按中文 1 字 = 1.5 token 估算
RECENT_PROMPT_MAX_CHARS="${RECENT_PROMPT_MAX_CHARS:-280}"

# 按 App 模式覆盖（#43）：TSV 每行「bundle-id<TAB>mode」，mode ∈ raw|en。命中前台 App 时
# 本轮自动切到对应模式（如终端里要命令原文 → raw，跳过 LLM 意图重构）。
# 文件不存在 = 功能关闭（默认），行为零变化。显式用 Raw/EN 快捷键时不覆盖。
APP_MODES_FILE="${APP_MODES_FILE:-$HOME/.config/vinput_app_modes.tsv}"

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
# 组装 whisper-cli 参数 —— 测试钩子 (--test-transcribe) 与生产路径共用同一处。
# 历史上这两处是各写一遍、靠注释提醒「保持同步」，新增 flag 时极易漏改一处导致测试
# 与线上不一致。收敛成一个函数后，flag 只有这一处真相。
# 用法：build_whisper_args <input.wav> <txt_out_prefix>；结果写入全局数组 WHISPER_ARGS。
build_whisper_args() {
    local _in="$1" _of="$2"
    WHISPER_ARGS=(-t "$WHISPER_THREADS" -m "$MODEL_PATH" -f "$_in" -l "$WHISPER_LANG")
    [ -n "$WHISPER_BEAM_SIZE" ]       && WHISPER_ARGS+=(--beam-size "$WHISPER_BEAM_SIZE")
    [ -n "$WHISPER_TEMPERATURE" ]     && WHISPER_ARGS+=(--temperature "$WHISPER_TEMPERATURE")
    [ -n "$WHISPER_TEMPERATURE_INC" ] && WHISPER_ARGS+=(--temperature-inc "$WHISPER_TEMPERATURE_INC")
    [ -n "$WHISPER_NO_SPEECH_THOLD" ] && WHISPER_ARGS+=(--no-speech-thold "$WHISPER_NO_SPEECH_THOLD")
    [ -n "$WHISPER_LOGPROB_THOLD" ]   && WHISPER_ARGS+=(--logprob-thold "$WHISPER_LOGPROB_THOLD")
    [ -n "$WHISPER_ENTROPY_THOLD" ]   && WHISPER_ARGS+=(--entropy-thold "$WHISPER_ENTROPY_THOLD")
    [ -n "$WHISPER_MAX_CONTEXT" ]     && WHISPER_ARGS+=(--max-context "$WHISPER_MAX_CONTEXT")
    [ "$WHISPER_CARRY_PROMPT" = "1" ] && WHISPER_ARGS+=(--carry-initial-prompt)
    WHISPER_ARGS+=(--prompt "$HOTWORDS" -otxt -of "$_of" -nt -np)
}

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
    local llm_prompt payload response_json cleaned n
    n=$(printf '%s' "$raw" | wc -m | tr -d ' ')

    if [ "$n" -ge "$LONG_TEXT_THRESHOLD" ]; then
    # 长内容模板（v1.8.0）：定位是「整理通顺 + 保结构」，不是「压缩成一句」。短内容的提炼器
    # prompt 套到几十秒多点口述上会过度概括、揉平分点 —— 这里换成不摘要、不丢内容的整理器。
    llm_prompt="你是一个口语 → 书面文本的整理器。下面是用户一段较长的口语口述，请整理成通顺、准确的书面文本。

【硬规则】
1. 删除语气词和无意义重复（嗯、那个、就是、我想说的是…），但**不要概括、不要摘要、不要删掉任何有信息量的内容** —— 长内容的目标是「整理通顺」，不是「压缩成一句」。
2. 若说话人中途自我纠正（\"啊不对，应该是…\"），只保留最终意图，丢弃被纠正的部分。
3. **绝对保留数字、否定词、专有名词**：'5个按钮' 不能变成 '几个按钮'；'不要硬编码' 不能变成 '硬编码'；'src/lib' 不能变成 'src 库'。**同样禁止新增原文没有的否定/转折/条件，禁止反转或臆测语义；输入残缺或语义不清时按字面意思保留、不要脑补。**
4. **绝对不要生成代码块**：把口述转成自然语言指令/说明，不是代码。
5. **保留并理顺结构**：口述里的分点（'第一…第二…' 或 '1.…2.…3.…'）原样保留为分点；多个主题用分句/换行分开，别揉成一坨。
6. 严禁输出任何解释、寒暄、'以下是整理后的内容'之类的引导语。**只输出整理后的文本本身**。

【示例】
输入: 嗯我想说的是，首先呢把这个登录页面重构一下，那个，用 hooks 改写，然后第二个就是，加一个加载中的状态，对了还有，记得不要把 token 存到 localStorage 里，要放到 httpOnly 的 cookie
输出: 1. 把登录页面重构，用 hooks 改写。
2. 加一个加载中的状态。
3. 不要把 token 存到 localStorage，放到 httpOnly 的 cookie。

【现在轮到你】
输入: ${raw}
输出:"
    else
    llm_prompt="你是一个口语 → 书面指令的提炼器。把下面用户的口语碎碎念清理成简洁、准确的书面指令。

【硬规则】
1. 删除语气词和无意义重复（嗯、那个、就是、我想说的是…）。
2. 若说话人中途自我纠正（"啊不对，应该是…"），只保留最终意图，丢弃被纠正的部分。
3. **绝对保留数字、否定词、专有名词**：'5个按钮' 不能变成 '几个按钮'；'不要硬编码' 不能变成 '硬编码'；'src/lib' 不能变成 'src 库'。**同样禁止新增原文没有的否定/转折/条件，禁止反转或臆测语义；输入残缺或语义不清时按字面意思保留、不要脑补。**
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
    fi

    payload=$(jq -n \
        --arg model "$OLLAMA_MODEL" \
        --arg prompt "$llm_prompt" \
        --arg keep_alive "30m" \
        '{model:$model, prompt:$prompt, stream:false, keep_alive:$keep_alive, options:{temperature:0}}')

    # --max-time 兜底：ollama 卡死/重载时不会无限等待；超时→空响应→下方回退到原始转写。
    response_json=$(curl -s --connect-timeout 5 --max-time "$OLLAMA_TIMEOUT" \
        -X POST "$OLLAMA_URL/api/generate" \
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

# ──────────────────────────────────────────────────────────────
# 中→英翻译整形（EN 模式，VINPUT_TRANSLATE_EN=1）— 与 clean_with_llm 对称：
# 把中文口语碎碎念翻译并整形成简洁、准确的「英文」书面指令（不只是直译，去口水 + 收紧）。
# 用于「说中文、要英文 prompt」的场景。失败/空响应时返回原文（永不丢用户输入）。
#
# 与 clean_with_llm 一样有测试钩子 --test-llm-clean-en；改这里之前先跑 bash tests/llm/run.sh。
# ──────────────────────────────────────────────────────────────
clean_with_llm_en() {
    local raw="$1"
    local llm_prompt payload response_json cleaned n
    n=$(printf '%s' "$raw" | wc -m | tr -d ' ')

    if [ "$n" -ge "$LONG_TEXT_THRESHOLD" ]; then
    # 长内容模板（v1.8.0）：翻译 + 保结构，不摘要、不丢内容（与 clean_with_llm 对称）。
    llm_prompt="你是一个「中文口语 → 英文书面文本」的翻译整理器。下面是用户一段较长的中文口语口述，请翻译并整理成通顺、准确的【英文】书面文本。

【硬规则】
1. 输出必须是英文。删除语气词和无意义重复（嗯、那个、就是…），但**不要概括、不要摘要、不要删掉任何有信息量的内容**。
2. 若说话人中途自我纠正（\"啊不对，应该是…\"），只保留最终意图，丢弃被纠正的部分。
3. **保留数字、否定词、专有名词/代码标识符**：'5个按钮' → '5 buttons'；'不要硬编码' → 'do not hardcode'（否定不能丢）；'src/lib'、'UserList'、'qwen2.5' 等标识符原样保留、不翻译。**同样禁止新增原文没有的否定/转折/条件、禁止反转或臆测语义；输入残缺时按字面意思保留、不要脑补。**
4. **绝对不要生成代码块**：把口述转成自然语言英文指令/说明，不是代码。
5. **保留并理顺结构**：分点（'第一…第二…' → '1. … 2. … 3. …'）原样保留；多个主题分句/换行分开。
6. 严禁输出任何解释、寒暄、'Here is…' 之类的引导语。**只输出整理后的英文文本本身**。

【示例】
输入: 嗯我想说的是，首先呢把这个登录页面重构一下，那个，用 hooks 改写，然后第二个就是，加一个加载中的状态，对了还有，记得不要把 token 存到 localStorage 里，要放到 httpOnly 的 cookie
输出: 1. Refactor the login page, rewriting it with hooks.
2. Add a loading state.
3. Do not store the token in localStorage; put it in an httpOnly cookie.

【现在轮到你】
输入: ${raw}
输出:"
    else
    llm_prompt="你是一个「中文口语 → 英文书面指令」的提炼翻译器。把下面用户的中文口语碎碎念翻译并清理成简洁、准确的【英文】书面指令。

【硬规则】
1. 输出必须是英文。删除语气词和无意义重复（嗯、那个、就是、我想说的是…）。
2. 若说话人中途自我纠正（\"啊不对，应该是…\"），只保留最终意图，丢弃被纠正的部分。
3. **保留数字、否定词、专有名词/代码标识符**：'5个按钮' → '5 buttons'；'不要硬编码' → 'do not hardcode'（否定不能丢）；'src/lib'、'UserList'、'qwen2.5' 等标识符原样保留、不翻译。**同样禁止新增原文没有的否定/转折/条件、禁止反转或臆测语义；输入残缺时按字面意思保留、不要脑补。**
4. **绝对不要生成代码块**：用户说\"写一个组件\"——你输出 \"Write a React component UserList that renders an array from props\"，**不是** \`\`\`function UserList() {...}\`\`\`。
5. 保留列表结构（'第一…第二…第三…' → '1. … 2. … 3. …'）。
6. 严禁输出任何解释、寒暄、'Here is…' 之类的引导语。**只输出最终英文文本本身**。

【示例】
输入: 嗯，那个，我想说的是，帮我改一下这个函数，让它返回数组
输出: Change this function to return an array

输入: 把它先放到 utils 目录下，啊不对，应该是放到 src/lib 目录下
输出: Put it under src/lib

输入: 帮我写一个 React 组件叫 UserList，从 props 接收数组并渲染列表
输出: Write a React component called UserList that takes an array from props and renders a list

输入: 把页面上的 5 个按钮去掉吧
输出: Remove the 5 buttons on the page

输入: 记得不要把数据库密码硬编码到代码里
输出: Do not hardcode the database password in the code

【现在轮到你】
输入: ${raw}
输出:"
    fi

    payload=$(jq -n \
        --arg model "$OLLAMA_MODEL" \
        --arg prompt "$llm_prompt" \
        --arg keep_alive "30m" \
        '{model:$model, prompt:$prompt, stream:false, keep_alive:$keep_alive, options:{temperature:0}}')

    # --max-time 兜底：ollama 卡死/重载时不会无限等待；超时→空响应→下方回退到原始转写。
    response_json=$(curl -s --connect-timeout 5 --max-time "$OLLAMA_TIMEOUT" \
        -X POST "$OLLAMA_URL/api/generate" \
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

# ──────────────────────────────────────────────────────────────
# 关键 token 丢失守卫（v1.8.0，v1.8.1 收窄为「仅数字」）— LLM 整形后、粘贴前的确定性兜底。
#
# clean_with_llm 的硬规则「保留数字」只是对模型的请求；qwen2.5:3b 在长输入上会静默吞掉数字
# （「5 个」→「几个」）。这里核对 raw（纠错后转写）里的阿拉伯数字是否仍在 cleaned 里；丢失 →
# 返回 1，调用方回退到「纠错后的原文」并给 HUD 警告。
#
# ⚠️ v1.8.1 移除了「否定词守卫」：它对口语中文误判率太高 —— 看不懂 / 能不能 / 是不是 / 差不多
# 里的 不/没 被 LLM 合法删掉时也会触发，导致整句回退到没标点、没润色的原文。中文否定靠子串匹配
# 无法可靠区分语义否定与口语助词，故只保留高价值、低误判的数字守卫。否定保留交回 LLM prompt 硬规则。
#
# 设计原则：宁漏勿误判。保留义务只来自 raw 的阿拉伯数字（纯中文数字「五/二十五」不产生义务）；
# cleaned 侧做单字中文→阿拉伯归一，覆盖「raw 是 5、LLM 改写成五」的合法互转。
# byte-exact：用 LC_ALL=C 做匹配，UTF-8 整字的字节序列匹配是安全的（self-synchronizing）。
# 用法: guard_critical_tokens <mode> <raw> <cleaned>；返回 0=ok，1=疑似丢失。
# ──────────────────────────────────────────────────────────────
guard_critical_tokens() {
    local mode="$1" raw="$2" cleaned="$3"

    # 仅 LLM 真正改写过的路径需要守卫；raw / short 模式 cleaned==raw，无需检查。
    case "$mode" in
        full|full-guard|en|en-guard) ;;
        *) return 0 ;;
    esac

    # —— 数字守卫（full + en 都查，数字跨语言）——
    # 保留义务只来自 raw 里的「阿拉伯数字」：纯中文数字（五 / 二十五）不产生义务（保守放行），
    # 否则按单字映射会把「二十五」拆成 2 和 5 凭空造义务而误判。
    # cleaned 侧做单字中文→阿拉伯归一，覆盖「raw 是 5、LLM 改写成五」这种合法互转。
    local cn2ar='s/〇/0/g;s/零/0/g;s/一/1/g;s/二/2/g;s/两/2/g;s/三/3/g;s/四/4/g;s/五/5/g;s/六/6/g;s/七/7/g;s/八/8/g;s/九/9/g'
    local cleaned_norm nums num
    cleaned_norm=$(printf '%s' "$cleaned" | LC_ALL=C sed "$cn2ar")
    nums=$(printf '%s' "$raw" | LC_ALL=C grep -oE '[0-9]+' || true)
    if [ -n "$nums" ]; then
        while IFS= read -r num; do
            [ -z "$num" ] && continue
            case "$cleaned_norm" in
                *"$num"*) ;;       # 数字仍在 → ok
                *) return 1 ;;     # 数字丢了
            esac
        done <<< "$nums"
    fi

    return 0
}

# ──────────────────────────────────────────────────────────────
# 按 App 模式覆盖（#43）— 录音一启动就取前台 App 的 bundle id，命中 APP_MODES_FILE 里的
# 映射则覆盖本轮模式（raw|en）。
# - 取 bundle id 用 lsappinfo（macOS 自带，~10ms，零权限）——不走 System Events，不新增权限面。
# - 显式用 Raw/EN 快捷键（VINPUT_RAW / VINPUT_TRANSLATE_EN 已置 1）时不覆盖：用户手选优先。
# - 任何失败（无文件 / lsappinfo 异常 / 未命中）→ 静默走默认模式，绝不打扰。
# 用法：app_mode_override [bundle-id]；参数仅测试钩子用，生产路径不传、现场探测。
# ──────────────────────────────────────────────────────────────
app_mode_override() {
    local file="${APP_MODES_FILE:-$HOME/.config/vinput_app_modes.tsv}"
    [ -f "$file" ] || return 0
    [ "${VINPUT_RAW:-0}" = "1" ] && return 0
    [ "${VINPUT_TRANSLATE_EN:-0}" = "1" ] && return 0

    local bid="${1:-}"
    if [ -z "$bid" ]; then
        local asn
        asn=$(lsappinfo front 2>/dev/null)
        [ -z "$asn" ] && return 0
        bid=$(lsappinfo info -only bundleid "$asn" 2>/dev/null \
              | sed -n 's/.*"CFBundleIdentifier"="\([^"]*\)".*/\1/p')
        [ -z "$bid" ] && return 0
    fi

    local id mode _rest
    while IFS=$'\t' read -r id mode _rest || [ -n "$id" ]; do
        case "$id" in ''|'#'*) continue ;; esac
        [ "$id" = "$bid" ] || continue
        case "$mode" in
            raw) VINPUT_RAW=1;          vlog "app-mode:raw app=$bid" ;;
            en)  VINPUT_TRANSLATE_EN=1; vlog "app-mode:en app=$bid" ;;
        esac
        return 0
    done < "$file"
    return 0
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
        osascript -e "display notification \"$msg\" with title \"vinput\"" >/dev/null 2>&1 &
    fi
}

# ──────────────────────────────────────────────────────────────
# 锁/阶段计时日志（诊断）— 把状态机的关键迁移按「时间戳 + 本进程 PID + 事件」追加到
# ~/.cache/vinput/lock.log。每次触发快捷键 = 一个新进程 = 一个新 PID，用 PID 把同一次
# 按键的事件链串起来。用途：当「刚录完、隔几秒再按却开不了新录音」复现时，回看日志即可
# 定位是哪个阶段占着锁、占了多久，以及被拒的那次按键（busy）落在上一轮 release 之前还是
# 之后 —— 前者=处理窗口串行（已知），后者=真·post-paste bug。开销可忽略；VINPUT_LOCK_LOG=0 关闭。
# ──────────────────────────────────────────────────────────────
LOCK_LOG_FILE="$HOME/.cache/vinput/lock.log"
vlog() {
    [ "${VINPUT_LOCK_LOG:-1}" = "1" ] || return 0
    mkdir -p "$(dirname "$LOCK_LOG_FILE")" 2>/dev/null
    printf '%s pid=%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$$" "$*" >> "$LOCK_LOG_FILE" 2>/dev/null
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

if [ "${1:-}" = "--test-llm-clean-en" ] && [ -n "${2:-}" ]; then
    # EN 模式测试钩子：直接喂中文文本，返回翻译整形后的英文输出。
    clean_with_llm_en "$2"
    echo
    exit 0
fi

if [ "${1:-}" = "--test-guard" ] && [ -n "${2:-}" ]; then
    # tests/integration 用：喂 <mode> <raw> <cleaned>，打印 ok|drop（确定性，无需 Ollama）。
    if guard_critical_tokens "${2:-}" "${3:-}" "${4:-}"; then
        echo "ok"
    else
        echo "drop"
    fi
    exit 0
fi

if [ "${1:-}" = "--test-app-mode" ] && [ -n "${2:-}" ]; then
    # tests/integration 用：喂 <bundle-id>，打印覆盖后的模式 raw|en|default（确定性，无外部依赖）。
    app_mode_override "$2"
    if [ "${VINPUT_TRANSLATE_EN:-0}" = "1" ]; then echo "en"
    elif [ "${VINPUT_RAW:-0}" = "1" ]; then echo "raw"
    else echo "default"; fi
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

    build_whisper_args "$test_wav" "$TXT_PATH"

    whisper-cli "${WHISPER_ARGS[@]}" > /dev/null 2>&1 || true

    RAW_RESULT=$(LC_ALL=C sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "${TXT_PATH}.txt" 2>/dev/null || echo "")
    if ! echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        RAW_RESULT=$(echo "$RAW_RESULT" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || echo "")
    fi

    RAW_RESULT=$(apply_corrections "$RAW_RESULT")
    printf '%s\n' "$RAW_RESULT"
    exit 0
fi

# ──────────────────────────────────────────────────────────────
# 库模式守卫：前台版 vinput.sh 用 `VINPUT_LIB=1 source vinput_bg.sh ""` 复用上面的全部函数
# （apply_corrections / clean_with_llm / clean_with_llm_en / guard_critical_tokens /
# build_whisper_args …）+ 同一套配置默认值，从而与主路径完全 parity、永不漂移。
# 此处 return 让 source 方只拿到「函数 + 配置」，不会跑下面的录音/锁/粘贴主流程。
# 正常被 Raycast 执行时 VINPUT_LIB 未设 → 守卫为假 → 主流程照常（行为零变化）。
[ "${VINPUT_LIB:-0}" = "1" ] && return 0 2>/dev/null

LOCK_T0=$(date +%s)
LOCK_DIR="/tmp/vinput.lock.d"
REC_PID_FILE="$LOCK_DIR/rec.pid"

if mkdir "$LOCK_DIR" 2>/dev/null; then
    MODE="record"
else
    MODE="toggle"
fi
vlog "press lock=$([ "$MODE" = record ] && echo free || echo held) mode=$MODE"

if [ "$MODE" = "toggle" ]; then
    # Double-fire debounce (see DOUBLE_FIRE_GRACE): if the lock was created < DOUBLE_FIRE_GRACE
    # seconds ago, this toggle is almost certainly Raycast firing the same keypress twice — the
    # twin already grabbed the lock and is starting to record. Exit silently so we neither stop
    # that recording nor clobber its "录音中" HUD with "正在处理". Sub-second lock age via perl
    # (BSD `date` has no %N); falls back to 999 (never debounce) if perl/stat is unavailable.
    LOCK_AGE_HR=$(perl -MTime::HiRes=time,stat -e \
        'my @s=stat($ARGV[0]); printf "%.3f", @s ? time-$s[9] : 999' "$LOCK_DIR" 2>/dev/null || echo 999)
    if awk "BEGIN{exit !($LOCK_AGE_HR < $DOUBLE_FIRE_GRACE)}"; then
        vlog "toggle:double-fire-debounce age=${LOCK_AGE_HR}s"
        exit 0
    fi

    if [ -f "$REC_PID_FILE" ]; then
        REC_PID=$(cat "$REC_PID_FILE" 2>/dev/null)
        # 锁年龄健全性检查：一次健康录音 = 录音(≤MAX_REC_SECONDS) + 转写(数秒)，远低于此上限。
        # 超过则判定为僵尸录音（守卫没杀掉 rec / rec 被孤儿化），强制回收而不是去「停止」它 ——
        # 否则一个卡死的 rec 会让之后每次触发都卡在「已停止，转写中」。
        LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || date +%s) ))
        STALE_CEILING=$(( MAX_REC_SECONDS + 60 ))
        if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2>/dev/null && [ "$LOCK_AGE" -le "$STALE_CEILING" ]; then
            # Normal toggle: stop the in-progress recording. Send SIGINT for a clean stop (rec
            # finalizes the WAV), then fast-escalate to SIGKILL if rec is still alive after
            # STOP_KILL_GRACE seconds. Why: SoX/rec only checks for SIGINT between audio-buffer
            # reads, so a wedged CoreAudio device makes rec ignore INT and run until the
            # MAX_REC_SECONDS+3 backstop (~48s of dead lock — observed in the field). The user
            # pressed stop NOW, so bound a wedged stop to a few seconds instead. The escalator is
            # detached so it outlives this toggle instance (which exits just below); it re-checks
            # the pid is still a live `rec ` before KILL to avoid a pid-reuse mis-kill (same guard
            # as the zombie-reap branch above).
            kill -INT "$REC_PID" 2>/dev/null
            ( sleep "$STOP_KILL_GRACE"
              if kill -0 "$REC_PID" 2>/dev/null \
                 && ps -p "$REC_PID" -o command= 2>/dev/null | grep -q 'rec '; then
                  kill -KILL "$REC_PID" 2>/dev/null
              fi ) >/dev/null 2>&1 &
            afplay /System/Library/Sounds/Tink.aiff >/dev/null 2>&1 &
            hud "🛑 已停止，转写中..." 60
            vlog "toggle:stop rec_pid=$REC_PID lock_age=${LOCK_AGE}s grace=${STOP_KILL_GRACE}s"
            exit 0
        else
            # pid 已死（上次正在转写）或锁早已过期（僵尸）。若 pid 还活着且确认是 rec 进程，
            # 强杀回收；用 ps 核对命令名，避免误杀 pid 复用后的无关进程。
            if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2>/dev/null \
               && ps -p "$REC_PID" -o command= 2>/dev/null | grep -q 'rec '; then
                kill -INT "$REC_PID" 2>/dev/null; sleep 1
                kill -KILL "$REC_PID" 2>/dev/null
            fi
            rm -rf "$LOCK_DIR"
            if ! mkdir "$LOCK_DIR" 2>/dev/null; then
                hud "❌ 锁冲突，请重试" 2
                vlog "toggle:reap-conflict"
                exit 1
            fi
            MODE="record"
            LOCK_T0=$(date +%s)
            vlog "toggle:reap rec_pid=$REC_PID lock_age=${LOCK_AGE}s -> record"
        fi
    else
        # 无 rec.pid = 上一条正处于「转写/整形/粘贴」阶段（rec 已结束、pid 文件已删）。
        # 正常情况稍等即可。但若那一轮在此阶段被硬杀（SIGKILL/断电/休眠），EXIT trap 来不及
        # 清锁 → 锁被孤儿化、且这里没有 rec.pid 可回收 → 以前会每次都卡在「正在处理」永不自愈，
        # 只能手动 rm -rf /tmp/vinput.lock.d。这里用锁年龄兜底：一次健康全流程（录音
        # ≤MAX_REC_SECONDS + 转写 + 整形≤OLLAMA_TIMEOUT + 粘贴）远低于 STALE_CEILING；
        # 超过即判孤儿锁，回收并直接开始新录音。
        LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || date +%s) ))
        STALE_CEILING=$(( MAX_REC_SECONDS + 60 ))
        if [ "$LOCK_AGE" -le "$STALE_CEILING" ]; then
            vlog "toggle:busy-processing lock_age=${LOCK_AGE}s rejected (no new recording)"
            hud "⏳ 正在处理上次录音" 2
            exit 0
        fi
        # 孤儿锁：强制回收 + 重建 → 落到下面的录音模式
        rm -rf "$LOCK_DIR"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            hud "❌ 锁冲突，请重试" 2
            vlog "toggle:orphan-conflict"
            exit 1
        fi
        MODE="record"
        LOCK_T0=$(date +%s)
        vlog "toggle:orphan-reclaim lock_age=${LOCK_AGE}s -> record"
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

# ⚠️ 所有 detach 的后台子进程（rec/守卫/afplay/预热/剪贴板还原）必须 >/dev/null 2>&1：
# Raycast 要等脚本 stdout 的 EOF 才认为命令结束，任何继承了 stdout 的孤儿进程都会让
# Raycast 把后续快捷键按压悬挂到 EOF 才放行 —— v1.9.1 实测：守卫子 shell 被 kill 后其
# 孤儿 sleep 攥着管道到 rec:start+45s，期间按快捷键连 raycast:fire 都不产生（lock.log
# 里两次「取消后拉不起录音」的恢复时刻都精确 = rec:start+MAX_REC_SECONDS）。
if [ "$USE_VAD" = "1" ]; then
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" \
        silence 1 0.1 "$SILENCE_START_THRESHOLD" 1 "$SILENCE_TAIL" "$SILENCE_STOP_THRESHOLD" \
        "${SOX_TAIL[@]}" >/dev/null 2>&1 &
else
    rec -q -c 1 -r 48000 -b 16 "$AUDIO_PATH" \
        "${SOX_TAIL[@]}" >/dev/null 2>&1 &
fi
REC_PID=$!
echo "$REC_PID" > "$REC_PID_FILE"
vlog "rec:start rec_pid=$REC_PID"

# 按 App 模式覆盖（#43）：以「按下快捷键那一刻」的前台 App 为准（用户说话期间切窗口不改判）。
# 放在 rec 启动之后 —— lsappinfo 的 ~10ms 不挡录音起步；放在预热之前 —— 覆盖成 raw 时跳过预热。
app_mode_override

# LLM 预热（v1.8.3）：rec 已在录音，立刻后台预加载 qwen，让模型冷加载与「说话+whisper 转写」
# 重叠 —— 等下面转写完成时模型已常驻，clean_with_llm 走热路径（秒级），不再吃首次冷启动那十几秒。
# 这正是「第一次录完、马上再按却开不了新录音」卡顿的主因：上一轮的转写+冷 LLM 一直占着锁。
# 空 prompt 即 Ollama 官方的「只加载模型」用法；keep_alive 与真实调用一致(30m)，让后续轮次也热。
# fire-and-forget：连不上/超时都静默放弃，绝不阻塞或影响录音。RAW 模式不过 LLM → 跳过。
if [ "${OLLAMA_WARMUP:-1}" = "1" ] && [ "${VINPUT_RAW:-0}" != "1" ]; then
    warmup_payload=$(jq -n --arg model "$OLLAMA_MODEL" --arg keep_alive "30m" \
        '{model:$model, prompt:"", stream:false, keep_alive:$keep_alive}')
    ( curl -s --connect-timeout 2 --max-time "$OLLAMA_TIMEOUT" \
        -X POST "$OLLAMA_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "$warmup_payload" ) >/dev/null 2>&1 &
fi

# Warmup：等 rec 真正打开音频设备后再给用户「开始」信号，避免首字被 buffer 抖动吃掉。
if [ "$REC_WARMUP_MS" -gt 0 ] 2>/dev/null; then
    sleep "$(awk "BEGIN {print $REC_WARMUP_MS / 1000}")"
fi
afplay /System/Library/Sounds/Pop.aiff >/dev/null 2>&1 &

# ESC 取消：录音期间 1 秒内连按两次 ESC 丢弃本轮（不转写、不粘贴、立刻可重录）。HUD 确认
# 双击后写 cancel 标记并 INT rec；下面 rec 停止后看到标记即清锁退出。为什么双击（v1.9.1）：
# 监控是全局的、录音窗口长达 45s，单击版（v1.9.0）会把用户在其他 App 里按的 ESC（输入法
# 收候选、vim、关弹窗）误认成取消，静默杀掉录音。与 ↑ 重录同一机制：需要给 hud 二进制
# 「输入监控」权限；没给权限时 ESC 只是无效，HUD 与录音一切照常（优雅降级）。
if [ "${HUD_CANCEL_ON_ESC:-1}" = "1" ]; then
    export HUD_ON_ESC_CMD="touch '$LOCK_DIR/cancel' 2>/dev/null && kill -INT $REC_PID 2>/dev/null"
fi
hud "🎙️ 录音中... (再按快捷键停止 · 双击ESC取消)" 60
unset HUD_ON_ESC_CMD   # 只挂在「录音中」这一个 HUD 上，后续阶段的 HUD 不再响应 ESC 取消

# 硬超时守卫：先 INT 优雅停；rec 若拒收 INT（音频设备 wedge 时会发生），3s 后 KILL 兜底。
# ⚠️ 没有这层 KILL，rec 会永久运行 → 锁永不释放 → 之后每次触发都被误判成「已停止，转写中」
#    （实测过一次：rec 卡了两天，必须 kill -9 才掉）。下面的 wait 正常返回后会 kill 掉本守卫，
#    所以正常录音里这层 KILL 永远不会触发。
# 注意：kill GUARD_PID 只杀子 shell，杀不掉它孵的 sleep —— 孤儿 sleep 到点后子命令仍会跑。
# 因此 (a) 整个子 shell 重定向（见上方 ⚠️），孤儿不再攥 Raycast 管道；(b) kill 前重查
# rec.pid 文件仍指向本轮 REC_PID 才动手 —— 正常轮次 rec.pid 早已删除，孤儿到点即空转，
# 也顺带堵了 pid 复用误杀。
( sleep "$MAX_REC_SECONDS"
  [ "$(cat "$REC_PID_FILE" 2>/dev/null)" = "$REC_PID" ] || exit 0
  kill -INT "$REC_PID" 2>/dev/null; sleep 3
  [ "$(cat "$REC_PID_FILE" 2>/dev/null)" = "$REC_PID" ] || exit 0
  kill -KILL "$REC_PID" 2>/dev/null ) >/dev/null 2>&1 &
GUARD_PID=$!

wait "$REC_PID" 2>/dev/null
kill "$GUARD_PID" 2>/dev/null
wait "$GUARD_PID" 2>/dev/null

rm -f "$REC_PID_FILE"
vlog "rec:stop"

# ESC 取消：HUD 在录音期间写入了 cancel 标记 → 丢弃本轮。EXIT trap 会清锁 + tmpdir，
# 退出后立刻可开新录音。放在 Tink/「转写中」之前，取消的轮次不闪任何处理中提示。
# 提示音 + 3s HUD（v1.9.1）：取消必须显眼 —— 无声的 1.5s 提示实测会被错过，用户
# 误以为「录音没拉起」。
if [ -f "$LOCK_DIR/cancel" ]; then
    vlog "exit:cancelled held=$(( $(date +%s) - LOCK_T0 ))s"
    afplay /System/Library/Sounds/Bottle.aiff >/dev/null 2>&1 &
    hud "🚫 已取消 · 未粘贴任何内容" 3
    exit 0
fi

afplay /System/Library/Sounds/Tink.aiff >/dev/null 2>&1 &
hud "💭 转写中..." 30

if [ ! -f "$AUDIO_PATH" ] || [ ! -s "$AUDIO_PATH" ]; then
    vlog "exit:empty-audio"
    hud "❌ 未捕获到有效音频" 3
    exit 1
fi

# 解码参数（v1.1.3 起）：见脚本顶部 WHISPER_* 配置块与 build_whisper_args()。
#   --beam-size 5            5 路 beam search，减少同音字误选
#   --temperature 0          + --temperature-inc 0.2 失败时温度递增重试（避免空输出）
#   --max-context / --entropy-thold / --carry-initial-prompt  长音频抗退化
build_whisper_args "$AUDIO_PATH" "$TXT_PATH"

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
    vlog "exit:empty-transcript rms=${RMS:-NA}"
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
vlog "transcribe:done chars=$RAW_CHARS"
if [ "${VINPUT_TRANSLATE_EN:-0}" = "1" ]; then
    # EN 模式：说中文、要英文 prompt。必过 LLM 翻译整形 —— 忽略短文本跳过，
    # 否则 "取消" 这类短中文会原样输出中文，达不到翻英目的。优先级高于 raw / short。
    MODE="en"
    hud "🌐 翻译成英文中..." 30
    CLEANED_RESULT=$(clean_with_llm_en "$RAW_RESULT")
elif [ "${VINPUT_RAW:-0}" = "1" ]; then
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

# 关键 token 丢失守卫（v1.8.0，v1.8.1 收窄为仅数字）：LLM 改写过的路径，核对数字没被静默吞掉。
# 命中 → 回退到「纠错后的原文」（完整、未丢内容），并置 HUD 警告态。详见 guard_critical_tokens。
GUARD_TRIGGERED=0
if ! guard_critical_tokens "$MODE" "$RAW_RESULT" "$CLEANED_RESULT"; then
    CLEANED_RESULT="$RAW_RESULT"
    GUARD_TRIGGERED=1
    MODE="${MODE}-guard"
fi
vlog "llm:done mode=$MODE"

# 剪贴板恢复（#12 的零成本替代）：pbcopy 前先暂存用户剪贴板。只在会自动粘贴时暂存 ——
# AUTO_PASTE=0 时结果本身就该留在剪贴板里。
SAVED_CLIPBOARD=""
if [ "$RESTORE_CLIPBOARD" = "1" ] && [ "$AUTO_PASTE" = "1" ]; then
    SAVED_CLIPBOARD=$(pbpaste 2>/dev/null || true)
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
vlog "paste:done auto_paste=$AUTO_PASTE ax_denied=$AX_DENIED"

# 剪贴板恢复：⌘V 已发出且未被权限拒绝 → 延迟 1s（等目标 App 真正读完剪贴板）后台还原。
# 粘贴失败（AX_DENIED）时跳过：用户此刻需要剪贴板里是转写结果，好手动 ⌘V。
if [ -n "$SAVED_CLIPBOARD" ] && [ "$AUTO_PASTE" = "1" ] && [ "$AX_DENIED" = "0" ]; then
    ( sleep 1; printf '%s' "$SAVED_CLIPBOARD" | pbcopy ) >/dev/null 2>&1 &
    disown 2>/dev/null
fi

# ── HUD 终态（#23）：先显示结果、释放锁，再做不占锁的记账 ──────────────
# 顺序很重要：HUD 在释放锁之前调用，确保「这一轮的终态」先于「下一轮的录音中」显示，
# 不会被本进程后续的 hud 调用反向覆盖。
HUD_SHOW_RESULT="${HUD_SHOW_RESULT:-1}"
HUD_FINAL_DURATION="${HUD_FINAL_DURATION:-2.5}"
if [ "$AX_DENIED" = "1" ]; then
    # 辅助功能权限缺失 (#8)：文本已在剪贴板、只是没能自动 ⌘V。首次顺手打开「隐私 → 辅助功能」面板。
    open_settings_pane accessibility \
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    hud "📋 已复制到剪贴板 · 自动粘贴需在「设置 → 隐私 → 辅助功能」勾选 Raycast，先按 ⌘V 用着" 6
elif [ "$HUD_SHOW_RESULT" = "1" ] && [ -n "$CLEANED_RESULT" ]; then
    # 按字符截断（中文 1 字 = 1），不按字节。LC_ALL 让 cut/wc 按 UTF-8 计数。
    HUD_TEXT=$(printf '%s' "$CLEANED_RESULT" | LC_ALL=en_US.UTF-8 cut -c1-60)
    CLEAN_CHARS=$(printf '%s' "$CLEANED_RESULT" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    [ "$CLEAN_CHARS" -gt 60 ] && HUD_TEXT="${HUD_TEXT}…"

    # ↑ 重录 (#23)：HUD_RERUN_ON_UP=1 时把当前脚本路径喂给 hud，按 ↑ 重跑整条流水线。
    HUD_RERUN_ON_UP="${HUD_RERUN_ON_UP:-0}"
    if [ "$HUD_RERUN_ON_UP" = "1" ]; then
        export HUD_ON_UP_CMD="$0"
    fi

    # 守卫触发时换成警告前缀：告知用户粘的是原文（润色疑似丢了数字）。
    if [ "${GUARD_TRIGGERED:-0}" = "1" ]; then
        hud "⚠️ 润色疑丢数字·已粘原文: ${HUD_TEXT}" "$HUD_FINAL_DURATION"
    else
        hud "✓ ${HUD_TEXT}" "$HUD_FINAL_DURATION"
    fi
else
    hud "✓ 已完成" 1.2
fi

# ── 提前释放录音锁（v1.8.1）──────────────────────────────────────
# 终态已显示、文本已粘贴 —— 用户此刻就能再次录音，不必等下面的 recent/history 记账。
# 以前锁在脚本退出（记账之后）才释放，紧接着按快捷键会撞「⏳ 正在处理上次录音」。
# 手动释放后 re-arm EXIT trap：退出时只清自己的 tmpdir，绝不误删「新一轮录音」刚建的锁。
vlog "release held=$(( $(date +%s) - LOCK_T0 ))s mode=$MODE"
rm -rf "$LOCK_DIR"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

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
