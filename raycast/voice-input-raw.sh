#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 语音输入 (Raw)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝
# @raycast.packageName Voice Input
# @raycast.description 本地 Whisper 语音转写（跳过 LLM 整形 — 适合短指令 / 转写原文 / 需要保留口语原貌的场景）
# @raycast.author Jackson

# #22 Raw mode：与默认 voice-input.sh 共用 vinput_bg.sh，靠 VINPUT_RAW=1 跳过 LLM 整形。
# 推荐快捷键：⌥+Space（与默认 ⌘⇧Space 区分）。

export VINPUT_RAW=1
exec "$HOME/.whisper_models/vinput_bg.sh"
