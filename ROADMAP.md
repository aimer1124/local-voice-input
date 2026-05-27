# Roadmap

> 中文 | [English ↓](#english)

本文档为 **local-voice-input** 的公开开发路线图。每个版本对应一个 [GitHub Milestone](https://github.com/aimer1124/local-voice-input/milestones)，每个待办项对应一个 [Issue](https://github.com/aimer1124/local-voice-input/issues)。

工作以 **当前主线 → v1.1.0 → v1.2.0 → v2.0.0** 顺序推进，未列出的小修小补可能在 patch 版本（如 v1.0.x）随时合入。

---

## 🚀 v1.1.0 — UX Polish（短期目标）

**目标**：把"能用"打磨到"舒服用"，降低高频痛点。

| 任务 | 类型 | 描述 |
|---|---|---|
| 演示 GIF / 视频 | docs | README 顶部放 30 秒完整流程演示 |
| `vinput --doctor` | feat | 一键诊断命令：检查模型 / 麦克风 / 权限 / Ollama 状态 |
| HUD 样式可配置 | feat | 位置、字号、颜色通过 `vinput.conf` 配置，无需重新编译 Swift |
| 3 极 TRS 耳机兼容 | bug | macOS 把无麦的有线耳机当默认输入设备的问题 |
| `vinput --version` | feat | 添加版本号查询 |

---

## 📦 v1.2.0 — Onboarding（中期目标）

**目标**：让"装"变得无脑，移除技术门槛。

| 任务 | 类型 | 描述 |
|---|---|---|
| Homebrew tap | packaging | `brew install aimer1124/tap/local-voice-input` 一行装 |
| Apple Notarization | security | 给 HUD 二进制做 Apple Developer 公证，免清隔离属性 |
| 首次启动向导 | feat | 自动检测 Raycast 权限，引导补齐缺失项 |
| `install.sh` 开关 | feat | `--dry-run` `--skip-models` `--upgrade-only` 等 flag |

---

## 🏗️ v2.0.0 — Architecture（远期目标）

**目标**：架构级演进，跳出 macOS 单平台。

| 任务 | 类型 | 描述 |
|---|---|---|
| Linux / X11 移植 | platform | 替换 Raycast、osascript、Swift HUD 为跨平台等价物 |
| Windows 移植 | platform | 同上，可能用 PowerShell + WPF HUD |
| 流式识别 | feat | 用 `faster-whisper` 或 `whisper-streaming` 实现边说边出字 |
| 直接 Unicode 注入 | feat | 用 `CGEventPost` 替代 `pbcopy + ⌘V`，绕开剪贴板污染 |

---

## 💡 想加点别的？

- 新功能/优化 → [Open feature request](https://github.com/aimer1124/local-voice-input/issues/new?template=feature_request.yml)
- 发现 bug → [Open bug report](https://github.com/aimer1124/local-voice-input/issues/new?template=bug_report.yml)
- 想自己实现 → fork 仓库，开 PR，详见 [CONTRIBUTING.md](./CONTRIBUTING.md)

---

## English

This is the public roadmap for **local-voice-input**. Each version maps to a [GitHub Milestone](https://github.com/aimer1124/local-voice-input/milestones), each task to an [Issue](https://github.com/aimer1124/local-voice-input/issues).

Order: **current main → v1.1.0 → v1.2.0 → v2.0.0**. Small fixes can land in patch versions at any time.

### 🚀 v1.1.0 — UX Polish (short term)

Polish from "works" to "feels nice". Reduce friction.

| Task | Type | Description |
|---|---|---|
| Demo GIF/video | docs | 30s end-to-end demo at top of README |
| `vinput --doctor` | feat | One-shot diagnostic: model / mic / permissions / Ollama |
| Configurable HUD | feat | Position / font / color via `vinput.conf`, no recompile |
| TRS headphones bug | bug | macOS routes 3-pole headphones to phantom mic input |
| `vinput --version` | feat | Version flag |

### 📦 v1.2.0 — Onboarding (mid term)

Frictionless install. Remove technical barriers.

| Task | Type | Description |
|---|---|---|
| Homebrew tap | packaging | `brew install aimer1124/tap/local-voice-input` |
| Notarization | security | Apple-notarize HUD binary, skip xattr cleanup |
| First-run wizard | feat | Detect missing Raycast permissions and guide setup |
| `install.sh` flags | feat | `--dry-run`, `--skip-models`, `--upgrade-only` |

### 🏗️ v2.0.0 — Architecture (long term)

Architectural evolution beyond macOS.

| Task | Type | Description |
|---|---|---|
| Linux/X11 port | platform | Replace Raycast/osascript/Swift HUD with cross-platform equivalents |
| Windows port | platform | PowerShell + WPF HUD likely |
| Streaming ASR | feat | `faster-whisper` for real-time partial output |
| Direct Unicode | feat | `CGEventPost` instead of `pbcopy + ⌘V` |

### 💡 Have an idea?

- New feature → [Feature request](https://github.com/aimer1124/local-voice-input/issues/new?template=feature_request.yml)
- Bug → [Bug report](https://github.com/aimer1124/local-voice-input/issues/new?template=bug_report.yml)
- Code contribution → see [CONTRIBUTING.md](./CONTRIBUTING.md)
