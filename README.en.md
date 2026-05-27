# 🎙️ local-voice-input — Local AI Voice Prompt Input

[![CI](https://github.com/aimer1124/local-voice-input/actions/workflows/release.yml/badge.svg)](https://github.com/aimer1124/local-voice-input/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/aimer1124/local-voice-input?color=brightgreen)](https://github.com/aimer1124/local-voice-input/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Apple%20Silicon-lightgrey)](#requirements)
[![Roadmap](https://img.shields.io/badge/roadmap-v1.1%20%E2%86%92%20v2.0-blue)](./ROADMAP.md)

> **Fully offline** voice-to-text tool for programmers: press a hotkey, speak, get cleaned-up text pasted at your cursor.
>
> _CLI tool name: `vinput`_

**100% local. Audio never leaves your machine. No cloud, no accounts.**

[中文 README](./README.md) · [CHANGELOG](./CHANGELOG.md) · [ROADMAP](./ROADMAP.md) · [Contributing](./CONTRIBUTING.md)

![demo](./assets/demo.gif)

---

## ✨ Features

- 🔒 **Fully offline**: Whisper.cpp + Ollama, your voice stays on-device
- 🧠 **AI intent refinement**: local LLM filters fillers and self-corrections, turns rambling into a structured prompt
- ⚡ **Fast**: 10s of Chinese audio → text in 2–4s
- 🎛️ **Toggle hotkey**: press to start, press again to stop — intuitive
- 🖥️ **Multi-monitor HUD**: frosted-glass overlay near the bottom-center of whichever screen your cursor is on
- 🎯 **Hotword-aware**: customizable hotwords boost recognition for technical terms
- 🔌 **Zero-config**: works out of the box; every knob is configurable

---

## 🎬 Flow

```
Press ⌘⇧Space (Raycast hotkey)
        │
        ▼
┌────────────────────────────┐
│  🎙️ Recording...          │  ← Pop sound
└────────────────────────────┘
        │  Speak your prompt
        ▼
Press ⌘⇧Space again         ← Tink sound
        │
        ▼
┌────────────────────────────┐
│  💭 Transcribing...        │
└────────────────────────────┘
        │  ↓ Whisper.cpp
┌────────────────────────────┐
│  🤖 Polishing with AI...   │
└────────────────────────────┘
        │  ↓ Ollama (qwen2.5:3b)
        │  ↓ pbcopy + ⌘V
        ▼
┌────────────────────────────┐
│  ✓ Done                    │
└────────────────────────────┘
        │
        ▼
   Cleaned text appears at cursor
```

---

## 🧠 How It Works

### Architecture

```
Raycast Global Hotkey
    └─ voice-input.sh (Raycast Script Command)
         └─ vinput_bg.sh (main logic)
              │
              ├─ Lock dir (atomic mkdir) = mutex + state machine
              │     ├─ First press → record mode
              │     └─ Second press → toggle mode (SIGINT to rec)
              │
              ├─ SoX rec → Whisper-cli → Ollama → pbcopy + ⌘V
              │
              ├─ 30s guard timeout (safety)
              │
              └─ HUD (Swift binary) → screen-center overlay
```

### Key Mechanisms

#### Toggle Lock (mkdir + PID file)

`/tmp/vinput.lock.d` doubles as a mutex AND state machine:

| State | mkdir | PID file | Behavior |
|---|---|---|---|
| Fresh session | succeeds | created | enter record mode |
| Mid-recording press | fails | exists | toggle mode, SIGINT to rec |
| Mid-transcription press | fails | gone | "still processing previous" HUD |
| Stale lock (crash) | fails | dead PID | auto-clean, restart |

`mkdir` is atomic and portable (macOS has no `flock`).

#### Recording Control (USE_VAD)

**Default USE_VAD=0** (recommended):
- `rec` starts capturing immediately regardless of volume
- Second hotkey press → instant SIGINT stop
- 30s hard timeout as safety net

**Optional USE_VAD=1**:
- SoX silence filter: stop after 1.5s of silence
- Only works in quiet environments

#### Whisper Transcription

- Model: `ggml-large-v3-turbo-q5_0` (547MB, Metal backend)
- Hotwords injected via `--prompt` for better technical term recognition
- Forced `-l zh` for Chinese, English terms guided by prompt

#### LLM Refinement (with short-text skip)

- Text shorter than `SHORT_TEXT_THRESHOLD` (15 chars default) → skip LLM, save 1–2s
- Longer text → Ollama with `keep_alive=30m` for warm model
- Fallback to raw Whisper output on failure

#### Screen HUD

- ~90 lines of Swift compiled to 92KB binary
- `NSVisualEffectView` with `.hudWindow` material (matches system volume HUD)
- `/tmp/vinput_hud.pid` for singleton pattern: new HUD kills previous
- Mouse-passthrough, cross-Space, auto-width
- Multi-screen aware via `NSEvent.mouseLocation`

#### UTF-8 Encoding

Raycast-spawned processes don't inherit Terminal's LANG, causing `pbcopy` to misinterpret UTF-8 bytes. Script forces:
```bash
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
```

---

## 📦 Installation

### One-line install

```bash
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

The installer handles:
1. Homebrew check
2. `brew install sox jq whisper-cpp ollama`
3. `brew install --cask raycast`
4. Start Ollama + pull `qwen2.5:3b` (~2GB)
5. Download Whisper `large-v3-turbo-q5_0` (~547MB)
6. Compile Swift HUD
7. Deploy scripts to `~/.whisper_models/`, config to `~/.config/`
8. Pre-warm Ollama

### Manual steps (cannot be automated)

1. **Privacy → Microphone**: enable Raycast (sox will prompt on first use)
2. **Privacy → Accessibility**: enable Raycast (for auto ⌘V paste)
3. **Raycast Settings → Extensions → Script Commands**:
   - Add Script Directory: `~/.config/raycast-scripts`
   - Bind a hotkey to `🎙️ 语音输入` (recommended: `⌘⇧Space`)

### Requirements

- macOS 13+
- Apple Silicon (M1/M2/M3/M4)
- 16GB RAM recommended (8GB works)
- 3GB disk space
- A working microphone (⚠️ 3-pole TRS music headphones may route input to a phantom port)

---

## 🚀 Usage

1. Click into any text field
2. Press your hotkey (e.g., ⌘⇧Space)
3. Speak after the Pop sound
4. Press the hotkey again to stop
5. Wait 2–4s — text appears at cursor

### Performance budget (10s Chinese audio)

| Stage | Time |
|---|---|
| Recording | however long you speak |
| Whisper | ~2s |
| Ollama | ~1s (short skip) / ~2s (long) |
| Paste | <0.1s |
| **Overhead** | **2–4s** |

---

## ⚙️ Configuration

All settings live in `~/.config/vinput.conf`:

```bash
# Whisper ASR
MODEL_PATH="$HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin"
WHISPER_LANG="zh"
WHISPER_THREADS=8

# Ollama
OLLAMA_MODEL="qwen2.5:3b"
SHORT_TEXT_THRESHOLD=15

# Behavior
AUTO_PASTE=1
USE_VAD=0
MAX_REC_SECONDS=30
```

Hotwords go in `~/.config/vinput_hotwords.txt` (one per line).

---

## 🆚 vs Commercial IMEs

| | vinput | Commercial IMEs |
|---|---|---|
| Privacy | ✅ Fully local | ❌ Cloud |
| Offline | ✅ | ❌ |
| Technical terms | ✅ Custom hotwords + LLM | ⚠️ Generic |
| Intent refinement | ✅ AI prompt distillation | ❌ Transcription only |
| Streaming output | ❌ Wait until done | ✅ Real-time |
| Direct insertion | ⚠️ via clipboard | ✅ System IME |
| Dialects | ⚠️ Mandarin only | ✅ Many |

**Best positioning**: use vinput as an **"AI Prompt dictation button"** alongside your system IME — vinput for long prompts to Claude/Cursor/ChatGPT, system IME for chat/passwords/short replies.

---

## 📄 License

MIT — see [LICENSE](./LICENSE)

---

## 🙏 Acknowledgements

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [Ollama](https://ollama.com/)
- [Qwen](https://github.com/QwenLM/Qwen)
- [Raycast](https://www.raycast.com/)
- [SoX](http://sox.sourceforge.net/)
