# Changelog

All notable changes to this project will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

See [ROADMAP.md](./ROADMAP.md) and [open milestones](https://github.com/aimer1124/local-voice-input/milestones) for what's planned next.

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

[Unreleased]: https://github.com/aimer1124/local-voice-input/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/aimer1124/local-voice-input/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/aimer1124/local-voice-input/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aimer1124/local-voice-input/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aimer1124/local-voice-input/releases/tag/v1.0.0
