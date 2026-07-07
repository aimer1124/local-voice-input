#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 语音输入
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎙️
# @raycast.packageName Voice Input
# @raycast.description 本地 AI 语音转写并粘贴到光标（Whisper + Ollama qwen3）
# @raycast.author Jackson

exec "$HOME/.whisper_models/vinput_bg.sh"
