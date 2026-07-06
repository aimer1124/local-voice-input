#!/bin/bash
# local-voice-input 一键安装脚本（部署的 CLI 工具名为 vinput）
# 用法: ./install.sh [--dry-run] [--skip-models] [--upgrade-only] [-h|--help]

set -e

VERSION="1.9.0"
GITHUB_REPO="aimer1124/local-voice-input"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$HOME/.whisper_models"
CONFIG_DIR="$HOME/.config"
RAYCAST_DIR="$HOME/.config/raycast-scripts"

WHISPER_MODEL_NAME="ggml-large-v3-turbo-q5_0.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${WHISPER_MODEL_NAME}"
OLLAMA_MODEL="qwen2.5:3b"
HUD_RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/hud"

# ── 颜色输出 ─────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*"; }
step() { echo -e "\n${YELLOW}▶${NC} $*"; }
skip() { echo -e "${CYAN}⊘${NC} $*"; }

# ── 选项解析 ─────────────────────────────────────────
DRY_RUN=0
SKIP_MODELS=0
UPGRADE_ONLY=0

usage() {
    cat <<EOF
local-voice-input 安装脚本 (v$VERSION)

用法: ./install.sh [选项]

选项:
  --dry-run        只做只读的环境检查，打印将要执行的动作，不下载 / 不写任何文件
  --skip-models    跳过 Whisper (~550MB) 与 Ollama (~2GB) 模型下载
                   （离线机：假设模型已用 USB 拷到 ~/.whisper_models / ollama）
  --upgrade-only   只更新运行时脚本和 HUD，跳过依赖安装与模型下载（二次安装 / 升级用）
  -h, --help       显示本帮助并退出

不带选项 = 全量安装（首次安装用）。可组合，例如 --dry-run --upgrade-only。
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1 ;;
        --skip-models)  SKIP_MODELS=1 ;;
        --upgrade-only) UPGRADE_ONLY=1 ;;
        -h|--help)      usage; exit 0 ;;
        *) err "未知选项: $1"; echo; usage; exit 2 ;;
    esac
    shift
done

# upgrade-only 蕴含「跳过模型」—— 它只负责把脚本和 HUD 刷新到最新版本。
[ "$UPGRADE_ONLY" = "1" ] && SKIP_MODELS=1

# run：dry-run 下只打印意图，否则真正执行。仅用于「单条命令 + 参数」，
# 复合逻辑（curl && mv、|| 兜底）在各步骤里单独用 $DRY_RUN 守卫。
run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}[dry-run]${NC} 将执行: $*"
    else
        "$@"
    fi
}

# install_atomic <src> <dst>：原子部署可执行脚本/二进制。
# 先 cp 到同目录临时文件、chmod +x，再 mv 改名（同盘 rename 原子）。
# ⚠️ 为什么不能直接 cp 覆盖：bash 是按字节偏移边读边执行脚本，若升级时正好有一轮 vinput_bg.sh
# 在跑，cp 原地改写会让运行中的进程从新文件错误偏移读到半个 token 而崩溃（v1.8.1 实测：
# "syntax error near unexpected token 'fi'"，那一轮卡在"转写中"）。mv 让运行中的进程继续持有
# 旧 inode、完全不受影响，新内容只对下一次调用生效。
install_atomic() {
    local src="$1" dst="$2"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}[dry-run]${NC} 将原子部署: $src → $dst"
        return 0
    fi
    local tmp="${dst}.tmp.$$"
    cp "$src" "$tmp" && chmod +x "$tmp" && mv -f "$tmp" "$dst"
}

MODE_DESC="全量安装"
[ "$SKIP_MODELS" = "1" ]  && MODE_DESC="跳过模型下载"
[ "$UPGRADE_ONLY" = "1" ] && MODE_DESC="仅升级脚本 + HUD"
[ "$DRY_RUN" = "1" ]      && MODE_DESC="dry-run（${MODE_DESC}，不写任何文件）"
echo -e "${YELLOW}▶${NC} local-voice-input 安装器 v$VERSION — 模式：${MODE_DESC}"

# ── 1. 环境检查 ──────────────────────────────────────
step "1/8 环境检查"

if [ "$(uname)" != "Darwin" ]; then
    err "本工具仅支持 macOS"
    exit 1
fi
ok "macOS 检测通过"

if ! command -v brew &> /dev/null; then
    err "未检测到 Homebrew，请先安装：https://brew.sh"
    exit 1
fi
ok "Homebrew 已安装"

# ── 2. 安装 CLI 依赖 ─────────────────────────────────
step "2/8 安装 CLI 依赖（sox / jq / whisper-cpp / ollama）"

if [ "$UPGRADE_ONLY" = "1" ]; then
    skip "升级模式：跳过依赖安装"
else
    for pkg in sox jq whisper-cpp ollama; do
        if brew list "$pkg" &> /dev/null; then
            ok "$pkg 已安装"
        else
            warn "安装 $pkg..."
            run brew install "$pkg"
        fi
    done
fi

# ── 3. 安装 Raycast ──────────────────────────────────
step "3/8 安装 Raycast"

if [ "$UPGRADE_ONLY" = "1" ]; then
    skip "升级模式：跳过 Raycast 安装"
elif [ -d "/Applications/Raycast.app" ]; then
    ok "Raycast 已安装"
else
    warn "安装 Raycast..."
    run brew install --cask raycast
fi

# ── 4. 启动 Ollama 并拉模型 ──────────────────────────
step "4/8 启动 Ollama 服务并拉取 ${OLLAMA_MODEL}"

if [ "$UPGRADE_ONLY" = "1" ]; then
    skip "升级模式：跳过 Ollama 启动与模型拉取"
else
    if ! pgrep -x ollama > /dev/null; then
        if [ "$DRY_RUN" = "1" ]; then
            echo -e "${CYAN}[dry-run]${NC} 将启动 Ollama 后台服务"
        else
            warn "启动 Ollama 后台服务..."
            brew services start ollama || ollama serve > /dev/null 2>&1 &
            sleep 3
        fi
    fi

    if [ "$SKIP_MODELS" = "1" ]; then
        skip "跳过 ${OLLAMA_MODEL} 拉取（--skip-models）"
    elif ollama list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
        ok "$OLLAMA_MODEL 已就绪"
    elif [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}[dry-run]${NC} 将拉取 $OLLAMA_MODEL (约 2GB)"
    else
        warn "拉取 $OLLAMA_MODEL (约 2GB)..."
        ollama pull "$OLLAMA_MODEL"
    fi
fi

# ── 5. 下载 Whisper 模型 ─────────────────────────────
step "5/8 下载 Whisper 模型"

if [ "$SKIP_MODELS" = "1" ]; then
    if [ -f "$WHISPER_DIR/$WHISPER_MODEL_NAME" ]; then
        ok "跳过下载（--skip-models）；已存在 $WHISPER_DIR/$WHISPER_MODEL_NAME"
    else
        warn "跳过下载（--skip-models）；⚠️ 模型不在 $WHISPER_DIR/${WHISPER_MODEL_NAME}，请自行拷入"
    fi
elif [ -f "$WHISPER_DIR/$WHISPER_MODEL_NAME" ]; then
    ok "Whisper 模型已存在"
elif [ "$DRY_RUN" = "1" ]; then
    echo -e "${CYAN}[dry-run]${NC} 将下载 Whisper 模型 (~550MB) ← $WHISPER_MODEL_URL"
else
    run mkdir -p "$WHISPER_DIR"
    warn "下载 Whisper 模型 (约 550MB)..."
    curl -L --progress-bar -o "$WHISPER_DIR/${WHISPER_MODEL_NAME}.tmp" "$WHISPER_MODEL_URL"
    mv "$WHISPER_DIR/${WHISPER_MODEL_NAME}.tmp" "$WHISPER_DIR/$WHISPER_MODEL_NAME"
    ok "Whisper 模型下载完成"
fi

# ── 6. 准备 HUD（优先编译，无 swiftc 时下载预编译）─────
# HUD 与脚本部署在所有模式下都执行（升级的核心就是刷新它们）。
step "6/8 准备屏幕中央 HUD"

run mkdir -p "$WHISPER_DIR"
HUD_PATH="$WHISPER_DIR/hud"
if command -v swiftc &> /dev/null; then
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}[dry-run]${NC} 将编译 HUD: ${REPO_DIR}/src/hud.swift → ${HUD_PATH}（原子替换）"
    else
        # 编译到临时文件再 mv（原子）：避免覆盖正在运行的 hud 二进制时报 "text file busy"
        swiftc -O "$REPO_DIR/src/hud.swift" -o "${HUD_PATH}.tmp.$$" && mv -f "${HUD_PATH}.tmp.$$" "$HUD_PATH"
    fi
    ok "HUD 从源码编译完成"
elif [ "$DRY_RUN" = "1" ]; then
    echo -e "${CYAN}[dry-run]${NC} 无 swiftc，将下载预编译 HUD ← $HUD_RELEASE_URL"
else
    warn "未检测到 swiftc，下载 v${VERSION} 预编译版本..."
    if curl -fL --progress-bar -o "${HUD_PATH}.tmp" "$HUD_RELEASE_URL"; then
        mv "${HUD_PATH}.tmp" "$HUD_PATH"
        chmod +x "$HUD_PATH"
        # 清除 Gatekeeper 隔离属性（从网络下载的二进制默认会被拦截）
        xattr -d com.apple.quarantine "$HUD_PATH" 2>/dev/null || true
        ok "HUD 预编译版本下载完成"
    else
        rm -f "${HUD_PATH}.tmp"
        err "HUD 下载失败。请安装 Xcode Command Line Tools 后重试："
        err "    xcode-select --install"
        exit 1
    fi
fi

# ── 7. 部署脚本 ──────────────────────────────────────
step "7/8 部署脚本与配置"

# 原子部署（v1.8.1）：用 mv 改名而非原地 cp，避免覆盖正在运行的 vinput_bg.sh 把那一轮读崩。
install_atomic "$REPO_DIR/bin/vinput.sh" "$WHISPER_DIR/vinput.sh"
install_atomic "$REPO_DIR/bin/vinput_bg.sh" "$WHISPER_DIR/vinput_bg.sh"
install_atomic "$REPO_DIR/bin/vinput" "$WHISPER_DIR/vinput"
ok "vinput.sh / vinput_bg.sh / vinput 部署完成"

run mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/vinput.conf" ]; then
    run cp "$REPO_DIR/config/vinput.conf.example" "$CONFIG_DIR/vinput.conf"
    ok "已写入默认配置 $CONFIG_DIR/vinput.conf"
else
    warn "检测到已有配置，跳过覆盖：$CONFIG_DIR/vinput.conf"
fi
if [ ! -f "$CONFIG_DIR/vinput_hotwords.txt" ]; then
    run cp "$REPO_DIR/config/vinput_hotwords.example.txt" "$CONFIG_DIR/vinput_hotwords.txt"
    ok "已写入默认热词 $CONFIG_DIR/vinput_hotwords.txt"
fi
if [ ! -f "$CONFIG_DIR/vinput_corrections.tsv" ]; then
    run cp "$REPO_DIR/config/vinput_corrections.example.tsv" "$CONFIG_DIR/vinput_corrections.tsv"
    ok "已写入默认纠错表 $CONFIG_DIR/vinput_corrections.tsv"
fi

run mkdir -p "$RAYCAST_DIR"
for rs in voice-input.sh voice-input-raw.sh voice-input-en.sh; do
    run cp "$REPO_DIR/raycast/$rs" "$RAYCAST_DIR/$rs"
    run chmod +x "$RAYCAST_DIR/$rs"
done
ok "Raycast 命令脚本就位"

# ── 8. 预热 ──────────────────────────────────────────
step "8/8 预热 Ollama 模型（让首次使用零冷启动）"

if [ "$SKIP_MODELS" = "1" ]; then
    skip "跳过预热（未下载模型）"
elif [ "$DRY_RUN" = "1" ]; then
    echo -e "${CYAN}[dry-run]${NC} 将向 Ollama 发一次预热请求"
else
    curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$OLLAMA_MODEL\",\"prompt\":\"hi\",\"stream\":false,\"keep_alive\":\"30m\"}" \
        > /dev/null || warn "预热请求失败（Ollama 未就绪？可稍后手动使用，不影响安装）"
    ok "Ollama 已预热"
fi

# ── 完成 ─────────────────────────────────────────────
if [ "$DRY_RUN" = "1" ]; then
    echo
    ok "dry-run 完成：环境检查通过，以上为将要执行的动作，未下载 / 未写入任何文件。"
    exit 0
fi

if [ "$UPGRADE_ONLY" = "1" ]; then
    echo
    ok "升级完成：vinput 脚本与 HUD 已刷新到 v${VERSION}。"
    echo -e "  权限与 Raycast 快捷键沿用原有配置，无需重做。验证：${CYAN}vinput --doctor${NC}"
    exit 0
fi

cat <<'EOF'

═══════════════════════════════════════════════════════════
🎉 安装完成！还差最后 3 步手动配置（无法脚本化）：

1️⃣  授权麦克风（系统设置 → 隐私 → 麦克风）
   - 把 Raycast 打勾
   - sox 首次会自动弹窗，点允许即可

2️⃣  授权辅助功能（系统设置 → 隐私 → 辅助功能）
   - 把 Raycast 打勾（用于自动 ⌘V 粘贴）
   - 没授权也不会卡死：vinput 会提示并自动打开该面板

3️⃣  在 Raycast 里绑定快捷键
   - 打开 Raycast Settings → Extensions → Script Commands
   - 添加目录：~/.config/raycast-scripts
   - "🎙️ 语音输入"        绑 ⌘⇧Space   完整流水线（Whisper + LLM 整形）
   - "📝 语音输入 (Raw)"  绑 ⌥Space     只跑 Whisper，跳过 LLM（短指令 / 原文转写）

完成后，按你设的快捷键即可开始使用！

🛠️  CLI 工具（可选）：
   把下面这行加到 ~/.zshrc 或 ~/.bashrc，就能在终端里跑 vinput 诊断：
       alias vinput="$HOME/.whisper_models/vinput"

   常用命令：
       vinput --doctor    # 一键诊断（工具链 / 资源 / 麦克风测试）
       vinput --version   # 查看版本
═══════════════════════════════════════════════════════════
EOF
