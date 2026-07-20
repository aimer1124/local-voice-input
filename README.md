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

1. Press your hotkey (e.g. `⌘⇧Space`) → Pop sound → 🎙️ Recording
2. Speak your command, e.g. *"write me a Python function that reads a CSV and filters out empty rows"*
3. Press the hotkey again → Tink sound → 💭 Transcribing → 🤖 Polishing with AI
4. ✓ Done — the cleaned-up prompt appears at your cursor

See it live in the demo GIF above.

---

## 🧠 How It Works

`voice-input.sh` (Raycast) execs `vinput_bg.sh`, the main logic: an atomic-`mkdir` lock drives a
record/toggle state machine, then chains **SoX `rec` → `whisper-cli` → Ollama (qwen) → `pbcopy` + ⌘V**,
guarded by a 45s hard-timeout process, with a Swift HUD switching per stage.

Full pipeline diagram, the toggle-lock state machine, `USE_VAD` modes, the LLM prompt design, and
the UTF-8 handling gotcha are documented in **[docs/architecture.md](./docs/architecture.md)**.

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
6. Start the Ollama service, pull `qwen3:4b-instruct` (~2.5GB), and pre-warm it

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
OLLAMA_MODEL="qwen3:4b-instruct"
OLLAMA_URL="http://localhost:11434"
OLLAMA_TIMEOUT=15              # LLM call timeout (s); on timeout, paste raw transcript instead of hanging. Raise on slow cold-loads
OLLAMA_WARMUP=1               # 1 = preload the model in the background when recording starts, so the LLM step is warm by the time transcription finishes (kills the "can't re-record for ~15s after the first take" stall). 0 to disable
SHORT_TEXT_THRESHOLD=15        # text shorter than this (CN: 1 char = 1) skips the LLM, saving 1–2s

# === Recording / paste behavior ===
AUTO_PASTE=1                   # 1 = auto ⌘V (needs Accessibility), 0 = copy only
USE_VAD=0                      # 0 = pure toggle (recommended), 1 = auto-stop on silence (quiet rooms only)
MAX_REC_SECONDS=45             # recording hard timeout (seconds)
STOP_KILL_GRACE=3              # on STOP, force-kill rec after N s if it ignores SIGINT (wedged audio device)
DOUBLE_FIRE_GRACE=0.7          # ignore a stop that lands within N s of record start (Raycast double-fire guard)
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

Not in the default config template — these knobs (Whisper decoding internals, LLM long-content
reshaping, dynamic prompt context, SoX preprocessing, VAD thresholds, HUD final-state/re-record,
per-app mode override, clipboard restore, lock-timing diagnostics) are already tuned for Chinese +
programmer workflows, and most people never touch them. Add any of them to `~/.config/vinput.conf`
by hand when needed — blank = built-in default, no error.

Full reference: **[docs/configuration-advanced.md](./docs/configuration-advanced.md)**. After
changing any Whisper/LLM-related setting, run the [Regression Tests](#-regression-tests-must-run-before-tagging)
once before relying on it.

---

## 🗂️ Project Structure

This project has three layers; the installed runtime directory is not the
source repository:

- **Source repo**: `local-voice-input` (this repo), containing scripts, HUD
  source, Raycast templates, config templates, tests, and release notes.
- **Homebrew tap repo**: `homebrew-tap`, containing only
  `Formula/local-voice-input.rb`, which points at a GitHub tag tarball and the
  release `hud` binary.
- **Local runtime directory**: `~/.whisper_models`, containing Whisper models
  and runtime symlinks. `vinput setup` links `vinput`, `vinput_bg.sh`, and
  `hud` here; do not maintain source copies in this directory.

```
vinput/
├── README.md                          # this document (English, default)
├── README.zh.md                       # Chinese version
├── LICENSE                            # MIT
├── install.sh                         # one-shot install
├── uninstall.sh                       # uninstall
├── bin/
│   ├── vinput                         # CLI: setup / doctor / history / corrections
│   ├── vinput.sh                      # foreground manual version (terminal Ctrl+C)
│   └── vinput_bg.sh                   # background version (called by Raycast)
├── raycast/
│   ├── voice-input.sh                 # full pipeline
│   ├── voice-input-raw.sh             # skip the LLM step
│   └── voice-input-en.sh              # Chinese dictation → English prompt
├── src/
│   └── hud.swift                      # screen-center HUD source
├── docs/
│   ├── architecture.md                # pipeline + internals deep dive
│   └── configuration-advanced.md      # full advanced-config knob reference
├── config/
│   ├── vinput.conf.example            # config template
│   ├── vinput_hotwords.example.txt    # hotword template
│   └── vinput_corrections.example.tsv # correction table template
├── tests/
│   ├── integration/                   # no-mic/no-network CLI integration tests
│   ├── llm/                           # Ollama prompt-cleaning regression tests
│   └── asr/                           # Whisper audio-sample regression tests
├── scripts/
│   ├── lint-shell.sh                  # shell compatibility lint
│   ├── preflight.sh                   # deterministic pre-release checks
│   └── release.sh                     # release/tap coordination helper
└── assets/                            # screenshots / demo assets
```

Before releasing, run:

```bash
bash scripts/preflight.sh
```

To include local LLM/ASR regression suites:

```bash
RUN_LLM=1 RUN_ASR=1 bash scripts/preflight.sh
```

Use `scripts/release.sh --version X.Y.Z` to validate the source release flow,
then `--apply --source-sha ... --hud-sha ...` to update the Homebrew tap formula.

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
It checks effective config, runtime layout, Raycast command entrypoints, the toolchain, resource files, Ollama status, and HUD availability, then runs a 3-second mic recording test and reports the RMS value as "healthy / weak / nearly silent".

To inspect config and entrypoint structure without touching Ollama or the microphone:

```bash
~/.whisper_models/vinput --doctor --quick
~/.whisper_models/vinput config
```

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
| Result never pastes / hangs after speaking | The LLM step waits on Ollama. It now times out after `OLLAMA_TIMEOUT` (default 15s) and pastes the **raw transcript** instead of hanging. If you hit the timeout often, check Ollama with `ollama ps` / `ollama run qwen2.5:3b hi`; a broken Homebrew Ollama (missing `llama-server` backend) makes every request hang — pin a known-good version (`brew pin ollama`). Raise `OLLAMA_TIMEOUT` on slow machines. |
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
| `qwen3:1.7b` | ⚡⚡⚡ | so-so (measured: occasionally drops words, 6/7 on the faithfulness suite) |
| **`qwen3:4b-instruct`** | **⚡⚡** | **balanced (recommended, default since v1.11.0; 7/7 faithfulness)** |
| `qwen2.5:3b` | ⚡⚡ | previous default (≤ v1.10), works as a fallback |
| `qwen3:8b` | ⚡ | stronger (untested) |

> ⚠️ For qwen3, use the **`-instruct`** variants. Bare `qwen3:4b` is the thinking build — it
> reasons at length before answering and blows straight through the hot-path timeout in our
> measurements. The pipeline passes `think:false` on every call, but thinking-only builds
> ignore it.

```bash
ollama pull qwen3:1.7b
# then set OLLAMA_MODEL="qwen3:1.7b" in ~/.config/vinput.conf
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

Or let the history mine candidates for you — high-frequency English words that keep showing up but aren't in your table yet, plus which existing rules actually earn their keep (and which never fire and can be pruned):

```bash
vinput corrections --suggest           # scan all history
vinput corrections --suggest --tail 200  # only the last 200 entries
```

It only suggests; you review and confirm with `vinput add-correction`.

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
