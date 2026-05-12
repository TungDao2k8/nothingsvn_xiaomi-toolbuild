<div align="center">

# 🚀 HyperK AutoBuild — Xiaomi Edition

**Xiaomi Custom ROM Builder** — *Automated MIUI / HyperOS firmware modification pipeline*

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Version](https://img.shields.io/badge/version-v1.0-green.svg)](#)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey.svg)](#)

**🌐 Language / Ngôn ngữ:** **English** | [Tiếng Việt](README_VI.MD)

---

*Transform official Xiaomi OEM firmware (MIUI 14 / HyperOS 3) into a fully customized Global ROM — packed with Google Apps, AI fixes, and the KaoriOS Toolbox.*

</div>

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📦 **Google Apps** | Pre-installed GApps for Domestic ROM variants |
| 🤖 **AI Fixing** | Intelligent compatibility patches for Domestic ROM |
| 🧰 **KaoriOS Toolbox** | Advanced system modification & tuning toolkit |
| 🔄 **Multi-format Support** | Supports `payload.bin`, `new.dat.br` (Brotli), `tgz` fastboot images, and `super.img` (EU ROMs) |
| 📱 **Supported OS** | **MIUI 14** and **HyperOS 3** |
| 🧩 **A-only & V-AB** | Supports both A-only and Virtual A/B partition schemes |
| ⚙️ **Automated Pipeline** | End-to-end CI/CD via GitHub Actions |
| 📤 **Cloud Upload** | Auto-upload built ROMs to Pixeldrain with download link |

> 🔧 More features coming soon — stay tuned!

## 🏗️ How It Works

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Download   │────▶│    Unpack    │────▶│    Modify    │────▶│    Repack    │
│   Base ROM   │     │  payload.bin  │     │  Partitions  │     │  EXT/EROFS   │
│   (Xiaomi)   │     │  new.dat.br   │     │ (MIUI/HOS)   │     │              │
└──────────────┘     │  super.img    │     └──────────────┘     └──────┬───────┘
                     └──────────────┘                                  │
                     ┌──────────────┐     ┌──────────────┐            │
                     │  Upload to   │◀────│   Pack ROM   │◀───────────┘
                     │ (Pixeldrain) │     │    (.zip)    │
                     └──────────────┘     └──────────────┘
```

## 📁 Project Structure

```
nothingsvn_xiaomi-toolbuild/
├── 📜 build.sh              # Main build orchestrator
├── 📜 functions.sh          # Shared utility functions
├── 📜 packROM.sh            # ROM packaging (super.img + partitions)
├── 📜 uploadROM.sh          # Cloud upload handler (Pixeldrain)
├── 📜 setup.sh              # Environment & dependency setup
├── ⚙️ config.env            # Build configuration flags
├── 📄 Version               # Current version (v1.0)
├── 📂 bin/
│   ├── 📂 Linux/x86_64/     # Native Linux tools (lpunpack, simg2img, etc.)
│   ├── 📂 apktool/          # APK / smali decompilation tools
│   ├── 📂 ddevice/          # Device detection & ROM info scripts
│   ├── 📂 imgextractor/     # EXT4 image extractor
│   ├── 📂 modfile/
│   │   ├── 📂 MIUI14/       # MIUI 14 specific mods
│   │   ├── 📂 OS3/          # HyperOS 3 mods
│   │   ├── 📂 Universal/    # Universal mods (all versions)
│   │   └── 📂 UpdateFile/   # Update-related file mods
│   ├── 📂 package/          # Package-level patching (CorePatch, KouseiPatcher, etc.)
│   └── 📂 script2flash/     # Flashing scripts & META-INF
└── 📂 .github/
    └── 📂 workflows/
        └── 📜 build.yml     # GitHub Actions CI/CD workflow
```

## 🚀 Quick Start

### Prerequisites

Make sure the following tools are installed on your **Linux x86_64** system:

```bash
unzip  aria2c  7z  zip  java  zipalign  python3  zstd  bc  xmlstarlet  aapt
```

Or use the setup script to install all required tools automatically:

```bash
bash setup.sh
```

### Build From Source

```bash
# Clone the repository
git clone https://github.com/nothingsvn/xiaomi-toolbuild.git
cd xiaomi-toolbuild
```

```bash
# Run the build pipeline
bash build.sh <URL_OR_PATH_TO_XIAOMI_FIRMWARE>

# Pack the ROM
bash packROM.sh

# Upload to Pixeldrain
bash uploadROM.sh
```

### Supported ROM Formats

| Format | Detection | Description |
|--------|-----------|-------------|
| `payload.bin` (ZIP) | Auto | Standard Xiaomi OTA payload |
| `payload.bin` (TGZ) | Auto | Fastboot ROM with payload |
| `new.dat.br` | Auto | Brotli-compressed system images (older MIUI) |
| `super.img.*` | Auto | Xiaomi EU-style split super images |
| `*.img` (TGZ) | Auto | Fastboot ROM with raw partition images |

### Supported OS Versions

| OS | Version Code | Android |
|----|-------------|---------|
| MIUI 14 | `V14.x` | Android 13 / 14 |
| HyperOS 3 | `OS3.x` | Android 15 / 16 |

> ⚠️ MIUI 13, HyperOS 1, and HyperOS 2 are **not supported**.

## ☁️ GitHub Actions (CI/CD)

Build ROMs automatically in the cloud using **GitHub Actions** — just trigger the workflow with a firmware URL.

#### 🔑 Required Secrets

| Secret | Description |
|--------|-------------|
| `TG_TOKEN` | Telegram bot token (for build notifications) |
| `TG_CHAT_ID` | Telegram chat/channel ID to receive notifications |
| `PD_API_KEY` | Pixeldrain API key (for ROM upload) |
| `DISCORD_WEBHOOK` | Discord webhook URL (for build notifications) |

#### 📥 Workflow Input

| Input | Description |
|-------|-------------|
| `input_url` | Direct URL of the official Xiaomi firmware |

> [!TIP]
> Build progress is reported in real-time via Telegram and Discord with a 5-step progress bar. The final message includes the direct Pixeldrain download link.

### Configuration

Edit `config.env` to toggle build options:

```env
install_toolbox=true    # Install KaoriOS Toolbox
install_mods=true       # Apply custom modifications
```

## 👤 Author

**Akai** — *Project Lead & Developer*

## 💎 Credits

### 🙏 Special Thanks

| Who | Contribution |
|-----|-------------|
| **Chau Vinh Tien** | Original project foundation |
| [Kousei](https://t.me/Kousei_jp) | KaoriOS Toolbox |
| [MaiAFK](https://t.me/maiphp) | Website concept & web server code |
| [Mốc](https://t.me/jerryx0x) | Mod & build methods |
| [summert](https://t.me/ntai15) | Coding support & issue resolution |
| [BHLNK](https://t.me/bhlnk) | AI fixing spoof methods |

### 💰 Sponsors

| Who | Support |
|-----|---------|
| [fukiame](https://t.me/fukiame) | Hosting sponsor |
| [Xfu7107](https://t.me/xfu7101) | Hosting, GitHub Actions & more |
| [AGPHONG](https://t.me/agphong) | Best sponsor 🏆 |

### 🤖 AI Tools

> Antigravity by Google · Cursor · Codex by OpenAI · Claude

## 📄 License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Made with ❤️ by Akai**

*⭐ Star this repo if you find it useful!*

</div>
