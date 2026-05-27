#!/bin/bash
# scripts/make-demo-gif.sh
# 把屏幕录像（mov/mp4）转成 README 里塞的演示 GIF
#
# 流程：
#   1. 你用 macOS 自带 ⇧⌘5 录一段 vinput 演示，保存到 /tmp/demo.mov
#   2. 跑这个脚本：./scripts/make-demo-gif.sh
#   3. 输出到 assets/demo.gif，自动检查文件大小 ≤ 5MB
#
# 可调参数（环境变量）：
#   FPS=15        帧率（10–20 合理）
#   WIDTH=1200    输出宽度（800–1200 合理）
#   QUALITY=85    gifski 质量（60–100）
#   INPUT=...     输入文件路径（默认 /tmp/demo.mov）
#   OUTPUT=...    输出路径（默认 assets/demo.gif）
#   MAX_MB=5      容忍的最大文件大小

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

INPUT="${INPUT:-/tmp/demo.mov}"
OUTPUT="${OUTPUT:-$REPO_DIR/assets/demo.gif}"
FPS="${FPS:-15}"
WIDTH="${WIDTH:-1200}"
QUALITY="${QUALITY:-85}"
MAX_MB="${MAX_MB:-5}"

# ── 颜色（用 $'...' 让 ESC 字符直接嵌入，避免 heredoc 里输出字面量）─
G=$'\033[0;32m'; Y=$'\033[1;33m'; R=$'\033[0;31m'; N=$'\033[0m'
ok()   { echo -e "${G}✓${N} $*"; }
warn() { echo -e "${Y}⚠${N} $*"; }
err()  { echo -e "${R}✗${N} $*"; }
step() { echo -e "\n${Y}▶${N} $*"; }

# ── 输入文件检查 ───────────────────────────────────────
if [ ! -f "$INPUT" ]; then
    cat <<EOF
${R}✗${N} 找不到输入文件: $INPUT

请先录制一段 vinput 演示：

  1. 按 ${Y}⇧⌘5${N} (Shift+Cmd+5) 打开屏幕录制工具栏
  2. 选 "Record Selected Portion" 框选要录的区域
     推荐尺寸: 1200×675 (16:9) 或 1280×720
  3. 点 "Record" 开始
  4. 在录制范围里做完整演示：
     ${G}a)${N} 把光标点进文本框 (备忘录 / TextEdit / 浏览器搜索框等)
     ${G}b)${N} 按 ⌘⇧Space → 等 Pop 提示音
     ${G}c)${N} 大声清晰地说一句话，例如：
        "帮我写一个 Python 函数读取 CSV 然后过滤掉空行"
     ${G}d)${N} 再按 ⌘⇧Space → 等 Tink 提示音
     ${G}e)${N} 看到 HUD 切换：💭转写 → 🤖润色 → ✓ 完成
     ${G}f)${N} 文字自动出现在光标位置
  5. 点菜单栏的录制图标或按 ${Y}⌘^Esc${N} 停止录制
  6. 录像默认保存在桌面，把它移动到:
     ${G}$INPUT${N}
  7. 再跑此脚本

EOF
    exit 1
fi

ok "找到输入: $INPUT ($(du -h "$INPUT" | cut -f1))"

# ── 依赖检查 ──────────────────────────────────────────
for dep in ffmpeg gifski; do
    if ! command -v "$dep" &>/dev/null; then
        warn "未安装 $dep，自动 brew install..."
        brew install "$dep"
    fi
done
ok "依赖齐备: ffmpeg, gifski"

# ── 转换 ─────────────────────────────────────────────
mkdir -p "$(dirname "$OUTPUT")"
TMPDIR=$(mktemp -d -t demogif.XXXXXX)
trap "rm -rf $TMPDIR" EXIT

step "1/3 抽帧 (fps=$FPS, width=$WIDTH)"
ffmpeg -loglevel error -i "$INPUT" \
    -vf "fps=$FPS,scale=$WIDTH:-2:flags=lanczos" \
    "$TMPDIR/frame_%05d.png"

FRAME_COUNT=$(ls "$TMPDIR"/*.png 2>/dev/null | wc -l | xargs)
ok "抽出 $FRAME_COUNT 帧"

step "2/3 编码 GIF (quality=$QUALITY)"
gifski --quiet --quality "$QUALITY" --output "$OUTPUT" "$TMPDIR"/*.png
ok "GIF 已生成"

step "3/3 校验大小"
SIZE_BYTES=$(stat -f%z "$OUTPUT")
SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $SIZE_BYTES / 1048576}")
ls -lh "$OUTPUT"

if [ "$(awk "BEGIN {print ($SIZE_MB > $MAX_MB)}")" = "1" ]; then
    warn "GIF 体积 ${SIZE_MB}MB 超过阈值 ${MAX_MB}MB"
    cat <<EOF

试试用更激进的参数重新生成：

  ${G}FPS=10 WIDTH=900 QUALITY=70 $0${N}

或者重录一段更短的视频（建议 ≤ 25 秒）。
EOF
    exit 1
fi

ok "完成: $OUTPUT (${SIZE_MB}MB)"
echo ""
echo "把它塞到 README.md 顶部："
echo ""
echo "  ![demo](./assets/demo.gif)"
echo ""
