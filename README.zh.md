# 🎙️ local-voice-input — 本地 AI 语音 Prompt 输入器

[![CI](https://github.com/aimer1124/local-voice-input/actions/workflows/release.yml/badge.svg)](https://github.com/aimer1124/local-voice-input/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/aimer1124/local-voice-input?color=brightgreen)](https://github.com/aimer1124/local-voice-input/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Apple%20Silicon-lightgrey)](#-系统要求)
[![Roadmap](https://img.shields.io/badge/roadmap-v1.1%20%E2%86%92%20v2.0-blue)](./ROADMAP.md)

> **完全离线** 的程序员专用语音输入工具：按下快捷键说话 → Whisper 转写 → 本地 LLM 提炼意图 → 自动粘贴到光标位置。
>
> _命令行工具名: `vinput`_

**100% 本地运行，音频不出网，无云端依赖，无账号注册。**

[English README](./README.md) · [CHANGELOG](./CHANGELOG.md) · [ROADMAP](./ROADMAP.md) · [Contributing](./CONTRIBUTING.md)

![demo](./assets/demo.gif)

---

## ✨ 核心特性

- 🔒 **完全离线**：Whisper.cpp + Ollama，音频与文本永不上云
- 🧠 **AI 意图重构**：本地 LLM 过滤"呃、那个"等口水词，把碎碎念压成结构化 Prompt
- ⚡ **响应快速**：10 秒中文音频，2–4 秒出文字
- 🎛️ **双模 toggle**：按一下开始 / 再按一下停止，符合直觉
- 🖥️ **多屏感知 HUD**：屏幕中下方毛玻璃悬浮提示，自动跟随鼠标所在屏
- 🎯 **专业术语友好**：可自定义热词词表，编程英文混读不翻车
- 🔌 **零配置可用**：默认中文，开箱即用；同时所有参数均可外置配置

---

## 🎬 工作流程

1. 按快捷键（如 `⌘⇧Space`）→ Pop 提示音 → 🎙️ 录音中
2. 说出你的指令，例如「帮我写一个 Python 函数，读取 CSV 然后过滤掉空行」
3. 再按一次快捷键 → Tink 提示音 → 💭 转写中 → 🤖 AI 润色中
4. ✓ 已完成 —— 光标位置自动出现整理过的 Prompt

效果见上方演示 GIF。

---

## 🧠 整体机制

`voice-input.sh`（Raycast）exec `vinput_bg.sh` 主逻辑：mkdir 原子锁驱动 record/toggle 状态机，
串联 **SoX `rec` → `whisper-cli` → Ollama (qwen) → `pbcopy` + ⌘V**，外层由 45s 硬超时守护进程兜底，
Swift HUD 随各阶段切换提示。

完整架构图、toggle 锁状态机、`USE_VAD` 双模、LLM prompt 设计、UTF-8 编码坑，详见
**[docs/architecture.zh.md](./docs/architecture.zh.md)**。

---

## 📦 安装

### Homebrew Tap（推荐 · v1.1.1+）

```bash
brew tap aimer1124/tap
brew install local-voice-input
vinput setup
```

`vinput setup` 是 Homebrew 包装的"二段式"补全 —— `brew install` 只负责把脚本和 HUD 二进制部署到 `libexec/`，下面这些会在 `vinput setup` 里完成：

1. `brew install sox jq whisper-cpp ollama`（已存在则跳过）
2. 下载 Whisper `large-v3-turbo-q5_0` 模型（~547MB）
3. 把 `vinput / vinput.sh / vinput_bg.sh / hud` 软链到 `~/.whisper_models/`
4. 写入默认配置 `~/.config/vinput.conf` + 热词词表
5. 部署 Raycast 命令脚本到 `~/.config/raycast-scripts/`
6. 启动 Ollama 服务 + 拉取 `qwen3:4b-instruct`（~2.5GB）+ 预热

升级：`brew upgrade local-voice-input`（脚本是 symlink，自动跟随版本）。

### 源码安装（开发者 / 不想用 brew）

```bash
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

`install.sh` 走的是历史路径：自动检查 Homebrew → `brew install` 依赖 → `brew install --cask raycast` → 下载 Whisper 模型 → 编译 / 下载 HUD 二进制 → 复制脚本到 `~/.whisper_models/` → 预热 Ollama。和 `vinput setup` 等价，只是不依赖 brew tap。

支持几个开关（可组合，`--help` 看全部）：

```bash
./install.sh --dry-run        # 只检查环境 + 打印将执行的动作，不下载/不写任何文件
./install.sh --upgrade-only   # 只刷新脚本和 HUD，跳过依赖与模型（升级最快）
./install.sh --skip-models    # 跳过 Whisper(~550MB)+Ollama(~2GB) 下载（离线机用 USB 拷模型）
```

### 手动配置（自动化无法覆盖的部分）

完成 `install.sh` 后，还需要在系统设置里：

1. **隐私 → 麦克风**：勾选 Raycast（首次触发时 sox 会自动弹窗，点允许）
2. **隐私 → 辅助功能**：勾选 Raycast（用于自动 ⌘V 粘贴）
3. **Raycast 设置 → Extensions → Script Commands**
   - Add Script Directory：`~/.config/raycast-scripts`
   - 给 `🎙️ 语音输入` 绑定快捷键（推荐 `⌘⇧Space`）。Raw 和 EN 命令可选，见下方 [模式](#模式三个-raycast-命令)。

> 漏了第 2 步也不会卡死：辅助功能没授权时，转写结果会照常进剪贴板，vinput 会提示
> 「📋 已复制到剪贴板 · 自动粘贴需勾选辅助功能」并**自动帮你打开对应设置面板**，授权
> 后即恢复自动粘贴。授权前手动按 `⌘V` 即可。

### 系统要求

- macOS 13+
- Apple Silicon（M1/M2/M3/M4）
- 16 GB 内存推荐（8 GB 也能跑）
- 3 GB 磁盘空间
- 能用的麦克风（**注意**：纯音乐用的 3 极有线耳机会让 macOS 把输入路由到无信号的耳机口）

---

## 🚀 使用

### 基础用法

1. 把光标点进任意文本框（编辑器、浏览器、聊天窗口都行）
2. 按你设的快捷键（如 ⌘⇧Space）
3. 听到 Pop 音后说话
4. 说完再按一次快捷键
5. 等 2–4 秒，文字自动粘贴到光标位置

### 模式（三个 Raycast 命令）

vinput 提供三个 Raycast 命令，共用同一条流水线（`vinput_bg.sh`），只在 LLM 那步不同。各绑一个快捷键即可：

| 命令 | 快捷键（建议） | LLM 步骤 | 输出 |
|---|---|---|---|
| **🎙️ 语音输入**（默认） | `⌘⇧Space` | 把中文口语提炼成中文书面 prompt | 中文（夹英文） |
| **📝 语音输入 (Raw)** | `⌥Space` | 跳过 | Whisper 转写原文，保留口语原貌 |
| **🌐 语音输入 (EN)** | `⌃⇧Space` | 把中文口语翻译+整形成英文 prompt | 英文 |

> EN 模式仍按 `-l zh` 转写你说的中文，再在 LLM 那步翻译并收紧成简洁的英文指令。它**总是**走 LLM（忽略 `SHORT_TEXT_THRESHOLD`）——否则短中文短语会原样返回中文。

### 性能预算（10 秒中文音频）

| 阶段 | 耗时 |
|---|---|
| 录音 | 你说多久就多久 |
| Whisper 转写 | ~2 s |
| Ollama 润色 | ~1 s（短文本跳过）/ ~2 s（长文本）|
| 粘贴 | < 0.1 s |
| **总额外延迟** | **2–4 秒** |

---

## ⚙️ 配置

配置集中在 `~/.config/vinput.conf`。**设计原则是开箱即用** —— 默认模板只放「大多数人真正会改」的几项，全部带推荐默认值；删掉或留空任意一项都会回退到内置默认，不会报错：

```bash
# === Whisper ASR ===
MODEL_PATH="$HOME/.whisper_models/ggml-large-v3-turbo-q5_0.bin"
WHISPER_LANG="zh"              # 中英混读靠热词 prompt 引导

# === Ollama LLM 润色 ===
OLLAMA_MODEL="qwen3:4b-instruct"
OLLAMA_URL="http://localhost:11434"
OLLAMA_TIMEOUT=15              # LLM 调用超时（秒）；超时则粘贴原始转写而非无限挂起。冷加载慢的机器调大
OLLAMA_WARMUP=1               # 1 = 录音一开始就后台预加载模型，等转写完成时 LLM 已热（消除「第一次录完约 15 秒内开不了新录音」的卡顿）；0 关闭
SHORT_TEXT_THRESHOLD=15        # 短于此字数（中文 1 字=1）跳过 LLM，省 1–2 秒

# === 录音 / 粘贴行为 ===
AUTO_PASTE=1                   # 1=自动 ⌘V（需辅助功能权限），0=只复制
USE_VAD=0                      # 0=纯 toggle（推荐），1=静音自动停（仅安静环境）
MAX_REC_SECONDS=45             # 录音硬超时（秒）
STOP_KILL_GRACE=3              # 按停止后，rec 若 N 秒内没响应 SIGINT（设备 wedge）就强杀
DOUBLE_FIRE_GRACE=0.7          # 录音开始 N 秒内的停止当作 Raycast 重复触发忽略（double-fire 去抖）
SOX_GAIN_DB=-3                 # 小声/远离麦克风调大：+6~+12（负=衰减）

# === 热词词表（可选）===
HOTWORDS_FILE="$HOME/.config/vinput_hotwords.txt"
```

> 想调 Whisper 解码内参、SoX 滤波、动态 prompt、VAD 阈值等？见下方 [进阶配置](#-进阶配置)。这些默认值已针对中文 + 程序员场景调优，一般不用动。

### 热词词表

`~/.config/vinput_hotwords.txt`，每行一个术语，会注入 Whisper prompt 提升识别准确率：

```
API
Promise
async
Playwright
PostgreSQL
...
```

### HUD 样式调整

无需重新编译，在 `~/.config/vinput.conf` 里设置即可，下次触发就生效：

| 配置项 | 默认 | 说明 |
|---|---|---|
| `HUD_Y_PERCENT` | `18` | 距屏幕底部百分比（0=贴底 / 50=正中 / 100=贴顶） |
| `HUD_HEIGHT` | `96` | 窗口高度（像素） |
| `HUD_FONT_SIZE` | `26` | 字号 |
| `HUD_FONT_WEIGHT` | `semibold` | `ultraLight`/`thin`/`light`/`regular`/`medium`/`semibold`/`bold`/`heavy`/`black` |
| `HUD_CORNER_RADIUS` | `20` | 圆角弧度 |
| `HUD_MATERIAL` | `hudWindow` | 毛玻璃风格：`hudWindow`/`sidebar`/`popover`/`menu`/…（详见 `NSVisualEffectView.Material`） |
| `HUD_WIDTH_MIN` | `220` | 自适应宽度下限 |
| `HUD_WIDTH_MAX` | `900` | 自适应宽度上限 |

也支持单次临时覆盖（不动配置文件）：
```bash
HUD_Y_PERCENT=50 HUD_FONT_SIZE=36 ~/.whisper_models/hud "测试样式" 2
```

---

## 🧩 进阶配置

没进默认配置模板的旋钮——Whisper 解码内参、LLM 长内容整形、动态 prompt 上下文、SoX 预处理、
VAD 阈值、HUD 终态/重录、按 App 模式覆盖、剪贴板恢复、锁计时诊断——默认值已针对中文 + 程序员
场景调优，绝大多数人不用动。需要时手动加进 `~/.config/vinput.conf` 即可（留空 = 用内置默认，不会报错）。

完整参考：**[docs/configuration-advanced.zh.md](./docs/configuration-advanced.zh.md)**。改
Whisper/LLM 相关项后请按 [回归测试](#-回归测试pre-tag-必跑) 跑一遍再用。

---

## 🗂️ 项目结构

这套项目有三层，不要把安装后的运行目录当成源码仓库：

- **主源码仓库**：`local-voice-input`（本文档所在仓库），维护脚本、HUD 源码、Raycast 模板、配置模板、测试与 release notes。
- **Homebrew tap 仓库**：`homebrew-tap`，只维护 `Formula/local-voice-input.rb`，指向某个 GitHub tag tarball 和 release 里的 `hud` 二进制。
- **本机运行目录**：`~/.whisper_models`，只放 Whisper 模型和运行入口软链。`vinput setup` 会把 `vinput` / `vinput_bg.sh` / `hud` 链接到这里；不要在这里维护源码副本。

```
vinput/
├── README.md                          # English version（默认）
├── README.zh.md                       # 本文档（中文）
├── LICENSE                            # MIT
├── install.sh                         # 一键安装
├── uninstall.sh                       # 卸载
├── bin/
│   ├── vinput                         # CLI：setup / doctor / history / corrections
│   ├── vinput.sh                      # 前台手动版（终端 Ctrl+C）
│   └── vinput_bg.sh                   # 后台版（Raycast 调用）
├── raycast/
│   ├── voice-input.sh                 # 完整流水线
│   ├── voice-input-raw.sh             # 跳过 LLM
│   └── voice-input-en.sh              # 中文口述 → 英文 prompt
├── src/
│   └── hud.swift                      # 屏幕中央 HUD 源码
├── docs/
│   ├── architecture.zh.md             # 流水线与内部机制详解
│   └── configuration-advanced.zh.md   # 进阶配置旋钮完整参考
├── config/
│   ├── vinput.conf.example            # 配置模板
│   ├── vinput_hotwords.example.txt    # 热词模板
│   └── vinput_corrections.example.tsv # 纠错表模板
├── tests/
│   ├── integration/                   # 无麦克风/无网络 CLI 集成测试
│   ├── llm/                           # Ollama prompt 清理回归
│   └── asr/                           # Whisper 音频样本回归
├── scripts/
│   ├── lint-shell.sh                  # shell 兼容性 lint
│   ├── preflight.sh                   # 发布前确定性检查
│   └── release.sh                     # release/tap 协调脚本
└── assets/                            # 截图/演示资源
```

发布前建议先跑：

```bash
bash scripts/preflight.sh
```

需要同时跑本地 LLM/ASR 回归时：

```bash
RUN_LLM=1 RUN_ASR=1 bash scripts/preflight.sh
```

更新 Homebrew tap 时用 `scripts/release.sh --version X.Y.Z` 做版本和流程检查，再用 `--apply --source-sha ... --hud-sha ...` 写入 tap formula。

---

## 🆚 vs 商用输入法

| 维度 | vinput | 微信/讯飞/豆包 |
|---|---|---|
| 隐私 | ✅ 100% 本地 | ❌ 上传云端 |
| 离线可用 | ✅ | ❌ |
| 专业术语 | ✅ 自定义热词 + LLM 重构 | ⚠️ 通用词库 |
| 意图重构 | ✅ AI 提炼成 Prompt | ❌ 只做转写 |
| 流式输出 | ❌ 必须录完才识别 | ✅ 边说边出字 |
| 任意位置直接输入 | ⚠️ 经剪贴板中转 | ✅ 系统级 IME |
| 候选词/纠错 | ❌ | ✅ |
| 方言支持 | ⚠️ 仅普通话强 | ✅ 几十种方言 |

**最佳定位**：把 vinput 当成 **"AI Prompt 口述按钮"**，跟系统输入法分工 —— vinput 用于写给 Claude/Cursor/ChatGPT 的长 prompt，系统输入法用于聊天/密码/短回复。

---

## 🔧 故障排查

**一键诊断**（推荐先跑这个）：
```bash
~/.whisper_models/vinput --doctor
```
会自动检查有效配置、运行目录、Raycast 命令入口、工具链、资源文件、Ollama 状态、HUD 可用性，并跑一次 3 秒麦克风录音测试，按"健康/偏弱/几乎静音"输出 RMS 值。

只想看配置/入口结构、不碰 Ollama 和麦克风：

```bash
~/.whisper_models/vinput --doctor --quick
~/.whisper_models/vinput config
```

| 症状 | 命令 / 操作 |
|---|---|
| Raycast 没反应 | 检查命令是否出现、快捷键有无冲突 |
| 只复制了没自动粘贴 | 系统设置 → 隐私 → 辅助功能 勾选 Raycast（vinput 会自动提示并打开该面板） |
| 录音失败 | `tail -50 /tmp/vinput_debug.log` |
| 不确定哪里出问题 | `~/.whisper_models/vinput --doctor` |
| 麦克风电平测试 | `rec -q /tmp/t.wav trim 0 3 && sox /tmp/t.wav -n stat \| grep RMS` |
| 默认输入设备 | 系统设置 → 声音 → 输入（用 MacBook Pro Microphone） |
| 卡死的录音 | `pkill -f "rec -q"; rm -rf /tmp/vinput.lock.d` |
| Ollama 没启动 | `brew services start ollama` |
| 说完后结果一直不粘贴 / 卡住 | LLM 这步在等 Ollama。现在会在 `OLLAMA_TIMEOUT`（默认 15s）后超时并改粘贴**原始转写**，不再无限挂起。若经常超时，用 `ollama ps` / `ollama run qwen2.5:3b hi` 查 Ollama；Homebrew 装的 Ollama 若后端损坏（缺 `llama-server`）会让每个请求都卡死——`brew pin ollama` 钉住一个能用的版本。慢机器可调大 `OLLAMA_TIMEOUT`。 |
| HUD 不显示 | `~/.whisper_models/hud "测试" 2` |
| 中文乱码 | 确认脚本含 `export LANG="en_US.UTF-8"` |

---

## 📚 进阶

### 切换更快的 Whisper 模型

| 模型 | 体积 | 速度 | 中文质量 |
|---|---|---|---|
| `ggml-tiny.bin` | 75 MB | 极快 | 差 |
| `ggml-base.bin` | 142 MB | 快 | 一般 |
| `ggml-small.bin` | 466 MB | 中等 | 中等 |
| **`ggml-large-v3-turbo-q5_0.bin`** | **547 MB** | **快** | **强烈推荐** |
| `ggml-large-v3.bin` | 3 GB | 慢 | 最高 |

### 切换更快的 Ollama 模型

| 模型 | 速度 | 润色质量 |
|---|---|---|
| `qwen3:1.7b` | ⚡⚡⚡ | 一般（实测偶发吞词，忠实度回归 6/7） |
| **`qwen3:4b-instruct`** | **⚡⚡** | **平衡（推荐，v1.11.0 起默认；忠实度回归 7/7）** |
| `qwen2.5:3b` | ⚡⚡ | 旧默认（v1.10 及之前），可作回退 |
| `qwen3:8b` | ⚡ | 更强（未实测） |

> ⚠️ qwen3 必须用 **`-instruct`** 变体。不带后缀的 `qwen3:4b` 是思考（thinking）构建，
> 会先生成整段推理再答题——实测热路径直接撞 60s 超时，完全不可用。管线已对所有调用
> 传 `think:false`，但思考构建不吃这个参数。

```bash
ollama pull qwen3:1.7b
# 然后改 ~/.config/vinput.conf 里的 OLLAMA_MODEL="qwen3:1.7b"
```

---

## 📜 转写历史 & 错词挖掘

每次成功转写都会 append 到 `~/.cache/vinput/history.jsonl`（纯本地，纯文本）。

```bash
vinput history                  # 最近 20 条彩色表格
vinput history --tail 100       # 最近 100 条
vinput history --grep qwen      # 搜索（在 raw/corrected/cleaned 三列）
vinput history --raw-only       # 只看原始 Whisper 输出（便于 grep 错词）
```

发现错词后一条命令补进纠错表：

```bash
vinput add-correction "Claude Code" "克劳德 code"
```

也可以让历史帮你挖候选——反复出现、却还没进纠错表的高频英文词，外加哪些已有规则常救场、哪些从未命中可剪枝：

```bash
vinput corrections --suggest            # 扫全部历史
vinput corrections --suggest --tail 200 # 只看最近 200 条
```

只给建议，确认后再用 `vinput add-correction` 落库。

> 隐私：日志只在本地，永不出机。要清空就 `rm ~/.cache/vinput/history.jsonl`。

---

## 🧪 回归测试（pre-tag 必跑）

三层 ASR 流水线 = 三组测试套件 + 一个 lint：

| 层 | 套件 | 命令 | 价值 |
|---|---|---|---|
| Whisper 转写 | [`tests/asr/`](./tests/asr/) | `bash tests/asr/run.sh` | 6 条 TTS 音频 + CER 预算 |
| 谐音纠错 | （数据驱动，无需测） | `vinput corrections` | TSV 即真值 |
| LLM 整形 | [`tests/llm/`](./tests/llm/) | `bash tests/llm/run.sh` | 6 个 case + 必含/绝不含约束 |
| 防御性 | `scripts/lint-shell.sh` | `bash scripts/lint-shell.sh` | grep `$VAR<非ASCII>` set -u 陷阱 |

修改 `bin/vinput_bg.sh`、Whisper/LLM 参数、`config/*` 之前**必须跑**对应层。退出码 0 才能 tag。

> 为什么：v1.1.3 → v1.1.7 四个 hotfix 都是「改了 ASR 参数没回归」的产物。v1.1.5 / v1.1.8 又
> 是 `set -u` 中文括号陷阱。这套基建直接挡掉这两个 bug class。

## 🤝 贡献

欢迎 PR / Issue。建议方向：
- 给回归套件 [tests/asr/](./tests/asr/) 提样本（真人录音、方言、噪声场景）
- Linux/Windows 移植（替换 Raycast、osascript、HUD）
- 流式识别（whisper-streaming / faster-whisper）
- 不依赖剪贴板的直接注入（用 CGEventPost 输入 Unicode）
- 更多语言/方言模型预设

---

## 📄 License

MIT —— 详见 [LICENSE](./LICENSE)

---

## 🙏 致谢

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — Whisper 本地推理
- [Ollama](https://ollama.com/) — 本地 LLM 引擎
- [Qwen](https://github.com/QwenLM/Qwen) — 阿里巴巴开源 LLM
- [Raycast](https://www.raycast.com/) — 现代化 macOS Launcher
- [SoX](http://sox.sourceforge.net/) — 音频录制工具链
