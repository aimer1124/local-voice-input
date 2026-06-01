#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 语音输入 (EN)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🌐
# @raycast.packageName Voice Input
# @raycast.description 说中文、出英文：本地 Whisper 转写中文，再由 Ollama 翻译整形成简洁的英文书面指令并粘贴到光标
# @raycast.author Jackson

# EN mode：与默认 voice-input.sh 共用 vinput_bg.sh，靠 VINPUT_TRANSLATE_EN=1
# 把 LLM 整形换成「中文口语 → 英文书面指令」。ASR 仍按中文转写。
# 推荐快捷键：⌃⇧Space（与默认 ⌘⇧Space、Raw ⌥Space 区分）。

export VINPUT_TRANSLATE_EN=1
exec "$HOME/.whisper_models/vinput_bg.sh"
