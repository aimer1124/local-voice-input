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

## ✅ 已交付（v1.1 – v1.5）

演示 GIF、`vinput --doctor`、`vinput --version`、HUD 样式可配置、Homebrew tap、谐音纠错表、
`vinput history`、Raw 模式（⌥Space）、动态 prompt、SoX 预处理、回归测试三件套、HUD 终态显示 +
↑ 重录。详见 [CHANGELOG](./CHANGELOG.md)。

---

## 🔜 P0 — 近期（消灭静默失败 & 安装摩擦）

| 任务 | Issue | 准入裁决 | 说明 |
|---|---|---|---|
| 3 极 TRS 耳机录不到声 | [#4](https://github.com/aimer1124/local-voice-input/issues/4) | ✅ **GO** | 唯一开放 bug，且是最伤体验的**静默失败**（准入 #4）。除 doctor 检测外，录音开始时应直接 HUD 告警 |
| 首次启动权限向导 | [#8](https://github.com/aimer1124/local-voice-input/issues/8) | ✅ **GO** | 安装摩擦是第一大易用缺口。检测并引导补齐 麦克风/辅助功能/Raycast。ROI 最高 |
| 文档/默认值一致性 | — | ✅ **已做** | 统一 `SHORT_TEXT_THRESHOLD=15`、修正 HUD 行数/体积、收敛配置模板（2026-05-29） |

## 🟡 P1 — 中期（顺滑度 & 补核心短板）

| 任务 | Issue | 准入裁决 | 说明 |
|---|---|---|---|
| 流式识别（边说边出字） | [#11](https://github.com/aimer1124/local-voice-input/issues/11) | ✅ **GO（拔高）** | 对比表里**唯一标 ❌ 的核心短板**，改的是核心回路（准入 #1），故从远期拔到中期 |
| HUD 二进制 Apple 公证 | [#7](https://github.com/aimer1124/local-voice-input/issues/7) | ✅ **GO** | 去掉"未受信任开发者"弹窗 + xattr 清理，纯安装顺滑度 |
| `install.sh` 开关 | [#9](https://github.com/aimer1124/local-voice-input/issues/9) | ✅ **GO** | `--dry-run`/`--skip-models`/`--upgrade-only`，对老用户友好；非首装关键 |

## 🔵 P2 — 远期（架构 & 扩张）

| 任务 | Issue | 准入裁决 | 说明 |
|---|---|---|---|
| 直接 Unicode 注入（CGEventPost） | [#12](https://github.com/aimer1124/local-voice-input/issues/12) | 🟡 **GO，但谨慎** | 绕开剪贴板污染，真实 UX 收益，但是架构改动，需充分测试与回退路径 |
| Linux / X11 移植 | [#10](https://github.com/aimer1124/local-voice-input/issues/10) | ⏸ **DEFER** | 平台扩张 = 维护成本翻倍（准入 #6）。**核心产品打磨完之前不碰** |
| Windows 移植 | — | ⏸ **DEFER** | 同上 |

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

### ✅ Shipped (v1.1 – v1.5)

Demo GIF, `vinput --doctor`/`--version`, configurable HUD, Homebrew tap, homophone correction table,
`vinput history`, Raw mode (⌥Space), dynamic prompt, SoX preprocessing, regression suites, HUD final
display + ↑-rerun. See [CHANGELOG](./CHANGELOG.md).

### 🔜 P0 — near term

| Task | Issue | Verdict |
|---|---|---|
| TRS headphone phantom-mic bug | [#4](https://github.com/aimer1124/local-voice-input/issues/4) | ✅ GO — only open bug, a silent failure |
| First-run permission wizard | [#8](https://github.com/aimer1124/local-voice-input/issues/8) | ✅ GO — highest-ROI usability fix |
| Doc/default consistency | — | ✅ Done (2026-05-29) |

### 🟡 P1 — mid term

| Task | Issue | Verdict |
|---|---|---|
| Streaming ASR | [#11](https://github.com/aimer1124/local-voice-input/issues/11) | ✅ GO (promoted) — only ❌ in the comparison table; touches the core loop |
| HUD notarization | [#7](https://github.com/aimer1124/local-voice-input/issues/7) | ✅ GO — install smoothness |
| `install.sh` flags | [#9](https://github.com/aimer1124/local-voice-input/issues/9) | ✅ GO — upgrade ergonomics |

### 🔵 P2 — long term

| Task | Issue | Verdict |
|---|---|---|
| Direct Unicode injection | [#12](https://github.com/aimer1124/local-voice-input/issues/12) | 🟡 GO but careful — architectural, needs a fallback path |
| Linux/X11 port | [#10](https://github.com/aimer1124/local-voice-input/issues/10) | ⏸ DEFER — doubles maintenance; not until core is polished |
| Windows port | — | ⏸ DEFER |
