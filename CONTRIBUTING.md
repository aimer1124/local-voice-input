# Contributing to local-voice-input

> English | [中文 ↓](#中文)

Thanks for your interest in **local-voice-input**!

## 🛠️ Local development

### Setup

```bash
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

### Dev loop

```bash
# 1. Edit bin/vinput_bg.sh or src/hud.swift
vim bin/vinput_bg.sh

# 2. Deploy to the runtime location
cp bin/vinput_bg.sh ~/.whisper_models/vinput_bg.sh
swiftc -O src/hud.swift -o ~/.whisper_models/hud

# 3. Trigger a test
~/.whisper_models/vinput_bg.sh
# Or press your Raycast hotkey
```

### Debugging

```bash
tail -f /tmp/vinput_debug.log               # background script logs
pgrep -lf "vinput|rec -q|ollama"            # rec / Ollama / Whisper process tree
~/.whisper_models/hud "test message" 2      # standalone HUD test
```

### Adding a config option

Docs are hand-maintained, so when you add a `FOO="${FOO:-default}"` knob to `bin/vinput_bg.sh`,
document it in README's Configuration section, in [docs/configuration-advanced.md](./docs/configuration-advanced.md)
(+ its `.zh.md` counterpart), or in `config/vinput.conf.example` — otherwise `scripts/check-docs.sh`
(run by `scripts/preflight.sh`) fails. Deliberately internal/debug-only vars go on that script's
short `INTERNAL_ALLOWLIST` with a one-line reason.

## 📝 Commit style

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>
```

`<type>` values:
- `feat`: a new feature
- `fix`: a bug fix
- `docs`: documentation
- `refactor`: refactoring
- `perf`: performance
- `ci`: CI/CD changes
- `chore`: chores (dependency bumps, config, etc.)

Example:
```
feat(hud): make position configurable via vinput.conf

Adds HUD_Y_OFFSET_PERCENT to vinput.conf. The Swift binary now reads
an env var passed by vinput_bg.sh instead of being recompiled.
```

## 🔀 PR flow

1. Fork → create a branch on your fork: `git checkout -b feat/something`
2. Commit (following the format above)
3. Push to your fork
4. Open a Pull Request against `main` on GitHub
5. In the PR description include: **what** you did, **why**, and **how to verify**

## 🚀 Release process (maintainers only)

See [docs/RELEASE_TEMPLATE.md](./docs/RELEASE_TEMPLATE.md). Short version:

```bash
# 1. Copy the bilingual notes template and fill it in
cp docs/RELEASE_TEMPLATE.md /tmp/notes-vX.Y.Z.md
# Edit...

# 2. Create the release (also pushes the tag, triggering CI)
gh release create vX.Y.Z \
    --title "vX.Y.Z — short title" \
    --notes-file /tmp/notes-vX.Y.Z.md \
    --target main

# 3. ~20s later CI auto-builds hud + hud.sha256 and uploads them
```

## 🎬 Contributing the demo GIF

The README demo GIF is compressed by [`scripts/make-demo-gif.sh`](./scripts/make-demo-gif.sh). Full workflow:

1. Use macOS **⇧⌘5** to record ("Record Selected Portion"), framing a 1200×675 region
2. Inside the recorded area, perform a full vinput demo:
   - Click your cursor into a text field
   - Press ⌘⇧Space → wait for the Pop sound → speak a sentence (e.g., "write me a Python function that reads a CSV and filters out empty rows")
   - Press ⌘⇧Space again → wait for the Tink sound → HUD transitions → text appears
3. Stop recording and move the generated mov to `/tmp/demo.mov`
4. Run the converter:
   ```bash
   ./scripts/make-demo-gif.sh
   ```
5. Output goes to `assets/demo.gif`, auto-validated to be ≤ 5MB
6. If too large, tune params and re-run:
   ```bash
   FPS=10 WIDTH=900 QUALITY=70 ./scripts/make-demo-gif.sh
   ```
7. Once happy, commit `assets/demo.gif` and add `![demo](./assets/demo.gif)` to the README top

## 🐛 Reporting bugs

Please report bugs via [GitHub Issues](https://github.com/aimer1124/local-voice-input/issues/new/choose). The issue template will ask for:
- macOS version + chip
- vinput version (`git rev-parse HEAD` or the release tag)
- Recent content of `/tmp/vinput_debug.log`
- Reproduction steps

## 💡 Feature requests

Like bug reports, use the "Feature request" issue template. Please explain:
- What problem you want solved
- The behavior you expect
- (Optional) an implementation idea

---

## 中文

> [English ↑](#contributing-to-local-voice-input)

感谢你对 **local-voice-input** 的兴趣！

### 🛠️ 本地开发

#### 环境准备

```bash
# 克隆并跑安装脚本部署一份可用环境
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

#### 开发循环

```bash
# 1. 改 bin/vinput_bg.sh 或 src/hud.swift
vim bin/vinput_bg.sh

# 2. 部署到运行位置
cp bin/vinput_bg.sh ~/.whisper_models/vinput_bg.sh
swiftc -O src/hud.swift -o ~/.whisper_models/hud

# 3. 触发测试
~/.whisper_models/vinput_bg.sh
# 或按你绑定的 Raycast 快捷键
```

#### 调试技巧

```bash
# 查看后台脚本日志
tail -f /tmp/vinput_debug.log

# 看 rec / Ollama / Whisper 链路状态
pgrep -lf "vinput|rec -q|ollama"

# 单独测 HUD
~/.whisper_models/hud "test message" 2
```

### 📝 提交规范

使用 [Conventional Commits](https://www.conventionalcommits.org/) 风格：

```
<type>(<scope>): <subject>

<body>
```

`<type>` 取值：
- `feat`: 新功能
- `fix`: 修 bug
- `docs`: 文档
- `refactor`: 重构
- `perf`: 性能优化
- `ci`: CI/CD 改动
- `chore`: 杂项（依赖升级、配置等）

示例：
```
feat(hud): make position configurable via vinput.conf

Adds HUD_Y_OFFSET_PERCENT to vinput.conf. The Swift binary now reads
an env var passed by vinput_bg.sh instead of being recompiled.
```

### 🔀 PR 流程

1. Fork → 在你的 fork 上建分支：`git checkout -b feat/something`
2. 提交（遵循上面的格式）
3. 推到你的 fork
4. 在 GitHub 上发 Pull Request 到 `main`
5. PR 描述里包含：**做了什么**、**为什么这么做**、**怎么验证**

### 🚀 发版流程（仅维护者）

详见 [docs/RELEASE_TEMPLATE.md](./docs/RELEASE_TEMPLATE.md)。简版：

```bash
# 1. 复制双语 notes 模板填写
cp docs/RELEASE_TEMPLATE.md /tmp/notes-vX.Y.Z.md
# 编辑...

# 2. 创建 release（同时推 tag，触发 CI）
gh release create vX.Y.Z \
    --title "vX.Y.Z — short title" \
    --notes-file /tmp/notes-vX.Y.Z.md \
    --target main

# 3. CI 约 20 秒后自动 build hud + hud.sha256 并上传
```

### 🎬 贡献演示 GIF

README 顶部的演示 GIF 由 [`scripts/make-demo-gif.sh`](./scripts/make-demo-gif.sh) 处理压缩。完整工作流程：

1. 用 macOS 自带 **⇧⌘5** 录屏（"Record Selected Portion"），框选 1200×675 区域
2. 在录制范围里完整演示 vinput：
   - 把光标点进文本框
   - 按 ⌘⇧Space → 等 Pop 音 → 说一句话（如"帮我写一个 Python 函数读取 CSV 然后过滤掉空行"）
   - 再按 ⌘⇧Space → 等 Tink 音 → HUD 切换 → 文字自动出现
3. 停止录制，把生成的 mov 文件移动到 `/tmp/demo.mov`
4. 跑转换脚本：
   ```bash
   ./scripts/make-demo-gif.sh
   ```
5. 输出 `assets/demo.gif`，自动校验大小 ≤ 5MB
6. 大了就调参重跑：
   ```bash
   FPS=10 WIDTH=900 QUALITY=70 ./scripts/make-demo-gif.sh
   ```
7. 满意后 commit `assets/demo.gif` 并把 README 顶部加上 `![demo](./assets/demo.gif)`

### 🐛 报告 Bug

请通过 [GitHub Issues](https://github.com/aimer1124/local-voice-input/issues/new/choose) 报告 bug。issue 模板会要求你提供：
- macOS 版本 + 芯片
- vinput 版本（`git rev-parse HEAD` 或 release tag）
- `/tmp/vinput_debug.log` 最近内容
- 复现步骤

### 💡 提交功能建议

跟报 bug 类似，用 issue 模板里的 "Feature request"。请说明：
- 你希望解决什么问题
- 你期望的行为
- （可选）实现思路
