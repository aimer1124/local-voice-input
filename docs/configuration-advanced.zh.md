# 进阶配置

> [English](./configuration-advanced.md) · 返回 [README](../README.zh.md#-进阶配置)

下面这些**没有放进默认配置模板**，因为默认值已针对中文 + 程序员场景调优，绝大多数人不用动。
需要时手动加进 `~/.config/vinput.conf` 即可（留空 = 用内置默认，不会报错）。改 Whisper/LLM
相关项后请按 [回归测试](../README.zh.md#-回归测试pre-tag-必跑) 跑一遍再用。

## Whisper 解码内参

```bash
WHISPER_THREADS=8             # 推理线程数
WHISPER_ZH_SIMPLIFY=1         # 繁→简归一（依赖可选安装的 opencc）。Whisper -l zh 只选语言分支、不选字形——large-v3 系模型常在 -l zh 下吐繁体字形，跟口音/用词无关。设 0 保留繁体输出（如 Taiwan/HK 用户）。对已是简体/非中文文本天然幂等；未装 opencc 时静默降级为不转换（vinput --doctor 会提示安装）
WHISPER_BEAM_SIZE=5           # beam search 路数，减少同音字误选；延迟 +0.5s
WHISPER_TEMPERATURE_INC=0.2   # 温度递增步长，失败时温度采样兜底防吐空
# WHISPER_TEMPERATURE=0       # 起始温度，留空=whisper.cpp 默认
# WHISPER_NO_SPEECH_THOLD=0.6 # 越小越严。⚠️ v1.1.3 调严后普通麦全判"非语音"，v1.1.6 改回默认(留空)
# WHISPER_LOGPROB_THOLD=-1.0  # 越接近 0 越严。同上，仅 doctor 显示信号偏弱时再考虑

# 长音频解码逃生舱（留空=whisper.cpp 默认）。⚠️ 实测对长音频样本零增益，把 --max-context 调小反而更差。
# 仅供手动实验；改前先看 tests/asr/README.md 里的负面结果表。
# WHISPER_ENTROPY_THOLD=       # 留空 = whisper.cpp 默认 (2.40)
# WHISPER_MAX_CONTEXT=         # 留空 = whisper.cpp 默认 (-1)；设小实测更差
# WHISPER_CARRY_PROMPT=0       # 1 = 每个 30s 窗口都重注入 prompt；实测无增益
```

## LLM 整形（长内容）

```bash
LONG_TEXT_THRESHOLD=80   # 转写字数 ≥ 此值（中文 1 字=1）时，LLM 从「提炼成一句」切到
                         # 「整理+保结构、不摘要、不丢内容」的长内容模板
```

短句仍走原来的提炼器。一旦转写达到 `LONG_TEXT_THRESHOLD`，LLM 改用保结构的长内容模板——一段多点口述会保留成多点列表，而不是被压成一句、丢掉细节。

整形之后（常规模式与 EN 模式都生效），一道确定性的**关键 token 丢失守卫**会核对：转写里的阿拉伯数字是否在 LLM 输出里仍然存在（例如「删那 5 个按钮」不能变成「删那些按钮」）。若数字被静默吞掉，则改粘**纠错后的原始转写**并在 HUD 给警告。守卫始终开、绝不覆盖忠实的改写、无需配置。（1.8.0 曾有否定词守卫，1.8.1 移除：口语中文「看不懂 / 能不能 / 是不是」会频繁误触发、回退原文丢掉标点与润色；否定保留交回 LLM prompt 硬规则。）

## 动态 Prompt 上下文

把最近 N 次成功转写拼到 Whisper `--prompt` 前，给模型「短期记忆」。实测连续聊同一话题时专有名词命中率 +20~40%。

```bash
USE_RECENT_PROMPT=1
RECENT_PROMPT_COUNT=5
RECENT_PROMPT_FILE="$HOME/.cache/vinput/recent.txt"
RECENT_PROMPT_MAX_CHARS=280
```

## SoX 录音预处理

> ⚠️ 所有效果必须 streaming-safe（不能依赖整流 buffer）。v1.1.4 用过 `norm -3`，导致 rec 在 SIGINT 时 0 帧输出 → "未识别到有效语音"。v1.1.7 改回固定 gain。

```bash
USE_SOX_PREPROCESS=1
SOX_HIGHPASS=80     # 切低频：风扇 / 街道嗡嗡声
SOX_LOWPASS=8000    # 切高频：嘶嘶声 / 抖动
SOX_GAIN_DB=-3      # 固定增益（已在基础配置，此处列全）
REC_WARMUP_MS=150   # rec 启动后等 buffer 就绪再提示说话，避免首字丢失
```

## VAD 阈值（仅 `USE_VAD=1` 时生效）

```bash
SILENCE_TAIL=1.5
SILENCE_START_THRESHOLD="0.5%"
SILENCE_STOP_THRESHOLD="6%"
```

## HUD 终态显示 & ↑ 重录

```bash
# HUD_SHOW_RESULT=1       # 粘贴后 HUD 显示真正粘贴的内容（截断 60 字）
# HUD_FINAL_DURATION=2.5  # 终态停留秒数
# HUD_RERUN_ON_UP=0       # 1=终态显示期间按 ↑ 立即重跑一次完整流水线（ESC 永远立即关闭）
# HUD_CANCEL_ON_ESC=1     # 0=关闭。录音期间 1 秒内连按两次 ESC 丢弃本轮：不转写、不粘贴、立刻可重录
```

> `HUD_RERUN_ON_UP=1` 与 ESC 取消都需在**系统设置 → 隐私 → 输入监控**给 hud 二进制（路径见 `vinput --doctor`）打勾。
> 没给权限时 HUD 仍正常显示，只是按键无效——便利功能，优雅降级。

HUD 外观（位置/字号/材质等 8 项）见 README 的 [HUD 样式调整](../README.zh.md#hud-样式调整)。

## 按 App 模式覆盖

按下快捷键那一刻，根据前台 App 自动切换模式——典型用法：终端里要命令原文，自动走 Raw（跳过 LLM 意图重构）。默认关闭：映射文件存在才生效。

```bash
APP_MODES_FILE="$HOME/.config/vinput_app_modes.tsv"   # 每行「bundle-id<TAB>mode」，mode ∈ raw|en
```

把 `config/vinput_app_modes.example.tsv` 复制过去，把你在用的终端取消注释即可。查某个 App 的 bundle id：先切到前台，再跑 `lsappinfo info -only bundleid "$(lsappinfo front)"`。探测用 `lsappinfo`——零新权限、~10ms、不拖慢录音起步。显式按 Raw/EN 快捷键永远优先于映射；探测失败一律静默回退默认模式。

## 剪贴板恢复

```bash
RESTORE_CLIPBOARD=1   # 0=关闭。自动粘贴成功后 ~1s 还原你之前复制的文本内容
                      # （延迟是为了让目标 App 先读到转写结果）
```

仅纯文本：图片等非文本剪贴板内容 `pbpaste` 拿不到，不做还原。自动粘贴失败或 `AUTO_PASTE=0` 时，转写结果会特意留在剪贴板里供你手动 ⌘V。

## 诊断：锁/阶段计时日志

```bash
VINPUT_LOCK_LOG=1   # 0=关闭。把状态机关键迁移（press / rec:start / transcribe:done /
                    # llm:done / paste:done / release，含时间戳+PID）追加到
                    # ~/.cache/vinput/lock.log
```

如果按快捷键被「⏳ 正在处理上次录音」拒绝，回看此日志即可定位是哪个阶段占着锁、占了多久。开销可忽略，常开无妨。
