# Architecture & Internals

> [中文](./architecture.zh.md) · back to [README](../README.md#-how-it-works)

Deep dive into the pipeline and the mechanisms behind it. Most users never need this —
it exists for contributors and for understanding *why* a given behavior happens.

## Pipeline

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
│       │       45s guard process (hard-timeout safety net)    │
│       │                                                      │
│   ┌───▼───┐                                                  │
│   │  HUD  │ ← switches the screen-center overlay per stage  │
│   └───────┘                                                  │
└─────────────────────────────────────────────────────────────┘
```

## Key Mechanisms

### 1. Dual-mode toggle lock

`/tmp/vinput.lock.d` doubles as a **mutex + state machine**:

| State | mkdir result | PID file | Behavior |
|---|---|---|---|
| Fresh session | succeeds | created | enter record mode, start recording |
| Press again mid-recording | fails | exists | toggle mode, send SIGINT for a graceful rec stop |
| Press again mid-transcription | fails | already removed | shows "still processing the previous recording" |
| Stale lock (crash) | fails | PID is dead | auto-clean, then restart |

`mkdir` is atomic and more portable than `flock` (macOS ships no `flock`).

### 2. Recording control (USE_VAD dual mode)

**Default USE_VAD=0 (recommended)**:
- `rec` starts capturing the instant you press, regardless of volume
- A second press sends SIGINT for an immediate stop
- 45s hard timeout as a safety net in case you forget to stop

**Optional USE_VAD=1**:
- Adds a SoX silence filter: auto-stops after 1.5s of silence
- Only suitable in quiet environments (ambient noise above the threshold keeps it from stopping)

### 3. Whisper transcription

- Model: `ggml-large-v3-turbo-q5_0` (547MB, Apple Silicon Metal backend)
- Hotword list injected via `--prompt` to boost technical-term accuracy
- Forced `-l zh` (Chinese) mode; mixed Chinese/English is guided by the prompt

### 4. LLM intent refinement (short-text skip optimization)

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

### 5. Screen-center HUD

- ~240 lines of Swift, compiled into a single ~116KB binary
- Uses `NSVisualEffectView` + the `.hudWindow` material, matching the system volume HUD
- Maintains a singleton via `/tmp/vinput_hud.pid`: a new HUD kills the previous one
- Mouse-passthrough, shows across Spaces, auto-fits text width
- Multi-screen aware: uses `NSEvent.mouseLocation` to hit whichever screen the cursor is on

### 6. UTF-8 encoding handling

Raycast-spawned child processes don't inherit Terminal's LANG, so `pbcopy` treats UTF-8 Chinese bytes as Latin-1 and pastes garbled text. The script forces:
```bash
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
```
