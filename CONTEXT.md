# CONTEXT.md — vinput 领域语言与历史坑档案

> Agent 工作前先读这里。用本表的术语说话，不造同义词；不踩本档案记录过的坑。

## 核心回路术语（Glossary）

| 术语 | 含义 | 别说成 |
|---|---|---|
| **核心回路** | `录音 → Whisper → 谐音纠错 → LLM 提炼 → 粘贴`，唯一主线 | "流水线"（泛指时用） |
| **toggle 锁** | `/tmp/vinput.lock.d`，mkdir 原子目录，同时充当互斥锁 + 状态机 | "锁文件"（它是目录） |
| **双模** | 同一快捷键的两种角色：首次按 = record 模式开始录音；再按 = toggle 模式发 SIGINT 优雅停 | — |
| **Raw 模式** | 跳过 LLM，直接粘 Whisper 转写原文（⌥Space） | "原始模式" |
| **EN 模式** | 中文口述 → LLM 翻译+整形成英文 prompt（⌃⇧Space），永远走 LLM | "英文模式" |
| **HUD** | Swift 编写的屏幕中央毛玻璃悬浮提示（~116KB 单二进制，`/tmp/vinput_hud.pid` 单例） | "弹窗/通知" |
| **热词词表** | `~/.config/vinput_hotwords.txt`，注入 Whisper `--prompt` 提升术语命中率 | "词典" |
| **谐音纠错表** | TSV 纠错规则，`vinput corrections` 管理，数据驱动无需测试 | "替换表" |
| **数字守卫** | 整形后核对转写里的阿拉伯数字是否幸存于 LLM 输出；被吞则回退纠错后原文 + HUD 警告。永远开、无配置 | "token 校验" |
| **忠实度回归** | `tests/llm/` 的 6 case + 必含/绝不含断言套件 | "LLM 测试" |
| **动态 prompt** | `USE_RECENT_PROMPT=1`：最近 N 次成功转写拼进 Whisper `--prompt`，同话题术语命中 +20~40% | "上下文记忆" |
| **VAD 双模** | `USE_VAD=0`（纯 toggle，推荐）/ `=1`（SoX silence 滤波自动停，仅安静环境） | "语音检测" |
| **spool 队列** | 录音/处理解耦的待办设想（issue #42，2026-07-20 已关闭：lock.log 显示忙碌拒绝已随现有锁+去抖+预热机制消失） | — |
| **三层目录** | 主源码仓库 / homebrew-tap / `~/.whisper_models/`（运行目录，勿放源码副本） | — |
| **45s 硬超时** | `MAX_REC_SECONDS=45`，防忘按停的兜底 | — |
| **double-fire 去抖** | `DOUBLE_FIRE_GRACE=0.7s`，忽略 Raycast 重复触发 | — |

## 历史坑档案（Hard-won lessons）

每条都是真实 hotfix 换来的。**改相关代码前重读对应条目。**

### H1. 改 ASR 参数不跑回归 = 连环 hotfix（v1.1.3→v1.1.7）
v1.1.3 调严 `WHISPER_NO_SPEECH_THOLD`（0.6），结果普通麦克风全被判"非语音"；v1.1.6 改回留空（whisper.cpp 默认）。教训固化成 AGENTS.md 测试纪律表：**改任何 Whisper/LLM 参数，先跑 `tests/asr/run.sh` / `tests/llm/run.sh` 再谈提交**。`WHISPER_LOGPROB_THOLD`、`WHISPER_ENTROPY_THOLD`、`WHISPER_MAX_CONTEXT` 同理，实测负面结果已记录在 `tests/asr/README.md`。

### H2. `set -u` + 非 ASCII 字符（v1.1.5 / v1.1.8）
`$VAR<中文括号等非ASCII>` 中，非 ASCII 字符会被并入变量名，`set -u` 下直接炸。规则：变量引用后紧跟非 ASCII 字符时，必须 `"$VAR"` 或 `${VAR}`。`scripts/lint-shell.sh` 专门 grep 这个模式，shell 改动必跑。

### H3. SoX 效果必须 streaming-safe（v1.1.4）
`norm -3` 依赖整流 buffer，导致 rec 收到 SIGINT 时 0 帧输出 → "未识别到有效语音"。v1.1.7 改回固定 `SOX_GAIN_DB`。规则：**所有 SoX 效果必须 streaming-safe**，增益只用固定值。

### H4. Raycast 子进程不继承 LANG
`pbcopy` 把 UTF-8 中文字节按 Latin-1 处理 → 粘贴乱码。规则：凡涉及中文/pbcopy 的脚本，开头 `export LANG="${LANG:-en_US.UTF-8}"`。

### H5. qwen3 必须用 `-instruct` 变体（v1.11.0）
裸 `qwen3:4b` 是 thinking 构建，先生成整段推理再答题，热路径直接撞 60s 超时；且 thinking 构建不吃 `think:false` 参数。默认模型是 `qwen3:4b-instruct`（忠实度回归 7/7）。

### H6. 否定词守卫的失败实验（v1.8.0→v1.8.1）
确定性"否定词守卫"被口语中文（看不懂/能不能/是不是）频繁误触发，回退原文反而丢了标点润色 → v1.8.1 移除，否定保留交回 LLM prompt 硬规则。教训：**确定性守卫只适用于数字这类无歧义 token；语义判断别用正则硬挡**。数字守卫（H 对立面）因此保留。

### H7. 长音频解码逃生舱无效
`WHISPER_ENTROPY_THOLD` / 调小 `WHISPER_MAX_CONTEXT` / `WHISPER_CARRY_PROMPT=1` 对长音频实测零增益甚至更差。这些参数留空 = whisper.cpp 默认，别当"调优旋钮"推荐给 agent 实验。

## 使用数据基线（决策依据）

212 条实测（2026-05-29 → 07-06）：70% full 模式、4% 数字守卫回退、长度 p50=25 / p90=81 字。ROADMAP 活跃 backlog 由这些数据驱动——提议功能时先问"数据支持吗"，不靠想象。
