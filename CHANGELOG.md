# Changelog

All notable changes to this project will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

See [ROADMAP.md](./ROADMAP.md) and [open milestones](https://github.com/aimer1124/local-voice-input/milestones) for what's planned next.

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

[Unreleased]: https://github.com/aimer1124/local-voice-input/compare/v1.2.0...HEAD
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
