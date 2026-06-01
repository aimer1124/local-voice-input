# Release Notes Template — Bilingual (zh-CN + English)

> 复制此模板填写每次新版本的 release notes。发布前先跑确定性检查：
>
> ```bash
> bash scripts/preflight.sh
> # optional full local gate:
> RUN_LLM=1 RUN_ASR=1 bash scripts/preflight.sh
> ```
>
> 然后运行：
>
> ```bash
> gh release create vX.Y.Z --title "vX.Y.Z — short title" \
>     --notes-file docs/RELEASE_TEMPLATE.md --target main
>
> # 推 tag 触发 CI 自动上传 hud 二进制（不会覆盖你的 notes）
> git fetch --tags
> ```
>
> 更新 Homebrew tap 时，用 release helper 校验版本并写入 formula：
>
> ```bash
> scripts/release.sh --version X.Y.Z --tap ~/homebrew-tap \
>     --source-sha <tag-tarball-sha256> --hud-sha <hud-sha256> --apply
> ```
>
> 或本地先打 tag 再推送：
>
> ```bash
> git tag vX.Y.Z -m "vX.Y.Z — short title"
> gh release create vX.Y.Z --notes-file <your-notes-file>.md
> git push origin vX.Y.Z
> ```

---

## 🇨🇳 中文

### 🚀 新增 / Changed
- ...

### 🐛 修复 / Fixed
- ...

### 📦 安装

```bash
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

未安装 Xcode Command Line Tools 的用户也可正常运行 —— `install.sh` 会自动从本 release 下载预编译的 HUD 二进制。

### 🔄 升级

```bash
cd local-voice-input
git pull
./install.sh
```

---

## 🇬🇧 English

### 🚀 What's New / Changed
- ...

### 🐛 Fixed
- ...

### 📦 Installation

```bash
git clone https://github.com/aimer1124/local-voice-input.git
cd local-voice-input
./install.sh
```

Users without Xcode Command Line Tools are supported — `install.sh` automatically downloads the pre-built HUD binary from this release.

### 🔄 Upgrade

```bash
cd local-voice-input
git pull
./install.sh
```

---

## 📥 Release Asset

`hud` is a pre-built Apple Silicon binary (arm64). SHA256 is in `hud.sha256`.

Built automatically by [`.github/workflows/release.yml`](https://github.com/aimer1124/local-voice-input/blob/main/.github/workflows/release.yml).

The binary is ad-hoc signed (not Apple-notarized). `install.sh` clears the Gatekeeper quarantine attribute automatically. If you prefer compiling from source, install Xcode CLT and re-run the installer:

```bash
xcode-select --install
```
