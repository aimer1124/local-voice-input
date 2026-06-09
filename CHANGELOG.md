# Changelog

All notable changes to this project will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.7.2] — 2026-06-09

Reliability fix for the LLM-refinement step hanging forever.

### Fixed
- **LLM step could hang the whole pipeline if Ollama wedged.** The `clean_with_llm` /
  `clean_with_llm_en` calls used `curl` with **no timeout**, so if Ollama stopped responding
  (e.g. a broken Homebrew Ollama whose `llama-server` backend is missing — every inference
  request then hangs), `curl` waited forever, the recording lock was never released, and the
  result never reached the input box; subsequent hotkeys fell into the toggle-stop branch
  ("已停止，转写中"). Added `--connect-timeout 5 --max-time "$OLLAMA_TIMEOUT"` to both calls.
  The empty-response fallback already in place then pastes the **raw transcript** instead of
  hanging — you still get your words, just unpolished.

### Added
- **`OLLAMA_TIMEOUT`** config option (default `30`s) — total timeout for the LLM-refinement
  call. Raise it on machines where cold-loading the model is slow; lower it to fail over to the
  raw transcript faster. Documented in `config/vinput.conf.example`, both READMEs (Configuration
  + Troubleshooting).
- **Doc-coverage guard** (`scripts/check-docs.sh`, wired into `scripts/preflight.sh`) — asserts
  every user-configurable `FOO="${FOO:-…}"` knob in `vinput_bg.sh` is mentioned in a README or
  the conf example (or is on a short, justified internal allowlist). Docs here are hand-written;
  this catches the "added a knob, forgot to document it" drift. It immediately caught three
  long-audio escape-hatch knobs (`WHISPER_ENTROPY_THOLD` / `WHISPER_MAX_CONTEXT` /
  `WHISPER_CARRY_PROMPT`) that shipped in 1.7.0 undocumented — now in README Advanced Config.

## [1.7.1] — 2026-06-08

Reliability fix for a recording that could never stop.

### Fixed
- **Stuck `rec` process → permanent "已停止，转写中" on every trigger.** When the audio device
  wedges, `rec` (SoX) can ignore `SIGINT`; the 30s hard-timeout guard only sent `SIGINT`, so a
  wedged `rec` ran forever, `wait` blocked forever, and `/tmp/vinput.lock.d` was never released —
  after which every hotkey press landed in the toggle-stop branch instead of starting a new
  recording (observed in the wild: a `rec` stuck for two days, only `kill -9` cleared it). Two
  defenses added in `bin/vinput_bg.sh`:
  - **Guard escalation** — the hard-timeout guard now follows `SIGINT` with a `SIGKILL` 3s later,
    so a wedged `rec` is always reaped at `MAX_REC_SECONDS + 3s` and the lock is released.
  - **Stale-lock reclaim by age** — on toggle, a lock older than `MAX_REC_SECONDS + 60s` (well
    beyond any healthy record-plus-transcribe cycle) is treated as a zombie and force-reclaimed
    into a fresh recording, instead of being "stopped". Covers the case where the guard process
    itself died (system sleep / parent killed → orphaned `rec`). The reclaim verifies the PID is
    actually a `rec` process before killing, to avoid hitting a reused PID.

## [1.7.0] — 2026-06-08

Headline: **EN mode** — speak Chinese, paste an English prompt — plus a long-audio quality guard.
The release also hardens the transcription internals: the whisper-cli flag list now has a single
source of truth, and the ASR regression suite finally covers long-form dictation (the case that
degrades most), with the dead-end tuning experiments archived so they aren't re-run.

### Added
- **EN mode — a third Raycast command (`🌐 语音输入 (EN)`)** — speak Chinese, get an English
  prompt. Shares `vinput_bg.sh` with the default and Raw commands; `VINPUT_TRANSLATE_EN=1` swaps the
  LLM step for a "Chinese speech → English written instruction" translate-and-reshape pass (new
  `clean_with_llm_en`, leaving the Chinese `clean_with_llm` untouched). ASR still transcribes with
  `-l zh`. **Always** runs the LLM (ignores `SHORT_TEXT_THRESHOLD`), otherwise a short Chinese phrase
  would come back unchanged in Chinese. Suggested hotkey `⌃⇧Space`. Deployed by both `install.sh` and
  `vinput setup`; adds a `--test-llm-clean-en` test hook.
- **Long-audio ASR regression sample** (`tests/asr/07-zh-long`, 66s continuous Chinese that crosses
  whisper's 30s window boundary). The suite previously topped out at a few-second utterances, so
  long-form dictation quality had no guard. Baseline raw CER ≈ 0.117 (vs 0.00–0.025 for short
  samples), driven by homophones and occasional window-boundary clause drops.
- **Escape-hatch decode knobs** `WHISPER_ENTROPY_THOLD` / `WHISPER_MAX_CONTEXT` /
  `WHISPER_CARRY_PROMPT` (blank defaults = no change to whisper.cpp defaults). For manual
  experimentation only — measured to give no gain (and `--max-context` capping actively *hurts*);
  rationale + data archived in `tests/asr/README.md` so the dead ends aren't re-explored.

### Changed
- **Deduped the whisper-cli invocation** into a single `build_whisper_args()` helper. The
  `--test-transcribe` hook and the production path previously assembled the flag list twice and
  relied on a "keep in sync" comment; new flags now have one source of truth. Behavior-neutral —
  ASR suite CER unchanged for samples 01–06.

See [ROADMAP.md](./ROADMAP.md) and [open issues](https://github.com/aimer1124/local-voice-input/issues) for what's planned next.

---

## [1.6.0] — 2026-05-29

A round of UX & onboarding fixes. The throughline: turn three "it failed but you can't tell why"
**silent failures** into one-line-fixable, actionable hints (#4 mic, #8 accessibility), and add
`dry-run` / `skip-models` / `upgrade-only` flags to `install.sh` (#9). Plus config-template slimming
and doc alignment.

### Added
- **`install.sh` flags (#9)** — added `--dry-run` (read-only env check + print planned actions,
  download/write nothing), `--skip-models` (skip the Whisper ~550MB + Ollama ~2GB downloads, for
  offline machines), `--upgrade-only` (refresh only the runtime scripts and HUD, skip deps and
  models, for re-install/upgrade), and `--help`. Combinable. Added a `run()` wrapper so every write
  op only prints its intent under dry-run; fixed `mkdir -p ~/.whisper_models` previously running only
  in the "download models" step and going missing under `--skip-models` (moved it to the always-run
  HUD deploy step).

### Fixed
- **Accessibility silent paste failure (#8)** — without Accessibility permission the auto ⌘V is
  rejected by macOS (keystroke returns `-1719`); previously the text only reached the clipboard
  without being pasted while the HUD still showed `✓ 已完成`, leaving users baffled. We now catch
  that error and turn it into an actionable guide — `📋 已复制到剪贴板 · 自动粘贴需在 设置 → 隐私
  → 辅助功能 勾选 Raycast，先按 ⌘V 用着` — and on the **first** occurrence auto-open the relevant
  Settings panel (no nagging afterward). Note: the other two checks issue #8 wanted — mic permission
  (macOS auto-prompts on first recording) and whether the default input is a real mic
  (`vinput --doctor` device check + #4's RMS rescue) — are already covered separately; this closes
  the last accessibility gap.
- **Silent-failure rescue (#4)** — an empty transcription no longer always pops
  `未识别到有效语音`. It first measures the recording's RMS level (reusing the same
  `vinput --doctor` sox stat, triggered only on the failure path, zero overhead on success) and
  gives an actionable diagnosis by level: dead silence (≤0.002) → `🎤 麦克风几乎没声音 — 拔掉无麦
  耳机，或检查 系统设置 → 声音 → 输入`; weak (<0.01) → `🔈 声音太小没听清 — 靠近麦克风，或调大
  SOX_GAIN_DB`; normal signal yet still empty → keeps the original message. This turns the most
  common "plugged-in 3-pole TRS headphones, no audio captured and no idea why" dead-end into a
  one-line fix.

### Changed
- **Config template slimming** — `config/vinput.conf.example` trimmed to ~8 basic knobs; the Whisper
  decoding internals / dynamic prompt / SoX / VAD / HUD advanced items moved to the README "Advanced
  Configuration". Every removed item's built-in default is byte-for-byte identical to the old
  template, so fresh installs see zero behavior change.
- **Doc consistency** — the `SHORT_TEXT_THRESHOLD` template default corrected from 8 to 15 (aligning
  the code default with the README); README's HUD line-count/size corrected (~240 lines / ~116KB).

---

## [1.5.0] — 2026-05-28

Minor — closes the last piece of #23. The HUD now optionally responds to
`↑` (rerun) and `ESC` (early dismiss), so frequent re-takes don't need to
go through Raycast again.

### Added
- **HUD ↑-to-rerun (#23 final)** — `HUD_RERUN_ON_UP=1` makes the
  final-result HUD spawn a fresh `vinput_bg.sh` when the user presses
  `↑` during its display. ESC always dismisses immediately.
- **`HUD_ON_UP_CMD` env var** in `src/hud.swift` — when set to any
  non-empty shell command, the HUD registers an `NSEvent` global key
  monitor and runs the command via `/bin/bash -lc` on `↑`. Detached
  child, no FD inheritance.
- **`vinput.conf.example`** documents `HUD_SHOW_RESULT`,
  `HUD_FINAL_DURATION`, and `HUD_RERUN_ON_UP` so users can discover
  and tune the new behavior.

### Notes
- **Permission ask** — `↑` requires the user to grant the `hud` binary
  *Input Monitoring* in System Settings → Privacy. Without it, the HUD
  still displays normally; only `↑` is a no-op. The Swift code writes
  a hint to stderr (which `vinput_bg.sh` captures into
  `/tmp/vinput_debug.log`) on registration failure.
- **Why opt-in** — most users won't want a permission prompt for a
  convenience feature. Default off; document the toggle in
  `vinput.conf` and `caveats`.
- **The whole hotkey path is detached** — when `↑` fires, HUD spawns
  the new transcription via `Process()` with all FDs set to
  `FileHandle.nullDevice`, then runs its own dismiss animation. No
  parent-child wait, no shared state beyond the script's own
  `/tmp/vinput.lock.d` (which was already cleaned up by the previous
  invocation's trap before the HUD even showed).

---

## [1.4.0] — 2026-05-28

Minor — closes the last two v1.3.0 milestone items (#19, #23). With this
release, every successful transcription is logged with structured metadata,
the HUD shows what was actually pasted, and the LLM regression suite handles
its own stochasticity.

### Added
- **`vinput history` (#19)** — every transcription appends a JSONL row to
  `~/.cache/vinput/history.jsonl` with `{ts, raw, corrected, cleaned,
  mode, rules_fired, audio_ms}`. Auto-rotates at 1000 lines to
  `history.jsonl.old`. Three subcommands:
  ```
  vinput history                  # last 20, colored table
  vinput history --tail N         # last N
  vinput history --grep PATTERN   # regex on raw/corrected/cleaned
  vinput history --raw-only       # ts + raw only (for error-word mining)
  ```
  Closes the loop with #18: scan history for systematic errors →
  `vinput add-correction <对> <错>` → next time it's auto-fixed.
- **HUD shows final text (#23 partial)** — after paste, HUD displays
  `✓ {cleaned text, ≤60 chars}` for 2.5s instead of a generic
  "✓ 已完成" flash. Two env vars: `HUD_SHOW_RESULT=0` to revert,
  `HUD_FINAL_DURATION=4.0` to dwell longer. Truncation uses
  `cut -c` under `LC_ALL=en_US.UTF-8` so CJK characters count as 1
  each (not 3 bytes).
- **LLM regression suite retry logic** — each case now retries up to 3
  times before declaring fail. Override with `VINPUT_LLM_MAX_TRIES=1`
  for strict mode. Reason: a perfectly-tuned prompt still flakes ~10%
  on qwen2.5:3b — the suite should catch systematic regressions, not
  ambient noise. PASS rows show "(try N/3)" when retries were used.
- **`list_fired_corrections()`** in `vinput_bg.sh` — computes which
  correction rules matched on a given text without applying them.
  Used by history writer to record which rules earned their keep this
  run; foundation for a future `vinput corrections --hit-rate` command.

### Deferred
- **#23 ↑-to-rerun via global hotkey** — needs Swift HUD changes to
  register `NSEvent.addGlobalMonitorForEvents`. Left for a follow-up
  focused on the Swift layer; the text-display half landed here.

### Notes
- The `mode` field in history (`full` / `raw` / `short`) makes it easy
  to see how often each path runs. Skim with
  `jq -r .mode ~/.cache/vinput/history.jsonl | sort | uniq -c`.
- `rules_fired` is computed by re-scanning the corrections table, not
  by modifying `apply_corrections()`. Slight redundancy (one extra
  pass per transcription) but keeps the correction path itself dead
  simple.

---

## [1.3.0] — 2026-05-28

Minor — closes three v1.3.0 milestone items (#21, #22) plus a defensive
infrastructure item (bash lint). The LLM cleanup stage is now under
regression coverage — together with v1.2.0's ASR suite and correction
table, all three transcription stages (Whisper → corrections → LLM) now
have automated guards.

### Added
- **LLM cleanup regression suite** — `tests/llm/` with 6 cases covering
  number preservation, negation preservation, no-code-output, filler
  removal, self-correction handling, and list preservation. Each case is
  three files (`.input.txt` / `.must_contain.txt` / `.must_not_contain.txt`)
  using contract-style assertions instead of fragile string matching.
  Run: `bash tests/llm/run.sh`.
- **LLM cleanup refactored into `clean_with_llm()` function** —
  `bin/vinput_bg.sh` no longer inlines the Ollama call. Production path
  and the new `--test-llm-clean <text>` test path share one
  implementation, so the regression suite measures the same code that
  ships.
- **Few-shot LLM prompt (#21)** — replaces the rule-only prompt with five
  worked examples covering each defect pattern from the issue. Explicitly
  guards numbers, negations, proper nouns, list structure, and forbids
  code-block output. All 6 regression cases pass on qwen2.5:3b.
- **Raw mode (#22)** — `📝 语音输入 (Raw)` Raycast script and
  `VINPUT_RAW=1` env var: skip the LLM stage, paste Whisper output as-is.
  Recommended binding: `⌥+Space` (complements the default `⌘⇧Space`).
  Use for short commands, original transcription preservation, or when
  the LLM over-cleans.
- **Bash lint (`scripts/lint-shell.sh` + CI)** — grep for the
  `$IDENT<non-ASCII>` pattern that bit us in v1.1.5, v1.1.8, and earlier.
  Bash treats `$HOTWORDS_FILE（` as one identifier under `set -u`; the
  lint fails on this pattern across `bin/`, `scripts/`, `raycast/`,
  `tests/`, and `install.sh`. Lines containing `lint-shell:disable` are
  skipped (for literal documentation of the anti-pattern). Wired into
  GitHub Actions (`.github/workflows/lint.yml`) on every push and PR.

### Fixed
- `scripts/make-demo-gif.sh:84` had `$dep，` (Chinese comma) — would have
  crashed under `set -u`. Caught by the new lint.

### Notes
- **Three layers, three guards** — Whisper layer is gated by
  `tests/asr/`, corrections layer is data-only (no test needed), LLM
  layer is gated by `tests/llm/`. Together they form a hermetic
  pre-tag check: `bash tests/asr/run.sh && bash tests/llm/run.sh`.
- **The lint script is itself a project lesson** — three hotfixes (one
  per release) ate two hours of debugging. A 50-line grep prevents that
  entire bug class. The cost/benefit ratio for defensive infrastructure
  is the highest of any work in this release.

---

## [1.2.0] — 2026-05-27

Minor — adds the **regression test suite** (#24) and **phonetic correction
table** (#18). First release where ASR changes are gated by a reproducible
benchmark instead of vibes.

### Added
- **`tests/asr/` regression suite** — 6 fixed TTS samples (Tingting voice),
  Levenshtein-based CER, per-sample budget table, single-command runner:
  ```
  bash tests/asr/run.sh
  ```
  Run this before any tag. The harness shells through a new
  `vinput_bg.sh --test-transcribe <wav>` mode, so the production code path
  is what's actually measured (not a parallel re-implementation that can
  drift). Zero pip dependency — CER is a 30-line pure-stdlib script.
  Acceptance criteria from #24 met: 6 samples, per-sample CER ceiling,
  README "如何贡献样本" section. CI gate deferred to a follow-up (the
  baseline needs to settle in user hands first).
- **Phonetic correction table (#18)** — `~/.config/vinput_corrections.tsv`
  TSV (one row per correct form, tab-separated wrong variants), applied
  after Whisper / before LLM cleaning. Case-insensitive ASCII matching,
  single sed invocation for the whole table (~5ms for 100 rules).
  Ships with 16 seeded rules (Claude Code, Whisper, Ollama, qwen2.5,
  useEffect, …) and three subcommands:
  ```
  vinput corrections                     # list all
  vinput add-correction <对> <错>         # append (auto-dedupe)
  vinput remove-correction <对> <错>
  ```
  Validated against the new regression suite: 4 of 5 imperfect samples
  dropped to CER 0 once the table was loaded.

### Notes
- **Format choice (TSV instead of YAML)** — the issue spec'd YAML, but
  shipping YAML would mean adding `yq` as a brew dep or a python dep
  (PyYAML) for ~50 lines of value. TSV gives the same data shape with
  pure bash parsing. If/when we move to a richer schema (regex variants,
  per-rule weights), revisit.
- The regression suite caught two real defects on its first run before
  #18 even landed: `Claude Code → Cloud Code` and `重构 → 中构`. Both
  are now fixed by the default correction table.

---

## [1.1.8] — 2026-05-27

Hotfix — same bug class as v1.1.5, on a different line.

### Fixed
- `cmd_setup` had `$HOTWORDS_FILE（保留不覆盖）` in the new
  auto-migration code path from v1.1.7 — Chinese full-width `（`
  directly after `$VAR` makes bash with `set -u` treat the whole
  thing as one unbound identifier. Fixed with `${HOTWORDS_FILE}`.
  Same pattern as the v1.1.5 fix for `$CONFIG_FILE` and `$OLLAMA_MODEL`.

### Lesson
- Running a project-wide regex sweep for `\$VAR<non-ASCII>` would have
  caught all three at once. Added to the v1.3.0 #24 benchmark suite as
  a lint check: pre-commit hook should grep for this pattern and fail.

---

## [1.1.7] — 2026-05-27

Hotfix — completes the v1.1.3→v1.1.6 recovery saga.

### Fixed
- **SoX `norm -3` doesn't work in streaming `rec`** — v1.1.4 added peak
  normalization to the SoX chain, but `norm` is a two-pass effect: it
  reads the entire input to find the peak, then scales. In a streaming
  `rec` that gets SIGINT'd when the user presses "stop", the buffer
  never flushes → WAV ends with **0 audio frames** → whisper-cli
  errors with `failed to read the frames of the audio data` → HUD
  shows ❌ 未识别到有效语音.
  Replaced with `gain -3` (single-pass, streaming-safe). Configurable
  via `SOX_GAIN_DB` (set to a positive value to amplify quiet mics).
- **Legacy word-per-line hotword files corrupt Chinese transcription**
  — `~/.config/vinput_hotwords.txt` from v1.0.x is 44 English tech
  terms, one per line. Passed as `--prompt` with `-l zh`, Whisper
  outputs garbled UTF-8 (`卖����`) which `sed` rejects → empty
  RAW_RESULT → same false "未识别到有效语音" error. `vinput setup`
  now detects this format (no Chinese chars, > 10 short lines) and
  automatically migrates it to the v1.1.4 sentence-form, backing up
  the original to `vinput_hotwords.txt.v1.0.x-backup`.
- **`sed` UTF-8 robustness** — in case Whisper still produces
  invalid UTF-8 in some edge case, the read path now runs sed under
  `LC_ALL=C` and rescues non-UTF-8 output with `iconv -c`.

### Added
- `VINPUT_DEBUG_KEEP=1` — when set, preserves the most recent
  `voice.wav` + whisper output at `/tmp/vinput-last.*` for debug
  inspection. Default off; no overhead in normal runs.

### Removed
- The always-on debug copy from v1.1.7-dev. (Replaced by the opt-in
  flag above.)

### Lessons
- v1.1.3's claimed "+13% homophone, +21% proper-noun, -10% hallucination"
  numbers were **paper-extrapolated, never measured**. They cost three
  hotfixes to recover from.
- v1.1.4's claimed "+18% quiet-speaker accuracy" was **physically
  impossible** because `norm` never worked in streaming `rec`.
- Real-audio regression suite is now a hard prerequisite — tracked
  separately in v1.3.0.

---

## [1.1.6] — 2026-05-27

Hotfix — revert v1.1.3's strict Whisper thresholds that caused empty
recognition on normal-quality audio.

### Fixed
- `--no-speech-thold 0.5` and `--logprob-thold -0.8` from v1.1.3 were
  **stricter than whisper.cpp's defaults** (0.6 / -1.0). On real-world
  audio (built-in mic, headset, marginal SNR), this caused Whisper to
  flag every segment as either "non-speech" or "low-confidence" and
  drop it — producing an empty transcript that surfaced as the HUD
  message **❌ 未识别到有效语音**.
  Defaults are now left unset, so whisper.cpp picks its own (0.6 /
  -1.0). Users wanting the stricter v1.1.3 behavior can set the env
  vars back in `vinput.conf`.

### Kept (genuinely good)
- `--beam-size 5` (still helps with homophones)
- `--temperature-inc 0.2` (fallback when greedy returns empty)
- All SoX preprocessing, dynamic prompt, record-buffer warmup.

---

## [1.1.5] — 2026-05-27

Critical patch — `vinput setup` failed on brew install with `unbound variable`.

### Fixed
- `cmd_setup` had `$CONFIG_FILE（保留不覆盖）` and `$OLLAMA_MODEL（约 2GB）`
  where the Chinese full-width `（` was treated as part of the variable name
  under `set -u`, crashing setup at step 4/6 (config files) or 6/6 (Ollama).
  Now uses `${VAR}` braces. Affects everyone who ran `brew install
  local-voice-input` and tried `vinput setup`.

---

## [1.1.4] — 2026-05-27

ASR Quality Round 2 — dynamic context + cleaner audio pipeline.

### Added
- **Dynamic prompt context** — the last `RECENT_PROMPT_COUNT` (default 5)
  successful transcriptions are cached to `~/.cache/vinput/recent.txt`
  and prepended to Whisper's `--prompt` on the next run. Gives the
  decoder short-term memory across calls, which significantly improves
  proper-noun recognition on repeated-topic conversations. Total prompt
  is capped at `RECENT_PROMPT_MAX_CHARS` (default 280). All
  configurable via `vinput.conf`. (closes #17)
- **SoX recording preprocessing** — `highpass 80`, `lowpass 8000`,
  and peak normalization (`norm -3dB`, replaces the old `gain -3`
  attenuation) now clean up the audio before it reaches Whisper.
  Quiet speakers benefit the most: peak normalization amplifies them
  to a target level instead of attenuating. All filter params
  overridable via `SOX_HIGHPASS`, `SOX_LOWPASS`, `SOX_NORM_DB`. Master
  switch: `USE_SOX_PREPROCESS=1`. (closes #20)
- **Record-buffer warmup** — `REC_WARMUP_MS=150` (default) delays the
  "start" cue + HUD until `rec` has opened the audio device, so the
  first syllable is no longer at risk of being lost to buffer
  initialization jitter.

### Notes
- No new dependencies. Pure config + shell additions.
- Old `gain -3` behavior is preserved when `USE_SOX_PREPROCESS=0` for
  users who want exactly the v1.1.3 audio path back.

---

## [1.1.3] — 2026-05-27

ASR decode tuning patch — first concrete wins on transcription accuracy.

### Changed
- **Whisper decode parameters** — added `--beam-size 5`,
  `--temperature 0 --temperature-inc 0.2`, `--no-speech-thold 0.5`,
  `--logprob-thold -0.8`. Reduces homophone misses (e.g. "空航" vs
  "空行"), prevents hallucinated text in silent segments, and
  recovers gracefully when greedy decode returns empty. All
  overridable via `~/.config/vinput.conf`. (closes #14)
- **Hotword file is now sentence-form** — Whisper's `--prompt` is a
  decoder context, not a keyword list. Context-rich sentences bias
  the decoder substantially harder than a comma-separated list.
  Existing comma-only hotword files keep working but new installs
  start with sentence-form examples. (closes #15)
- **Short-text threshold uses `wc -m`** — previous byte-length check
  treated a 5-char Chinese sentence (15 bytes) the same as a 15-char
  English one, leading to inconsistent LLM bypass. Default threshold
  re-tuned from 15 to 8 (characters). (closes #16)

### Notes
- No new dependencies; pure config + flag change.
- Decode latency: ~+0.5s for the beam search; subjectively unnoticeable.

---

## [1.1.1] — 2026-05-27

Bootstrap polish — prepares the ground for the Homebrew tap.

### Added
- **`vinput setup`** subcommand — single-shot bootstrap that installs deps,
  downloads the Whisper model, symlinks runtime scripts into
  `~/.whisper_models/`, copies the Raycast template, and warms up Ollama.
  Designed to run after `brew install` (works equally well from a git clone).
- Symlink-resolution helper so `vinput` correctly locates its resource root
  whether invoked from `prefix/bin/vinput` (Homebrew) or `repo/bin/vinput`
  (git clone).

### Changed
- `install.sh` version pinned to 1.1.1 so the pre-built HUD fallback URL
  matches the release asset.

---

## [1.1.0] — 2026-05-27

UX polish milestone — demo, diagnostics, configurable HUD.

### Added
- **Demo GIF** in README top, with subtitle overlay pipeline using Pillow
  (since `brew ffmpeg` ships without `drawtext`). `scripts/make-demo-gif.sh`
  + `scripts/overlay_captions.py` handle the conversion with auto-installed
  deps and CJK font fallback chain. (closes #1)
- **`vinput --doctor`** diagnostic command — checks toolchain, resources,
  runtime state, default audio device, and runs a 3-second mic test.
  Reports failures with concrete fix suggestions; smart-detects the
  "wired headphones routed to phantom mic" scenario. (closes #2)
- **`vinput --version`** flag — prints version + git short SHA + repo URL.
  (closes #5)
- **`bin/vinput`** CLI dispatcher — single entry point for meta commands;
  does *not* trigger recording (avoids accidental triggers from terminal
  typos). Real voice input still goes through Raycast → `vinput_bg.sh`.
- **HUD style configurability** — eight aspects of the screen-center HUD
  (position, height, font size/weight, corner radius, visual material,
  width clamping) are now overridable via env vars typically set in
  `vinput.conf`. No recompile needed. (closes #3)

### Changed
- `install.sh` now also deploys `bin/vinput` and prints an alias suggestion
- `uninstall.sh` cleans up `vinput` binary
- README "故障排查" / Troubleshooting now leads with `vinput --doctor`
- HUD style section in README replaces recompile recipe with config table

---

## [1.0.2] — 2026-05-27

### Added
- Project polish layer: `CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`
- GitHub issue templates (bug report + feature request)
- README status badges (CI, latest release, license, platform)

### Changed
- Documentation now consistently uses bilingual (zh-CN + English) structure

---

## [1.0.1] — 2026-05-27

### Added
- **CI auto-release**: GitHub Actions workflow auto-builds the HUD binary and attaches it to the matching release on every tag push ([`.github/workflows/release.yml`](./.github/workflows/release.yml))
- **install.sh smart fallback**: When `swiftc` is missing, downloads pre-built HUD binary from the release; auto-clears Gatekeeper quarantine attribute
- **Bilingual release convention**: All future releases ship notes in both Chinese and English; template at [`docs/RELEASE_TEMPLATE.md`](./docs/RELEASE_TEMPLATE.md)

### Changed
- `install.sh` now reports more granular progress in the HUD-preparation step

---

## [1.0.0] — 2026-05-26

### Added
- First stable release of **local-voice-input** (CLI tool name: `vinput`)
- Fully offline pipeline: Raycast → SoX → Whisper.cpp → Ollama qwen2.5:3b → ⌘V
- Toggle hotkey UX: press to start, press again to stop
- 30-second hard timeout safety net
- macOS multi-monitor HUD (Swift, frosted glass, follows cursor's screen)
- Hotword injection via Whisper `--prompt`
- LLM intent refinement with short-text bypass
- Ollama `keep_alive=30m` for warm-model latency
- mkdir-based atomic lock (mutex + state machine)
- UTF-8 LANG export to prevent Raycast→pbcopy garbling
- One-line installer `install.sh` covering all dependencies, model downloads, deployment, and Ollama pre-warming

---

[Unreleased]: https://github.com/aimer1124/local-voice-input/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/aimer1124/local-voice-input/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/aimer1124/local-voice-input/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/aimer1124/local-voice-input/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/aimer1124/local-voice-input/compare/v1.1.8...v1.2.0
[1.1.8]: https://github.com/aimer1124/local-voice-input/compare/v1.1.7...v1.1.8
[1.1.7]: https://github.com/aimer1124/local-voice-input/compare/v1.1.6...v1.1.7
[1.1.6]: https://github.com/aimer1124/local-voice-input/compare/v1.1.5...v1.1.6
[1.1.5]: https://github.com/aimer1124/local-voice-input/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/aimer1124/local-voice-input/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/aimer1124/local-voice-input/compare/v1.1.1...v1.1.3
[1.1.1]: https://github.com/aimer1124/local-voice-input/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/aimer1124/local-voice-input/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/aimer1124/local-voice-input/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aimer1124/local-voice-input/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aimer1124/local-voice-input/releases/tag/v1.0.0
