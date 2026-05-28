# LLM Cleanup Regression Suite

冻结的 raw-text → Ollama → 期望约束。和 `tests/asr/` 是兄弟套件：那个测 Whisper
拿出来的字面正确性；**这个测 LLM 整形阶段不会破坏语义（吞数字、丢否定、生成代码…）**。

## 为什么存在

`bin/vinput_bg.sh` 里的 `clean_with_llm()` 用的 prompt 决定了：
- 数字会不会被改写（"5 个按钮" → "几个按钮" 就糟了）
- 否定会不会被丢（"不要硬编码" → "硬编码" 直接是事故）
- LLM 会不会自作主张产代码（用户只想要指令，不想要 `\`\`\`function ...\`\`\``）

每次改 prompt 之前必须跑：

```bash
bash tests/llm/run.sh
```

退出码 0 = 全过；非零 = 有 case 没满足约束，**别 merge / 别 tag**。

## 文件结构

每个 case 三个文件（一 case 一组）：

```
tests/llm/cases/
├── 01-preserve-number.input.txt          # 输入给 LLM 的文本
├── 01-preserve-number.must_contain.txt   # 一行一个：输出必须包含（CI）
├── 01-preserve-number.must_not_contain.txt  # 一行一个：输出绝不能包含（CI）
└── ...
```

**约束是必要条件，不是等式**。LLM 输出是随机的，要求精确匹配会 flaky。我们只检查：
- 关键信息（数字 / 否定 / 专名）是否保留
- 危险模式（fillers / 代码块 / "啊不对" 之类的自我纠正残留）是否绝迹

**Retry 兜底**：每个 case 默认最多跑 3 次，任一次过就 PASS。这是对 LLM 随机性的妥协 ——
suite 的价值在于发现**系统性退化**（prompt 改坏了），不在于挑出单次 flake。需要严格
模式时 `VINPUT_LLM_MAX_TRIES=1 bash tests/llm/run.sh`。

## 如何加 case

1. 在 `cases/` 目录加三个文件：`<id>.input.txt` / `.must_contain.txt` / `.must_not_contain.txt`
2. `must_contain` / `must_not_contain` 任一可以为空文件（约束就是"无约束"）
3. 跑 `bash tests/llm/run.sh` 验证你新 case 的 PASS/FAIL 符合预期
4. commit

## 已知 quirks

- **依赖 Ollama 在跑** — `run.sh` 不会启动 Ollama。如果没启动，所有 case 都会拿到空输出 → 全 FAIL。先 `brew services start ollama`。
- **首次调用慢** — 模型加载冷启动 ~5-10s。后续 case 会复用进程内模型，每个 ~1-2s。
- **`contains_ci` 只对 ASCII 大小写敏感** — 中文本身没有大小写概念。约束里的 `React` / `react` / `REACT` 都匹配；中文严格按字。
- **case ID 决定执行顺序**（按 glob 字母排序）。所以前缀数字。

## 设计取舍

- **为什么是 contract 检查而不是 CER**：LLM 输出风格多样，CER 跟一个"金标"对比会无意义地波动。"必含/绝不含"更直接表达我们关心的不变量。
- **为什么没接 CI**：和 ASR 套件同理 —— Ollama 在 CI runner 上跑大模型不现实。本地 pre-tag 跑就够。
- **为什么不固化温度**：Ollama 的 `temperature` 参数在 qwen2.5 上效果有限，强制 0 也未必稳定。这个套件被设计成对温度不敏感（contract 检查留余地）。
