#!/bin/bash
# local-voice-input 一键安装脚本（部署的 CLI 工具名为 vinput）
# 用法: ./install.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$HOME/.whisper_models"
CONFIG_DIR="$HOME/.config"
RAYCAST_DIR="$HOME/.config/raycast-scripts"

WHISPER_MODEL_NAME="ggml-large-v3-turbo-q5_0.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${WHISPER_MODEL_NAME}"
OLLAMA_MODEL="qwen2.5:3b"

# ── 颜色输出 ─────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*"; }
step() { echo -e "\n${YELLOW}▶${NC} $*"; }

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

for pkg in sox jq whisper-cpp ollama; do
    if brew list "$pkg" &> /dev/null; then
        ok "$pkg 已安装"
    else
        warn "安装 $pkg..."
        brew install "$pkg"
    fi
done

# ── 3. 安装 Raycast ──────────────────────────────────
step "3/8 安装 Raycast"

if [ -d "/Applications/Raycast.app" ]; then
    ok "Raycast 已安装"
else
    warn "安装 Raycast..."
    brew install --cask raycast
fi

# ── 4. 启动 Ollama 并拉模型 ──────────────────────────
step "4/8 启动 Ollama 服务并拉取 ${OLLAMA_MODEL}"

if ! pgrep -x ollama > /dev/null; then
    warn "启动 Ollama 后台服务..."
    brew services start ollama || ollama serve > /dev/null 2>&1 &
    sleep 3
fi

if ollama list | grep -q "$OLLAMA_MODEL"; then
    ok "$OLLAMA_MODEL 已就绪"
else
    warn "拉取 $OLLAMA_MODEL (约 2GB)..."
    ollama pull "$OLLAMA_MODEL"
fi

# ── 5. 下载 Whisper 模型 ─────────────────────────────
step "5/8 下载 Whisper 模型"

mkdir -p "$WHISPER_DIR"
if [ -f "$WHISPER_DIR/$WHISPER_MODEL_NAME" ]; then
    ok "Whisper 模型已存在"
else
    warn "下载 Whisper 模型 (约 550MB)..."
    curl -L --progress-bar -o "$WHISPER_DIR/${WHISPER_MODEL_NAME}.tmp" "$WHISPER_MODEL_URL"
    mv "$WHISPER_DIR/${WHISPER_MODEL_NAME}.tmp" "$WHISPER_DIR/$WHISPER_MODEL_NAME"
    ok "Whisper 模型下载完成"
fi

# ── 6. 编译 HUD ──────────────────────────────────────
step "6/8 编译屏幕中央 HUD"

if ! command -v swiftc &> /dev/null; then
    err "未检测到 swiftc，请运行 xcode-select --install 后重试"
    exit 1
fi
swiftc -O "$REPO_DIR/src/hud.swift" -o "$WHISPER_DIR/hud"
ok "HUD 编译完成"

# ── 7. 部署脚本 ──────────────────────────────────────
step "7/8 部署脚本与配置"

cp "$REPO_DIR/bin/vinput.sh" "$WHISPER_DIR/vinput.sh"
cp "$REPO_DIR/bin/vinput_bg.sh" "$WHISPER_DIR/vinput_bg.sh"
chmod +x "$WHISPER_DIR/vinput.sh" "$WHISPER_DIR/vinput_bg.sh"
ok "vinput.sh / vinput_bg.sh 部署完成"

mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/vinput.conf" ]; then
    cp "$REPO_DIR/config/vinput.conf.example" "$CONFIG_DIR/vinput.conf"
    ok "已写入默认配置 $CONFIG_DIR/vinput.conf"
else
    warn "检测到已有配置，跳过覆盖：$CONFIG_DIR/vinput.conf"
fi
if [ ! -f "$CONFIG_DIR/vinput_hotwords.txt" ]; then
    cp "$REPO_DIR/config/vinput_hotwords.example.txt" "$CONFIG_DIR/vinput_hotwords.txt"
    ok "已写入默认热词 $CONFIG_DIR/vinput_hotwords.txt"
fi

mkdir -p "$RAYCAST_DIR"
cp "$REPO_DIR/raycast/voice-input.sh" "$RAYCAST_DIR/voice-input.sh"
chmod +x "$RAYCAST_DIR/voice-input.sh"
ok "Raycast 命令脚本就位"

# ── 8. 预热 ──────────────────────────────────────────
step "8/8 预热 Ollama 模型（让首次使用零冷启动）"

curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$OLLAMA_MODEL\",\"prompt\":\"hi\",\"stream\":false,\"keep_alive\":\"30m\"}" \
    > /dev/null
ok "Ollama 已预热"

# ── 完成 ─────────────────────────────────────────────
cat <<'EOF'

═══════════════════════════════════════════════════════════
🎉 安装完成！还差最后 3 步手动配置（无法脚本化）：

1️⃣  授权麦克风（系统设置 → 隐私 → 麦克风）
   - 把 Raycast 打勾
   - sox 首次会自动弹窗，点允许即可

2️⃣  授权辅助功能（系统设置 → 隐私 → 辅助功能）
   - 把 Raycast 打勾（用于自动 ⌘V 粘贴）

3️⃣  在 Raycast 里绑定快捷键
   - 打开 Raycast Settings → Extensions → Script Commands
   - 添加目录：~/.config/raycast-scripts
   - 给 "🎙️ 语音输入" 命令绑快捷键（推荐 ⌘⇧Space）

完成后，按你设的快捷键即可开始使用！
═══════════════════════════════════════════════════════════
EOF
