# ASR Regression Suite

固定音频 → Whisper 转写 → 字符错误率 (CER)。在改 `bin/vinput_bg.sh`、`config/`、Whisper
参数前都跑一次，看是否退化。

## 为什么存在

v1.1.3 → v1.1.7 四个 hotfix 都是「改了 ASR 参数没回归」的产物。这个套件就是为了让这种
事不再发生 —— 在你按 `git tag` 之前先按 `bash tests/asr/run.sh`。

## 快速开始

```bash
bash tests/asr/run.sh
```

首次运行会自动调用 `generate.sh` 生成 `samples/*.wav`（用 macOS `say` TTS，可重现）。

输出：

```
ID                CER     BUDGET  VERDICT  HYP
01-zh-tech-basic  0.0250  0.15    PASS     使用Whisper和 Ollama 作本地语音转写...
02-zh-products    0.0465  0.20    PASS     常用的开发工具有Cursor、Cloud Code...
...
✓ All samples within budget.
```

退出码 0 = 全部在预算内；非零 = 至少一条退化，**别 tag**。

## 文件结构

```
tests/asr/
├── samples/
│   ├── manifest.tsv          # 单一权威：id, voice, rate, post_fx, cer_max, note
│   ├── NN-xxx.txt            # 参考文本（也是 reference for CER）
│   └── NN-xxx.wav            # 生成的音频（.gitignore — 用 generate.sh 重建）
├── generate.sh               # macOS `say` + sox 重新生成所有 wav
├── run.sh                    # 主入口：跑端到端 + CER 表
├── cer.py                    # Levenshtein-based CER（纯 stdlib，无 jiwer）
└── README.md
```

## 如何贡献新样本

1. **加 `.txt`**：`samples/07-your-id.txt`，内容是你期望的转写（中文用真实标点）。
2. **加 manifest 行**：
   ```
   07-your-id	Tingting	180	none	0.20	描述这个样本测什么
   ```
   - `voice`：`say -v '?' | grep zh_CN` 看可选项。
   - `rate`：词每分钟（180 是中速，260 是急快）。
   - `post_fx`：`none` / `silence` / 任意 sox 链（如 `gain -20`、`pad 0 1 reverb`）。
   - `cer_max`：CER 预算 ∈ [0, 1]。0.15 是干净基线，0.25 给挑战样本。
3. **跑一次** `bash tests/asr/run.sh`，确认你的样本能进预算。如果 CER 高于预期：要么调
   `cer_max`，要么调样本，但**不要**为它放宽 budget。
4. **commit** `.txt` 和 `manifest.tsv` —— `.wav` 是生成物，被 gitignore。

## 设计取舍

- **为什么用 TTS 而不是真人录音**：可重现。任何人 clone 完都能 `generate.sh` 拿到同
  样的 wav。真人录音以后可以加 `samples/human/`，作为更高难度的层。
- **为什么是 CER 而不是 WER**：中文按字算 ER 更稳，避免分词的歧义。`cer.py` 在比较前
  剥掉空白和标点。
- **为什么没用 jiwer**：避免 pip 依赖让套件在 brew 环境零安装即可跑。CER 算法本身 30
  行就够。如果以后要切到 jiwer，`cer.py` 接口就是 `--ref-string REF HYP`。
- **为什么没接 CI**：CI 上跑 large-v3-turbo 单条 ~10 秒，6 条 ~60 秒，可接受但不是
  v1.1.8 紧急需求。本地 pre-tag 跑过比 CI 检查更直接。CI gate 留给后续 issue。

## 已知 quirks

- **`06-silence` 会出 "Thank you."**：Whisper 在纯静音段的经典幻觉。`cer_max=1.00`
  表示我们不卡这条 —— 但它存在是为了**监测幻觉变更**。哪天它从 "Thank you." 变成
  乱码或者大段输出，我们一眼就能看见。
- **`02-zh-products` 经常把 `Claude Code` 识别成 `Cloud Code`**：这正是 issue #18
  （谐音纠错表）的杀手锏目标 —— 一旦 #18 上线，预期这条 CER 会进一步降低。

## 长音频调参（负面结果归档）

`07-zh-long`（66s 连续中文，跨 2 个 whisper 30s 窗口边界）是这套件里唯一 CER 偏高的真实
样本（raw ≈ 0.117，其余短句 0.00–0.025）。错误集中在两类：①同音字（「重构」→「中够」、
「默认值」→「默认之」）；②**窗口边界整句漏字**（参考里「把改动前后的效果实际对比一下」
整句丢失）。

为提升长音频准确度，逐项实测过以下方案，**结论是 ASR 层基本调不动**，记此存档免得重走：

| 方案 | 07-zh-long CER | 备注 |
|------|----------------|------|
| baseline（beam5 + 默认 flag） | **0.117** | 现状，已接近地板 |
| `--max-context 64 / 32` | 0.39 | **更差**，且把单窗短句一起拖垮（截断了 prompt 热词） |
| `--max-context 0` | 0.113 | 长句几乎持平，但短句退化，净亏 |
| `--entropy-thold 2.2` / `--carry-initial-prompt` / `beam 8~10` / `best-of` / `no-fallback` | 0.117 | 零增益 |
| 去掉 `--prompt` 热词 | 0.113 | 长句微降，但牺牲专有名词，不划算 |
| 换 `turbo-q8_0` | 0.120 | 与现状持平（量化差异可忽略） |
| 换完整 `large-v3-q5_0` | 0.148 | **更差**且慢 1.8×（turbo 在中文上已很接近完整版） |
| 静音切片重拼（sox silence split） | 0.34 | **更差**，引入复读 + 片段重复 |

留下的 `WHISPER_ENTROPY_THOLD` / `WHISPER_MAX_CONTEXT` / `WHISPER_CARRY_PROMPT` 三个配置
项（默认空 = 不改 whisper 默认）只是手动实验的逃生舱，**别当默认开**。长音频 raw CER 的
真正兜底在下游：谐音纠错表（#18）+ LLM 整形。注意 CER 测的是 **raw whisper 输出**，线上
实际还会过纠错表与 qwen2.5 整形，体验优于这里的裸数字。
