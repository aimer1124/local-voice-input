# 🎙️ local-voice-input — Local AI Voice Prompt Input

[![CI](https://github.com/aimer1124/local-voice-input/actions/workflows/release.yml/badge.svg)](https://github.com/aimer1124/local-voice-input/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/aimer1124/local-voice-input?color=brightgreen)](https://github.com/aimer1124/local-voice-input/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Apple%20Silicon-lightgrey)](#requirements)
[![Roadmap](https://img.shields.io/badge/roadmap-v1.1%20%E2%86%92%20v2.0-blue)](./ROADMAP.md)

> A **fully offline** voice-input tool built for programmers: press a hotkey and speak → Whisper transcribes → a local LLM distills your intent → the result is auto-pasted at your cursor.
>
> _CLI tool name: `vinput`_

**100% local. Audio never leaves your machine. No cloud, no accounts.**

[中文 README](./README.zh.md) · [CHANGELOG](./CHANGELOG.md) · [ROADMAP](./ROADMAP.md) · [Contributing](./CONTRIBUTING.md)

![demo](./assets/demo.gif)

---

## ✨ Features

- 🔒 **Fully offline**: Whisper.cpp + Ollama — audio and text never touch the cloud
- 🧠 **AI intent refinement**: a local LLM strips fillers ("uh", "you know") and compresses rambling into a structured prompt
- ⚡ **Fast**: 10s of audio → text in 2–4s
- 🎛️ **Toggle hotkey**: press once to start, press again to stop — intuitive
- 🖥️ **Multi-monitor HUD**: a frosted-glass overlay near the bottom-center that follows whichever screen your cursor is on
- 🎯 **Technical-term friendly**: a customizable hotword list keeps mixed code/English from derailing recognition
- 🔌 **Zero-config**: Chinese by default, works out of the box; every parameter is also externally configurable

---

## 🎬 Flow

```
Press ⌘⇧Space (Raycast hotkey)
       │
       ▼
┌────────────────────────────┐
│  🎙️ Recording... (HUD)     │  ← Pop sound
└────────────────────────────┘
       │
       │  Speak your command, e.g.:
       │  "write me a Python function that reads a CSV and filters out empty rows"
       │
       ▼
Press ⌘⇧Space again          ← Tink sound
       │
       ▼
┌────────────────────────────┐
│  💭 Transcribing...         │
└────────────────────────────┘
       │  ↓ Whisper.cpp transcribes
┌────────────────────────────┐
│  🤖 Polishing with AI...    │
└────────────────────────────┘
       │  ↓ Ollama (qwen2.5:3b) distills intent
       │  ↓ pbcopy + osascript ⌘V
       ▼
┌────────────────────────────┐
│  ✓ Done                     │
└────────────────────────────┘
       │
       ▼
   The cleaned-up prompt appears at your cursor
```

---

## 🧠 How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Raycast global hotkey                    │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  voice-input.sh (Raycast Script Command)                    │
│     └─ exec vinput_bg.sh                                    │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  vinput_bg.sh (main logic)                                  │
│                                                              │
│   Concurrency lock (atomic mkdir)                            │
│      ├─ First press  → record mode                           │
│      └─ Second press → toggle mode (SIGINT for graceful rec) │
│                                                              │
│   ┌───────┐    ┌──────────┐    ┌────────┐    ┌──────────┐  │
│   │ SoX   │ →  │ Whisper  │ →  │ Ollama │ →  │ pbcopy + │  │
│   │ rec   │    │ -cli     │    │ qwen   │    │ ⌘V       │  │
│   └───┬───┘    └──────────┘    └────────┘    └──────────┘  │
│       │                                                      │
│       │       30s guard process (hard-timeout safety net)    │
│       │                                                      │
│   ┌───▼───┐                                                  │
│   │  HUD  │ ← switches the screen-center overlay per stage  │
│   └───────┘                                                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Mechanisms

#### 1. Dual-mode toggle lock

`/tmp/vinput.lock.d` doubles as a **mutex + state machine**:

| State | mkdir result | PID file | Behavior |
|---|---|---|---|
| Fresh session | succeeds | created | enter record mode, start recording |
| Press again mid-recording | fails | exists | toggle mode, send SIGINT for a graceful rec stop |
| Press again mid-transcription | fails | already removed | shows "still processing the previous recording" |
| Stale lock (crash) | fails | PID is dead | auto-clean, then restart |

`mkdir` is atomic and more portable than `flock` (macOS ships no `flock`).

#### 2. Recording control (USE_VAD dual mode)

**Default USE_VAD=0 (recommended)**:
- `rec` starts capturing the instant you press, regardless of volume
- A second press sends SIGINT for an immediate stop
- 30s hard timeout as a safety net in case you forget to stop

**Optional USE_VAD=1**:
- Adds a SoX silence filter: auto-stops after 1.5s of silence
- Only suitable in quiet environments (ambient noise above the threshold keeps it from stopping)

#### 3. Whisper transcription

- Model: `ggml-large-v3-turbo-q5_0` (547MB, Apple Silicon Metal backend)
- Hotword list injected via `--prompt` to boost technical-term accuracy
- Forced `-l zh` (Chinese) mode; mixed Chinese/English is guided by the prompt

#### 4. LLM intent refinement (short-text skip optimization)

- Shorter than `SHORT_TEXT_THRESHOLD` (15 chars by default) → use the raw text directly, saving 1–2s
- Longer text → call Ollama with `keep_alive=30m` to keep the model resident in memory
- Falls back to the raw Whisper result on failure

**LLM prompt design**:
```
You are a high-efficiency programmer-instruction distiller. Rules:
1. Filter out fillers ("uh", "um", "you know")
2. On mid-sentence self-correction, keep only the final intent
3. Turn speech into a written, hardcore prompt format
4. No explanations or pleasantries — output the final text only
```

#### 5. Screen-center HUD

- ~240 lines of Swift, compiled into a single ~116KB binary
- Uses `NSVisualEffectView` + the `.hudWindow` material, matching the system volume HUD
- Maintains a singleton via `/tmp/vinput_hud.pid`: a new HUD kills the previous one
- Mouse-passthrough, shows across Spaces, auto-fits text width
- Multi-screen aware: uses `NSEvent.mouseLocation` to hit whichever screen the cursor is on

#### 6. UTF-8 encoding handling

Raycast-spawned child processes don't inherit Terminal's LANG, so `pbcopy` treats UTF-8 Chinese bytes as Latin-1 and pastes garbled text. The script forces:
```bash
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
```

---

## 📦 Installation

### Homebrew Tap (recommended · v1.1.1+)

```bash
brew tap aimer1124/tap
brew install local-voice-input
vinput setup
```

`vinput setup` is the second stage of Homebrew's two-step bootstrap — `brew install` only deploys the scripts and the HUD binary into `libexec/`. The following happen inside `vinput setup`:

1. `brew install sox jq whisper-cpp ollama` (skipped if already present)
2. Download the Whisper `large-v3-turbo-q5_0` model (~547MB)
3. Symlink `vinput / vinput.sh / vinput_bg.sh / hud` into `~/.whisper_models/`
4. Write the default config `~/.config/vinput.conf` + hotword list
5. Deploy the Raycast command script to `~/.config/raycast-scripts/`
6. Start the Ollama service, pull `qwen2.5:3b` (~2GB), and pre-warm it

Upgrade with `brew upgrade local-voice-input` (the scripts are symlinks, so they follow the version automatically).

### From source (developers / no brew)

```bash
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

`install.sh` follows the original path: it checks for Homebrew → `brew install` the dependencies → `brew install --cask raycast` → download the Whisper model → compile/download the HUD binary → copy scripts to `~/.whisper_models/` → pre-warm Ollama. It's equivalent to `vinput setup`, just without depending on the brew tap.

It supports a few flags (combinable; run `--help` for the full list):

```bash
./install.sh --dry-run        # only check the environment + print planned actions; download/write nothing
./install.sh --upgrade-only   # refresh only the scripts and HUD, skip deps and models (fastest upgrade)
./install.sh --skip-models    # skip the Whisper (~550MB) + Ollama (~2GB) downloads (copy models via USB on offline machines)
```

### Manual setup (the parts automation can't cover)

After `install.sh` finishes, you still need to do the following in System Settings:

1. **Privacy → Microphone**: enable Raycast (sox prompts automatically on first trigger — click Allow)
2. **Privacy → Accessibility**: enable Raycast (used for the automatic ⌘V paste)
3. **Raycast Settings → Extensions → Script Commands**
   - Add Script Directory: `~/.config/raycast-scripts`
   - Bind a hotkey to the **🎙️ 语音输入** ("Voice Input") command (recommended: `⌘⇧Space`). The Raw and EN commands are optional — see [Modes](#modes-three-raycast-commands) below.

> Skipping step 2 won't break things: without Accessibility permission the transcription still lands on
> the clipboard, and vinput shows "📋 Copied to clipboard · auto-paste needs Accessibility" while
> **opening the relevant Settings panel for you**. Auto-paste resumes once granted; press `⌘V` manually
> until then.

### Requirements

- macOS 13+
- Apple Silicon (M1/M2/M3/M4)
- 16 GB RAM recommended (8 GB also works)
- 3 GB disk space
- A working microphone (**note**: 3-pole TRS music headphones make macOS route input to the dead headphone port)

---

## 🚀 Usage

### Basics

1. Click your cursor into any text field (editor, browser, chat window — all fine)
2. Press your hotkey (e.g., ⌘⇧Space)
3. Speak after the Pop sound
4. Press the hotkey once more when done
5. Wait 2–4s; the text is auto-pasted at the cursor

### Modes (three Raycast commands)

vinput ships three Raycast script commands that share the same pipeline (`vinput_bg.sh`) and differ only in the LLM step. Bind each to its own hotkey:

| Command | Hotkey (suggested) | LLM step | Output |
|---|---|---|---|
| **🎙️ 语音输入** (default) | `⌘⇧Space` | distill Chinese speech into a written Chinese prompt | Chinese (mixed CN/EN) |
| **📝 语音输入 (Raw)** | `⌥Space` | skipped | raw Whisper transcript, as spoken |
| **🌐 语音输入 (EN)** | `⌃⇧Space` | translate + reshape Chinese speech into an English prompt | English |

> EN mode still transcribes your Chinese speech with `-l zh`, then translates and tightens it into a concise English instruction in the LLM step. It **always** runs the LLM (ignores `SHORT_TEXT_THRESHOLD`) — otherwise a short Chinese phrase would come back unchanged in Chinese.

### Performance budget (10s of audio)

| Stage | Time |
|---|---|
| Recording | as long as you speak |
| Whisper transcription | ~2s |
| Ollama refinement | ~1s (short text skips it) / ~2s (long text) |
| Paste | < 0.1s |
| **Total added latency** | **2–4s** |

---

## ⚙️ Configuration

Configuration lives in `~/.config/vinput.conf`. **The design principle is works-out-of-the-box** — the default template only includes the handful of knobs "most people will actually change", all with recommended defaults. Deleting or blanking any one of them falls back to the built-in default without error:

```bash
# === Whisper ASR ===
MODEL_PATH="$HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin"
WHISPER_LANG="zh"              # mixed CN/EN is guided by the hotword prompt

# === Ollama LLM refinement ===
OLLAMA_MODEL="qwen2.5:3b"
OLLAMA_URL="http://localhost:11434"
SHORT_TEXT_THRESHOLD=15        # text shorter than this (CN: 1 char = 1) skips the LLM, saving 1–2s

# === Recording / paste behavior ===
AUTO_PASTE=1                   # 1 = auto ⌘V (needs Accessibility), 0 = copy only
USE_VAD=0                      # 0 = pure toggle (recommended), 1 = auto-stop on silence (quiet rooms only)
MAX_REC_SECONDS=30             # recording hard timeout (seconds)
SOX_GAIN_DB=-3                 # too quiet / far from mic? raise to +6~+12 (negative = attenuate)

# === Hotword list (optional) ===
HOTWORDS_FILE="$HOME/.config/vinput_hotwords.txt"
```

> Want to tune Whisper's internal decoding params, SoX filtering, dynamic prompts, VAD thresholds, etc.? See [Advanced Configuration](#-advanced-configuration) below. These defaults are already tuned for Chinese + programmer workflows and usually don't need touching.

### Hotword list

`~/.config/vinput_hotwords.txt`, one term per line, injected into the Whisper prompt to improve recognition accuracy:

```
API
Promise
async
Playwright
PostgreSQL
...
```

### HUD style adjustments

No recompile needed — set these in `~/.config/vinput.conf` and they take effect on the next trigger:

| Setting | Default | Description |
|---|---|---|
| `HUD_Y_PERCENT` | `18` | Distance from the screen bottom as a percentage (0 = bottom / 50 = center / 100 = top) |
| `HUD_HEIGHT` | `96` | Window height (pixels) |
| `HUD_FONT_SIZE` | `26` | Font size |
| `HUD_FONT_WEIGHT` | `semibold` | `ultraLight`/`thin`/`light`/`regular`/`medium`/`semibold`/`bold`/`heavy`/`black` |
| `HUD_CORNER_RADIUS` | `20` | Corner radius |
| `HUD_MATERIAL` | `hudWindow` | Frosted-glass style: `hudWindow`/`sidebar`/`popover`/`menu`/… (see `NSVisualEffectView.Material`) |
| `HUD_WIDTH_MIN` | `220` | Lower bound for adaptive width |
| `HUD_WIDTH_MAX` | `900` | Upper bound for adaptive width |

One-off overrides are also supported (without touching the config file):
```bash
HUD_Y_PERCENT=50 HUD_FONT_SIZE=36 ~/.whisper_models/hud "test style" 2
```

---

## 🧩 Advanced Configuration

These are **not in the default config template**, because the defaults are already tuned for Chinese + programmer workflows and the vast majority of people won't touch them.
Add them to `~/.config/vinput.conf` by hand when needed (blank = built-in default, no error). After changing any Whisper/LLM-related setting, run the [Regression Tests](#-regression-tests-must-run-before-tagging) once before relying on it.

### Whisper decoding internals

```bash
WHISPER_THREADS=8             # inference threads
WHISPER_BEAM_SIZE=5           # beam-search width, reduces homophone misses; +0.5s latency
WHISPER_TEMPERATURE_INC=0.2   # temperature increment step, a sampling fallback against empty output on failure
# WHISPER_TEMPERATURE=0       # starting temperature; blank = whisper.cpp default
# WHISPER_NO_SPEECH_THOLD=0.6 # lower = stricter. ⚠️ v1.1.3's stricter value judged ordinary mics as "non-speech"; v1.1.6 reverted to default (blank)
# WHISPER_LOGPROB_THOLD=-1.0  # closer to 0 = stricter. Same story; only consider it if doctor reports a weak signal
```

### Dynamic prompt context

Prepends the last N successful transcriptions to Whisper's `--prompt` to give the model "short-term memory". In practice, proper-noun hit rate is +20~40% when chatting about the same topic in a row.

```bash
USE_RECENT_PROMPT=1
RECENT_PROMPT_COUNT=5
RECENT_PROMPT_FILE="$HOME/.cache/vinput/recent.txt"
RECENT_PROMPT_MAX_CHARS=280
```

### SoX recording preprocessing

> ⚠️ Every effect must be streaming-safe (cannot depend on a full-rectification buffer). v1.1.4 used `norm -3`, which made rec output 0 frames on SIGINT → "no valid speech detected". v1.1.7 reverted to a fixed gain.

```bash
USE_SOX_PREPROCESS=1
SOX_HIGHPASS=80     # cut low frequencies: fan / street rumble
SOX_LOWPASS=8000    # cut high frequencies: hiss / jitter
SOX_GAIN_DB=-3      # fixed gain (already in the basic config; listed here for completeness)
REC_WARMUP_MS=150   # wait for rec's buffer to be ready before prompting you to speak, avoiding a dropped first word
```

### VAD thresholds (only when `USE_VAD=1`)

```bash
SILENCE_TAIL=1.5
SILENCE_START_THRESHOLD="0.5%"
SILENCE_STOP_THRESHOLD="6%"
```

### HUD final state & ↑ re-record

```bash
# HUD_SHOW_RESULT=1       # after pasting, the HUD shows what was actually pasted (truncated to 60 chars)
# HUD_FINAL_DURATION=2.5  # how many seconds the final state lingers
# HUD_RERUN_ON_UP=0       # 1 = press ↑ during the final state to instantly re-run the full pipeline (ESC always closes immediately)
```

> `HUD_RERUN_ON_UP=1` requires checking the hud binary (path via `vinput --doctor`) in **System Settings → Privacy → Input Monitoring**.
> Without permission the HUD still displays fine, ↑ just does nothing — it's a convenience feature, off by default.

HUD appearance (8 knobs: position/font/material/etc.) is covered in [HUD style adjustments](#hud-style-adjustments) above.

---

## 🗂️ Project Structure

```
vinput/
├── README.md                          # this document (English, default)
├── README.zh.md                       # Chinese version
├── LICENSE                            # MIT
├── install.sh                         # one-shot install
├── uninstall.sh                       # uninstall
├── bin/
│   ├── vinput.sh                      # foreground manual version (terminal Ctrl+C)
│   └── vinput_bg.sh                   # background version (called by Raycast)
├── raycast/
│   └── voice-input.sh                 # Raycast command wrapper
├── src/
│   └── hud.swift                      # screen-center HUD source
├── config/
│   ├── vinput.conf.example            # config template
│   └── vinput_hotwords.example.txt    # hotword template
└── assets/                            # screenshots / demo assets
```

---

## 🆚 vs Commercial IMEs

| Dimension | vinput | WeChat / iFlytek / Doubao |
|---|---|---|
| Privacy | ✅ 100% local | ❌ Uploaded to the cloud |
| Works offline | ✅ | ❌ |
| Technical terms | ✅ Custom hotwords + LLM refinement | ⚠️ Generic vocabulary |
| Intent refinement | ✅ AI distills into a prompt | ❌ Transcription only |
| Streaming output | ❌ Must finish recording first | ✅ Text as you speak |
| Direct insertion anywhere | ⚠️ Relayed via clipboard | ✅ System-level IME |
| Candidates / correction | ❌ | ✅ |
| Dialect support | ⚠️ Mandarin only | ✅ Dozens of dialects |

**Best positioning**: treat vinput as an **"AI prompt dictation button"** that divides labor with your system IME — vinput for long prompts to Claude/Cursor/ChatGPT, the system IME for chat/passwords/short replies.

---

## 🔧 Troubleshooting

**One-shot diagnosis** (run this first):
```bash
~/.whisper_models/vinput --doctor
```
It checks the toolchain, resource files, Ollama status, and HUD availability, then runs a 3-second mic recording test and reports the RMS value as "healthy / weak / nearly silent".

| Symptom | Command / action |
|---|---|
| Raycast does nothing | Check the command appears and the hotkey isn't conflicting |
| Copied but didn't auto-paste | System Settings → Privacy → Accessibility, enable Raycast (vinput prompts and opens the panel for you) |
| Recording failed | `tail -50 /tmp/vinput_debug.log` |
| Not sure where it broke | `~/.whisper_models/vinput --doctor` |
| Mic level test | `rec -q /tmp/t.wav trim 0 3 && sox /tmp/t.wav -n stat \| grep RMS` |
| Default input device | System Settings → Sound → Input (use MacBook Pro Microphone) |
| Stuck recording | `pkill -f "rec -q"; rm -rf /tmp/vinput.lock.d` |
| Ollama not running | `brew services start ollama` |
| HUD not showing | `~/.whisper_models/hud "test" 2` |
| Garbled Chinese | Confirm the script contains `export LANG="en_US.UTF-8"` |

---

## 📚 Going Further

### Switch to a faster Whisper model

| Model | Size | Speed | Chinese quality |
|---|---|---|---|
| `ggml-tiny.bin` | 75 MB | blazing | poor |
| `ggml-base.bin` | 142 MB | fast | so-so |
| `ggml-small.bin` | 466 MB | medium | medium |
| **`ggml-large-v3-turbo-q5_0.bin`** | **547 MB** | **fast** | **strongly recommended** |
| `ggml-large-v3.bin` | 3 GB | slow | highest |

### Switch to a faster Ollama model

| Model | Speed | Refinement quality |
|---|---|---|
| `qwen2.5:1.5b` | ⚡⚡⚡ | so-so |
| **`qwen2.5:3b`** | **⚡⚡** | **balanced (recommended)** |
| `qwen2.5:7b` | ⚡ | stronger |
| `gemma2:2b` | ⚡⚡⚡ | alternative choice |

```bash
ollama pull qwen2.5:1.5b
# then set OLLAMA_MODEL="qwen2.5:1.5b" in ~/.config/vinput.conf
```

---

## 📜 Transcription History & Mistake Mining

Every successful transcription is appended to `~/.cache/vinput/history.jsonl` (fully local, plain text).

```bash
vinput history                  # last 20 entries as a colored table
vinput history --tail 100       # last 100 entries
vinput history --grep qwen      # search (across the raw/corrected/cleaned columns)
vinput history --raw-only       # raw Whisper output only (handy for grepping mistakes)
```

Once you spot a mistake, add it to the correction table with one command:

```bash
vinput add-correction "Claude Code" "克劳德 code"
```

> Privacy: the log stays local and never leaves the machine. To wipe it: `rm ~/.cache/vinput/history.jsonl`.

---

## 🧪 Regression Tests (must run before tagging)

A three-layer ASR pipeline = three test suites + one lint:

| Layer | Suite | Command | Value |
|---|---|---|---|
| Whisper transcription | [`tests/asr/`](./tests/asr/) | `bash tests/asr/run.sh` | 6 TTS clips + a CER budget |
| Homophone correction | (data-driven, no test needed) | `vinput corrections` | the TSV is the ground truth |
| LLM shaping | [`tests/llm/`](./tests/llm/) | `bash tests/llm/run.sh` | 6 cases + must-contain / must-not-contain constraints |
| Defensive | `scripts/lint-shell.sh` | `bash scripts/lint-shell.sh` | greps `$VAR<non-ASCII>` set -u traps |

Before modifying `bin/vinput_bg.sh`, the Whisper/LLM params, or `config/*`, you **must run** the corresponding layer. Only an exit code of 0 clears it for tagging.

> Why: the four hotfixes from v1.1.3 → v1.1.7 were all "changed an ASR param without a regression". v1.1.5 / v1.1.8 were the `set -u` Chinese-parenthesis trap. This harness blocks both bug classes outright.

## 🤝 Contributing

PRs / issues welcome. Suggested directions:
- Contribute samples to the regression suite [tests/asr/](./tests/asr/) (real recordings, dialects, noisy scenarios)
- Linux/Windows ports (replace Raycast, osascript, the HUD)
- Streaming recognition (whisper-streaming / faster-whisper)
- Clipboard-free direct injection (type Unicode via CGEventPost)
- More language/dialect model presets

---

## 📄 License

MIT — see [LICENSE](./LICENSE)

---

## 🙏 Acknowledgements

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — local Whisper inference
- [Ollama](https://ollama.com/) — local LLM engine
- [Qwen](https://github.com/QwenLM/Qwen) — Alibaba's open-source LLM
- [Raycast](https://www.raycast.com/) — modern macOS launcher
- [SoX](http://sox.sourceforge.net/) — audio recording toolchain
