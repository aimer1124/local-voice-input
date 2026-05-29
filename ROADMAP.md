# Roadmap

> 中文 | [English ↓](#english)

本文档为 **local-voice-input** 的公开开发路线图。每个待办项对应一个 [Issue](https://github.com/aimer1124/local-voice-input/issues)。

> 最后一次全量评审：**2026-05-29（v1.5.0）**。优先级按下方[功能准入门槛](#功能准入门槛)重排——能消灭**静默失败**和**安装摩擦**的事项最优先，平台扩张最后。

---

## 🎯 北极星

**一个按钮的本地口述器**：按快捷键 → 说话 → 干净的 prompt 自动粘到光标。
唯一核心回路 = 录音 → Whisper → 纠错 → LLM 提炼 → 粘贴。其余皆为配角，只在不拖累核心回路时存在。

---

## 功能准入门槛

每个新功能 / issue 立项前过这 7 条：

1. **核心回路优先**——是否让核心回路更快/更稳/更少步骤？配角必须默认关、默认不可见。
2. **零配置优先**——带合理默认；不往默认配置模板加旋钮，除非过半用户会动。
3. **不为便利功能加系统权限**——必须加时默认关 + 缺权限优雅降级。
4. **零静默失败**——每条失败路径都有 HUD 或 `vinput --doctor` 可见提示。
5. **每个表面都有成本**——CLI ≤ ~8 命令、默认配置 ≤ ~8 项；加一个要删一个或书面论证。
6. **先打磨单平台**——平台移植排在核心打磨之后。
7. **改 ASR/LLM 参数必过回归套件再 tag**（tests/asr、tests/llm、scripts/lint-shell.sh）。

---

## ✅ 已交付

**v1.1 – v1.5**：演示 GIF、`vinput --doctor`/`--version`、HUD 样式可配置、Homebrew tap、谐音纠错表、
`vinput history`、Raw 模式（⌥Space）、动态 prompt、SoX 预处理、回归测试三件套、HUD 终态显示 + ↑ 重录。

**v1.6.0（2026-05-29）— UX & onboarding 一波**：把三处「失败了看不懂为啥」的静默失败逐一变成可操作提示。
- [#4](https://github.com/aimer1124/local-voice-input/issues/4) 麦克风静默失败 → 按 RMS 电平给可操作诊断
- [#8](https://github.com/aimer1124/local-voice-input/issues/8) 辅助功能权限缺失 → 引导而非静默粘贴失败
- [#9](https://github.com/aimer1124/local-voice-input/issues/9) `install.sh` 加 `--dry-run`/`--skip-models`/`--upgrade-only`
- 配置模板收敛 + 文档/默认值对齐

详见 [CHANGELOG](./CHANGELOG.md)。**P0（静默失败 + 安装摩擦）已清零。**

---

## 决策回顾（2026-05-29）

P0 清零后复盘剩余项时，在[功能准入门槛](#功能准入门槛)之上再加一层**价值-成本尺**：命中下面任一条就砍掉或暂缓——
宁可保持精简，也不为「看起来该有」的功能付经常性成本或牺牲强项：

- (a) 市场已有大量**免费替代** → 边际价值低；
- (b) 与本产品**强项冲突** → 得不偿失；
- (c) 带来**经常性费用** → 对免费 OSS 工具是真负担；
- (d) **维护成本翻倍**。

## 🅧 暂不做

| 任务 | Issue | 裁决 | 理由 |
|---|---|---|---|
| 流式识别（边说边出字） | [#11](https://github.com/aimer1124/local-voice-input/issues/11) | ❌ **暂不做** | 命中 (a)+(b)：免费流式输入法遍地；且流式与我们的 **LLM 意图重构冲突**——重构必须等整句说完，流式只省掉 Whisper 的 ~2s、省不掉 LLM，还牺牲全段解码的准确率。要做也只该限定 Raw 模式，优先级极低 |

## ⏸ 暂缓

| 任务 | Issue | 裁决 | 理由 |
|---|---|---|---|
| HUD 二进制 Apple 公证 | [#7](https://github.com/aimer1124/local-voice-input/issues/7) | ⏸ **暂缓** | 命中 (c)：**唯一要 Apple Developer $99/年**的项，且**非阻塞**——quarantine 已用 `install.sh` 的 `xattr -d` + 有 swiftc 时本地编译（产物无 quarantine）绕过。仅当①已有付费开发者账号 或 ②真有用户反馈 Gatekeeper 挡路 才做。免费替代：引导走本地 swiftc 编译 |
| Linux / X11 / Windows 移植 | [#10](https://github.com/aimer1124/local-voice-input/issues/10) | ⏸ **DEFER** | 命中 (d)：Raycast/osascript/Swift HUD 全是 macOS 原生，移植 = 维护翻倍。无费用，合法的 someday |

## 🔵 低优先 backlog

| 任务 | Issue | 裁决 | 理由 |
|---|---|---|---|
| 直接 Unicode 注入（CGEventPost） | [#12](https://github.com/aimer1124/local-voice-input/issues/12) | 🟡 **保留，不紧急** | 唯一真实收益是不污染剪贴板；但 CGEventPost 合成按键同样需辅助功能权限、不省权限面。无费用、少量原生代码成本 |

> **下一步**：v1.6.0 后产品处于干净状态，优先**观察实际用户反馈再定方向**，而非继续堆功能。

---

## 💡 想加点别的？

- 新功能/优化 → [Open feature request](https://github.com/aimer1124/local-voice-input/issues/new?template=feature_request.yml)（会先过上面 7 条门槛）
- 发现 bug → [Open bug report](https://github.com/aimer1124/local-voice-input/issues/new?template=bug_report.yml)
- 想自己实现 → fork 仓库开 PR，详见 [CONTRIBUTING.md](./CONTRIBUTING.md)

---

## English

Public roadmap for **local-voice-input**. Last full review: **2026-05-29 (v1.5.0)**. Priorities are
re-ordered by the [feature gate](#功能准入门槛) below — items that kill **silent failures** and
**install friction** come first; platform expansion comes last.

### 🎯 North star

A **one-button local dictation tool**: hotkey → speak → clean prompt pasted at the cursor.
The only core loop = record → Whisper → corrections → LLM polish → paste. Everything else is a
supporting act that exists only while it doesn't slow the core loop.

### Feature gate (7 rules)

1. **Core loop first** — does it make the core loop faster / more reliable / fewer steps? Side
   features default OFF and invisible.
2. **Zero-config first** — ship a sane default; don't add a knob to the default config template
   unless most users will touch it.
3. **No new permission for convenience features** — if required, default OFF and degrade gracefully.
4. **No silent failures** — every failure path surfaces a HUD or `vinput --doctor` message.
5. **Every surface has a cost** — CLI ≤ ~8 commands, default config ≤ ~8 knobs; add one, remove one
   or justify it.
6. **Polish one platform first** — ports come after the core is done.
7. **ASR/LLM param changes must pass the regression suites before tagging.**

### ✅ Shipped

**v1.1 – v1.5**: Demo GIF, `vinput --doctor`/`--version`, configurable HUD, Homebrew tap, homophone
correction table, `vinput history`, Raw mode (⌥Space), dynamic prompt, SoX preprocessing, regression
suites, HUD final display + ↑-rerun.

**v1.6.0 (2026-05-29)** — turned three silent failures into actionable hints: #4 silent-mic
diagnosis, #8 accessibility-perm guide, #9 `install.sh` `--dry-run`/`--skip-models`/`--upgrade-only`,
plus config-template slimming + doc alignment. **P0 cleared.** See [CHANGELOG](./CHANGELOG.md).

### Decision review (2026-05-29)

On top of the [feature gate](#功能准入门槛), a **value-vs-cost** filter — cut or defer if it hits any of:
(a) plenty of free alternatives → low marginal value; (b) conflicts with our strength; (c) recurring
fee → real burden for a free OSS tool; (d) doubles maintenance.

### 🅧 Won't do (for now)

| Task | Issue | Verdict |
|---|---|---|
| Streaming ASR | [#11](https://github.com/aimer1124/local-voice-input/issues/11) | ❌ Hits (a)+(b): free streaming IMEs everywhere; streaming conflicts with our **LLM intent-reshape** (must wait for the full utterance — streaming only saves Whisper's ~2s, not the LLM, and costs accuracy). Only worth it inside Raw mode; very low priority |

### ⏸ Deferred

| Task | Issue | Verdict |
|---|---|---|
| HUD notarization | [#7](https://github.com/aimer1124/local-voice-input/issues/7) | ⏸ Hits (c): the **only $99/yr** item, and **non-blocking** — quarantine already worked around (`xattr -d` + local swiftc build). Do it only if you already have a paid dev account, or users actually hit Gatekeeper |
| Linux / X11 / Windows port | [#10](https://github.com/aimer1124/local-voice-input/issues/10) | ⏸ DEFER — hits (d): Raycast/osascript/Swift HUD are all macOS-native; a port doubles maintenance |

### 🔵 Low-priority backlog

| Task | Issue | Verdict |
|---|---|---|
| Direct Unicode injection | [#12](https://github.com/aimer1124/local-voice-input/issues/12) | 🟡 Kept, not urgent — only real win is not clobbering the clipboard; CGEventPost still needs Accessibility. No fee, small native cost |

> **Next**: product is in a clean state after v1.6.0 — watch real user feedback before adding more, rather than piling on features.
