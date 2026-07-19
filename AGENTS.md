# AGENTS.md — vinput (local-voice-input) 项目宪法

> 任何 coding agent（omp / Claude Code / Codex）在本仓库工作前**必读**。本文件是约束，不是建议。

## 一句话定位

**一个按钮的本地口述器**：按快捷键 → 说话 → 干净的 prompt 自动粘到光标。100% 本地运行，音频不出网。

## 北极星与核心回路

唯一核心回路 = `录音 → Whisper → 谐音纠错 → LLM 提炼 → 粘贴`。其余一切皆配角，只在**不拖累核心回路**时存在。任何让核心回路变慢/变脆/变多步骤的改动，默认拒绝。

## 功能准入 7 条门槛（提方案前必自查）

1. **核心回路优先**——是否让核心回路更快/更稳/更少步骤？配角功能必须默认关、默认不可见。
2. **零配置优先**——带合理默认值；不往默认配置模板加旋钮，除非过半用户会动。
3. **不为便利功能加系统权限**——必须加时默认关 + 缺权限优雅降级。
4. **零静默失败**——每条失败路径都要有 HUD 或 `vinput --doctor` 可见提示。
5. **每个表面都有成本**——CLI ≤ ~8 命令、默认配置 ≤ ~8 项；加一个要删一个或书面论证。
6. **先打磨单平台**——macOS only，平台移植排在核心打磨之后。
7. **改 ASR/LLM 参数必过回归套件再 tag**（见下"测试纪律"）。

## 已定决策黑名单（勿翻案）

以下方向 ROADMAP 已正式裁决**暂不做**，提方案时不要重新提议（除非用户明确要求重开讨论）：

- ❌ **流式识别**（边说边出字）——与 LLM 意图重构冲突；免费替代品遍地
- ❌ **跨平台移植**（Linux/Windows）——Raycast/osascript/Swift HUD 全是 macOS 原生，移植 = 维护翻倍
- ❌ **GUI 化**、**屏幕上下文感知**、**语音命令**
- ⏸ **HUD 二进制 Apple 公证**——唯一要 $99/年的项，quarantine 已有绕行方案

## 硬技术约束

- **Bash 3.2 兼容**：macOS 自带 bash 3.2，禁用 bash 4+ 特性（关联数组、`mapfile`、`|&` 等）
- **`set -u` + 非 ASCII 陷阱**：`$VAR<中文括号等非ASCII字符>` 会被当成变量名一部分而炸（v1.1.5/v1.1.8 教训）；变量引用紧跟非 ASCII 字符时必须加引号或大括号
- **UTF-8 强制**：涉及 `pbcopy`/中文文本的脚本必须 `export LANG="${LANG:-en_US.UTF-8}"`（Raycast 子进程不继承 Terminal 的 LANG）
- 运行环境：macOS 13+ / Apple Silicon / 依赖 `sox` `whisper-cpp` `ollama` `jq`

## 测试纪律（红线）

本项目的"测试"= **bash 驱动的样本回归**，不是单元测试框架。TDD 在这里的含义 = 先加失败样本/断言（red），再修实现（green），再清理（refactor）。

**文件 → 必跑套件映射**：

| 改动范围 | 必跑 |
|---|---|
| `bin/vinput_bg.sh` / Whisper 参数 / 热词逻辑 | `bash tests/asr/run.sh` + `bash scripts/lint-shell.sh` |
| LLM prompt / `OLLAMA_MODEL` / 纠错逻辑 | `bash tests/llm/run.sh` + `bash scripts/lint-shell.sh` |
| 任何 `.sh` / `bin/*` | `bash scripts/lint-shell.sh` |
| `config/*` / README 配置段 | `bash scripts/preflight.sh`（内含 check-docs） |
| **打 tag 前** | `RUN_LLM=1 RUN_ASR=1 bash scripts/preflight.sh` 全量，退出码必须 0 |

历史教训：v1.1.3→v1.1.7 四个 hotfix 全是「改了 ASR 参数没跑回归」的产物。不要重蹈。

**Agent 自述验证结果不可信（2026-07-19 #49 pilot 教训）**：实现 agent 曾误删 `append_history()` 整个函数、把脚本改出语法错误（`bash -n` 都过不了），却报告「lint 通过、6/6 测试通过」——验证命令根本没有执行。由此立规：

- Agent 声称跑过的任何验证，必须附带真实命令输出与退出码；只有结论没有输出 = 视同未执行
- 编排方（人或另一个 agent）每轮改动后必须**外部**复跑 `bash -n <改动脚本>` + `bash scripts/lint-shell.sh`，并亲自审 `git diff`（重点看删除行：新增功能的 diff 出现大段删除即红灯），不得采信执行方自述
- 版本 bump 时 `tests/integration/run.sh` 的版本断言会红，这是有意设计——同步更新断言，别绕过

## 性能预算

10 秒中文音频总额外延迟 **2–4 秒**（Whisper ~2s + LLM ~1–2s + 粘贴 <0.1s）。热路径（`bin/vinput_bg.sh` 主流程）上的任何新增开销都必须可测量且可关。`OLLAMA_WARMUP=1` 与 `keep_alive=30m` 是延迟关键，不可随意改动。

## Dev loop 与文档纪律

- 改完脚本：`cp bin/vinput_bg.sh ~/.whisper_models/vinput_bg.sh` 后用真实快捷键实测（回归套件之外的人工验收）
- **新增配置旋钮**（`FOO="${FOO:-default}"`）必须同步文档（README 配置段或 `config/vinput.conf.example`），否则 `scripts/check-docs.sh`（preflight 一部分）失败；刻意内部的变量进该脚本的 `INTERNAL_ALLOWLIST` 并附一行理由
- Commit 遵循 **Conventional Commits**：`feat|fix|docs|refactor|perf|ci|chore(<scope>): <subject>`
- CHANGELOG 遵循 Keep a Changelog，发布走 `scripts/release.sh --version X.Y.Z`

## 三层目录结构（勿混淆）

1. **主源码仓库**（本目录）——脚本、HUD 源码、模板、测试
2. **homebrew-tap 仓库**——只有 `Formula/local-voice-input.rb`
3. **本机运行目录 `~/.whisper_models/`**——模型 + 运行入口软链；**不要在这里维护源码副本**

## Agent skills

### Issue tracker

GitHub Issues（`aimer1124/local-voice-input`），`gh` CLI 全权操作；标题沿用 `功能：`/`修复：` 前缀惯例。See `docs/agents/issue-tracker.md`.

### Triage labels

五状态标签（`needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`）与领域标签正交共存。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目录 `CONTEXT.md` + `docs/adr/`；`ROADMAP.md` 兼具决策日志效力。See `docs/agents/domain.md`.

### 已安装的 skills（.claude/skills/）

- **编排型（用户触发）**：`grill-with-docs`（对齐需求+沉淀文档）→ `to-spec`（生成 spec 发 issue）→ `to-tickets`（拆 tracer-bullet 任务）→ `implement`（驱动实现）；`triage`（issue 状态机）；`improve-codebase-architecture`（定期架构扫描）；`setup-matt-pocock-skills`（本仓库已配置完成，勿再跑）
- **纪律型（agent 自动引用）**：`tdd`（red-green-refactor，按上文 shell 语境适配）、`diagnosing-bugs`（复现→最小化→假设→插桩→修复→回归）

工作流约定：新需求从 `grill-with-docs` 开始，禁止跳过对齐直接写码；实现类工作以 `implement` 收口，提交前必过"测试纪律"表。
