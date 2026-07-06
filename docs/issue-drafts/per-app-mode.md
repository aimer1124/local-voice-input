# 功能：按前台 App 轻量自适应模式（默认关）

> issue 草稿 — 审阅后用 `gh issue create --title "..." --body-file <本文件>` 发布，发布后可删除本文件。

## 背景

同类项目（VoiceInk、whisper-local、local-whisper）普遍支持按前台 App 切换行为（如终端里不加句首大写）。对 vinput 最有价值的裁剪版：**在终端类 App 里自动走 Raw 模式**——终端里通常要的是命令原文，LLM 意图重构反而碍事。

## 方案草案（最小面）

- 粘贴前已有 osascript 调用链；录音启动时用 `osascript` 取前台 App bundle id（零新权限，System Events 已在用）；
- 命中用户配置文件（如 `~/.config/vinput_app_modes.tsv`，格式 `bundle-id<TAB>mode`）时覆盖本轮模式；
- **默认关**：配置文件不存在 = 行为零变化；不进默认配置模板，README 进阶节文档化。

## 门槛自查（ROADMAP 7 条）

1. 核心回路更少步骤（免手动切 Raw 快捷键）✅ 2. 零配置默认关 ✅ 3. 零新权限 ✅ 4. 无静默失败面（miss = 走默认模式）✅ 5. 不加默认模板旋钮 ✅ 6. 单平台 ✅ 7. 不动 ASR/LLM 参数 ✅

## 备选考虑

- 取前台 App 应发生在**录音启动时**而非粘贴时——用户说话期间切窗口的意图以「按下快捷键那一刻」为准。
- 失败（osascript 超时/空）→ 静默回退默认模式，不打扰。
