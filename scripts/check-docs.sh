#!/bin/bash
# Doc-coverage guard: every user-configurable env var in bin/vinput_bg.sh must be
# mentioned in at least one of the doc surfaces (README.md / README.zh.md /
# config/vinput.conf.example), OR be on the INTERNAL allowlist below.
#
# Why: docs here are hand-maintained (no generator). This catches the common drift —
# someone adds a `FOO="${FOO:-...}"` knob and forgets to document it. Runs in preflight.
#
# Add a new knob → document it (README or conf example) OR, if it's a deliberately
# internal/debug var, add it to INTERNAL_ALLOWLIST with a reason.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/bin/vinput_bg.sh"
DOCS=("$ROOT/README.md" "$ROOT/README.zh.md" "$ROOT/config/vinput.conf.example")

# Deliberately undocumented (internal plumbing / debug-only). Keep this list short and
# justified — anything user-facing belongs in the docs, not here.
INTERNAL_ALLOWLIST=(
    HUD_BIN              # 内部：HUD 二进制路径，由安装脚本管理
    HUD_SHOW_RESULT      # 进阶 HUD 开关，README 以注释形式示例（默认关）
    HUD_FINAL_DURATION   # 同上
    CORRECTIONS_FILE     # 路径由 config 模板隐含；纠错表用法见 config/vinput_corrections.example.tsv
    HISTORY_FILE         # 内部缓存路径
    HISTORY_MAX_LINES    # 内部：历史行数上限
    RECENT_PROMPT_FILE   # 内部缓存路径
    SUGGEST_REMINDER_THRESHOLD  # 内部：挖掘提醒阈值（#49），固定 100 条新记录
    SUGGEST_STATE_FILE   # 内部：挖掘提醒状态文件路径（#49）
    VINPUT_LIB           # 内部：库模式守卫（vinput.sh source 时置 1），非用户旋钮
    VINPUT_RAW           # 由 raycast/voice-input-raw.sh 设置；用户面是「Raw 模式快捷键」而非 env
    VINPUT_TRANSLATE_EN  # 由 raycast/voice-input-en.sh 设置；同上
    VINPUT_DEBUG_KEEP    # debug-only：保留临时音频文件排查用
)

in_allowlist() {
    local v="$1"
    for a in "${INTERNAL_ALLOWLIST[@]}"; do [ "$a" = "$v" ] && return 0; done
    return 1
}

# All user-configurable knobs, two shapes:
#   1) top-level assignments  FOO="${FOO:-default}"  → take the name before '='
#   2) inline reads of VINPUT_* switches  ${VINPUT_FOO:-default}  — these are read
#      inside functions without a top-level assignment (e.g. VINPUT_LOCK_LOG), so
#      shape-1 alone lets them drift undocumented. Only the VINPUT_ prefix is
#      scanned here: unprefixed inline ${VAR:-} matches script-locals (RMS,
#      GUARD_TRIGGERED) and shell builtins (LANG), which are not knobs.
mapfile -t VARS < <({ grep -E '^[A-Z_]+="?\$\{[A-Z_]+:-' "$SCRIPT" | cut -d= -f1
                      grep -oE '\$\{VINPUT_[A-Z_]+:-' "$SCRIPT" | sed 's/^\${//; s/:-$//'
                    } | sort -u)

missing=()
for v in "${VARS[@]}"; do
    in_allowlist "$v" && continue
    if ! grep -qw "$v" "${DOCS[@]}" 2>/dev/null; then
        missing+=("$v")
    fi
done

echo "▶ checked ${#VARS[@]} configurable vars against ${#DOCS[@]} doc surfaces"
if [ "${#missing[@]}" -eq 0 ]; then
    echo "✓ all documented (or allowlisted)"
    exit 0
fi
echo "✗ undocumented config vars (add to a README/conf example, or to INTERNAL_ALLOWLIST with a reason):"
for v in "${missing[@]}"; do echo "    - $v"; done
exit 1
