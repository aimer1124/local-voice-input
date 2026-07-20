# Advanced Configuration

> [中文](./configuration-advanced.zh.md) · back to [README](../README.md#-advanced-configuration)

These are **not in the default config template**, because the defaults are already tuned for
Chinese + programmer workflows and the vast majority of people won't touch them. Add them to
`~/.config/vinput.conf` by hand when needed (blank = built-in default, no error). After changing
any Whisper/LLM-related setting, run the [Regression Tests](../README.md#-regression-tests-must-run-before-tagging)
once before relying on it.

## Whisper decoding internals

```bash
WHISPER_THREADS=8             # inference threads
WHISPER_ZH_SIMPLIFY=1         # Traditional→Simplified normalization (opencc, optional dep). Whisper's -l zh picks the language, not the script — large-v3-class models often emit Traditional glyphs regardless of accent. 0 to keep Traditional output (e.g. Taiwan/HK users). No-op on already-simplified/non-CJK text; falls back to no-op if `opencc` isn't installed (`vinput --doctor` flags it)
WHISPER_BEAM_SIZE=5           # beam-search width, reduces homophone misses; +0.5s latency
WHISPER_TEMPERATURE_INC=0.2   # temperature increment step, a sampling fallback against empty output on failure
# WHISPER_TEMPERATURE=0       # starting temperature; blank = whisper.cpp default
# WHISPER_NO_SPEECH_THOLD=0.6 # lower = stricter. ⚠️ v1.1.3's stricter value judged ordinary mics as "non-speech"; v1.1.6 reverted to default (blank)
# WHISPER_LOGPROB_THOLD=-1.0  # closer to 0 = stricter. Same story; only consider it if doctor reports a weak signal

# Long-audio decode escape hatches (blank = whisper.cpp default). ⚠️ Measured to give NO gain on
# the long-audio sample — capping --max-context actively HURT. Manual experiments only; see the
# negative-results table in tests/asr/README.md before touching these.
# WHISPER_ENTROPY_THOLD=       # blank = whisper.cpp default (2.40)
# WHISPER_MAX_CONTEXT=         # blank = whisper.cpp default (-1); setting small measured worse, not better
# WHISPER_CARRY_PROMPT=0       # 1 = re-inject the prompt into every 30s window; measured no gain
```

## LLM intent reshaping (long content)

```bash
LONG_TEXT_THRESHOLD=80   # transcripts ≥ this many chars (CN: 1 char = 1) switch the LLM from
                         # "distill into one instruction" to "tidy up + keep structure, don't summarize"
```

Short utterances go through the terse distiller as before. Once a transcript reaches `LONG_TEXT_THRESHOLD`, the LLM uses a structure-preserving prompt instead, so a multi-point ramble stays a multi-point list rather than being compressed into a single lossy sentence.

After reshaping (for both normal and EN modes), a deterministic **critical-token guard** checks that the Arabic numbers present in the transcript survived the LLM rewrite (e.g. "remove the 5 buttons" must not become "remove the buttons"). If a number was silently dropped, it pastes the corrected **raw transcript** instead and the HUD warns. The guard is always on, never overrides a faithful rewrite, and needs no config. (A negation guard shipped in 1.8.0 but was removed in 1.8.1: conversational Chinese — 看不懂 / 能不能 / 是不是 — false-fired constantly, falling back to raw and losing punctuation/polish. Negation preservation is left to the LLM prompt's hard rules.)

## Dynamic prompt context

Prepends the last N successful transcriptions to Whisper's `--prompt` to give the model "short-term memory". In practice, proper-noun hit rate is +20~40% when chatting about the same topic in a row.

```bash
USE_RECENT_PROMPT=1
RECENT_PROMPT_COUNT=5
RECENT_PROMPT_FILE="$HOME/.cache/vinput/recent.txt"
RECENT_PROMPT_MAX_CHARS=280
```

## SoX recording preprocessing

> ⚠️ Every effect must be streaming-safe (cannot depend on a full-rectification buffer). v1.1.4 used `norm -3`, which made rec output 0 frames on SIGINT → "no valid speech detected". v1.1.7 reverted to a fixed gain.

```bash
USE_SOX_PREPROCESS=1
SOX_HIGHPASS=80     # cut low frequencies: fan / street rumble
SOX_LOWPASS=8000    # cut high frequencies: hiss / jitter
SOX_GAIN_DB=-3      # fixed gain (already in the basic config; listed here for completeness)
REC_WARMUP_MS=150   # wait for rec's buffer to be ready before prompting you to speak, avoiding a dropped first word
```

## VAD thresholds (only when `USE_VAD=1`)

```bash
SILENCE_TAIL=1.5
SILENCE_START_THRESHOLD="0.5%"
SILENCE_STOP_THRESHOLD="6%"
```

## HUD final state & ↑ re-record

```bash
# HUD_SHOW_RESULT=1       # after pasting, the HUD shows what was actually pasted (truncated to 60 chars)
# HUD_FINAL_DURATION=2.5  # how many seconds the final state lingers
# HUD_RERUN_ON_UP=0       # 1 = press ↑ during the final state to instantly re-run the full pipeline (ESC always closes immediately)
# HUD_CANCEL_ON_ESC=1     # 0 = disable. Double-press ESC (within 1s) while recording to discard the take —
#                         # no paste, ready to re-record immediately
```

> `HUD_RERUN_ON_UP=1` and ESC-cancel both require checking the hud binary (path via `vinput --doctor`) in **System Settings → Privacy → Input Monitoring**.
> Without permission the HUD still displays fine, the keys just do nothing — convenience features that degrade gracefully.

HUD appearance (8 knobs: position/font/material/etc.) is covered in [HUD style adjustments](../README.md#hud-style-adjustments) in the README.

## Per-app mode override

Automatically switch mode based on the frontmost app at the moment you press the hotkey — e.g. get the raw transcript (no LLM reshaping) inside terminals. Off by default: the feature only activates if the mapping file exists.

```bash
APP_MODES_FILE="$HOME/.config/vinput_app_modes.tsv"   # one "bundle-id<TAB>mode" per line, mode ∈ raw|en
```

Copy `config/vinput_app_modes.example.tsv` there and uncomment the terminals you use. Find any app's bundle id with `lsappinfo info -only bundleid "$(lsappinfo front)"` (bring it frontmost first). Detection uses `lsappinfo` — no new permissions, ~10ms, never delays recording start. An explicit Raw/EN hotkey always wins over the map; any lookup failure silently falls back to the default mode.

## Clipboard restore

```bash
RESTORE_CLIPBOARD=1   # 0 = disable. After a successful auto-paste, restores whatever text was on
                      # your clipboard before vinput overwrote it (~1s delay so the target app
                      # reads the result first)
```

Text-only: images and other non-text clipboard content can't be captured by `pbpaste`, so those are not restored. When auto-paste fails or `AUTO_PASTE=0`, the transcription result is deliberately left on the clipboard for you to paste manually.

## Diagnostics: lock/stage timing log

```bash
VINPUT_LOCK_LOG=1   # 0 = disable. Appends state-machine transitions (press / rec:start /
                    # transcribe:done / llm:done / paste:done / release, with timestamp + PID)
                    # to ~/.cache/vinput/lock.log
```

If a hotkey press ever gets rejected with "still processing the previous recording", this log shows which stage was holding the lock and for how long. Negligible overhead; safe to leave on.
