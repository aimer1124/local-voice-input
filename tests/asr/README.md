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
