#!/bin/bash
# vinput 卸载脚本
# 用法: ./uninstall.sh

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

read -p "确认要卸载 vinput 吗？(y/N) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

echo -e "${YELLOW}▶${NC} 停止并清理..."

pkill -f vinput_bg.sh 2>/dev/null || true
pkill -f "rec -q" 2>/dev/null || true
rm -rf /tmp/vinput.lock.d /tmp/vinput_hud.pid /tmp/vinput_debug.log* /tmp/voice_input.*

echo -e "${YELLOW}▶${NC} 删除脚本与 HUD..."
rm -f \
    "$HOME/.whisper_models/vinput.sh" \
    "$HOME/.whisper_models/vinput_bg.sh" \
    "$HOME/.whisper_models/hud" \
    "$HOME/.config/raycast-scripts/voice-input.sh"

echo -e "${YELLOW}▶${NC} 配置文件保留（如需删除请手动操作）："
echo "    ~/.config/vinput.conf"
echo "    ~/.config/vinput_hotwords.txt"

echo -e "${YELLOW}▶${NC} Whisper 模型保留（如需删除）："
echo "    ~/.whisper_models/*.bin"

echo -e "${YELLOW}▶${NC} 系统依赖保留（如需删除）："
echo "    brew uninstall sox jq whisper-cpp ollama"
echo "    brew uninstall --cask raycast"

echo -e "${GREEN}✓${NC} 卸载完成"
