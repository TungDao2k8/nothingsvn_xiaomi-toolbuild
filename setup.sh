#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# setup.sh - Converted for Arch Linux
# Original: https://github.com/TungDao2k8/nothingsvn_xiaomi-toolbuild

set -e

# ── Helpers ───────────────────────────────────────────────────────────────────
has_cmd() { command -v "$1" &>/dev/null; }

# Detect AUR helper (yay preferred, paru fallback)
if has_cmd yay; then
    AUR="yay"
elif has_cmd paru; then
    AUR="paru"
else
    echo "[setup] No AUR helper found (yay / paru)."
    echo "        Installing yay automatically..."
    sudo pacman -S --noconfirm --needed git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay-setup
    (cd /tmp/yay-setup && makepkg -si --noconfirm)
    rm -rf /tmp/yay-setup
    AUR="yay"
fi

echo "[setup] Using AUR helper: $AUR"

# ── System update ─────────────────────────────────────────────────────────────
# Equivalent of: apt update && apt upgrade
sudo pacman -Syu --noconfirm

# ── Official pacman packages ──────────────────────────────────────────────────
# Mapping from Ubuntu packages → Arch packages:
#   aria2                      → aria2
#   jq                         → jq
#   rclone                     → rclone
#   sshpass                    → sshpass
#   python-is-python3          → python (already is python3 on Arch)
#   wget                       → wget
#   python3                    → python
#   lz4                        → lz4
#   xz-utils                   → xz
#   device-tree-compiler       → dtc
#   zlib1g-dev                 → zlib
#   gcc                        → gcc
#   g++                        → gcc (includes g++)
#   libc6                      → glibc
#   libstdc++6                 → gcc-libs
#   python3-pip                → python-pip
#   dialog                     → dialog
#   libgtk-3-dev               → gtk3
#   busybox                    → busybox
#   zip                        → zip
#   unzip                      → unzip
#   p7zip-full                 → p7zip
#   zstd                       → zstd
#   bc                         → bc
#   xmlstarlet                 → xmlstarlet
#   erofs-utils                → erofs-utils
#   android-sdk-libsparse-utils→ android-tools  (includes simg2img, img2simg)
#   aapt                       → android-tools  (includes aapt)
#   zipalign                   → android-tools  (includes zipalign)

PACMAN_PKGS=(
    aria2
    jq
    rclone
    sshpass
    python
    python-pip
    wget
    lz4
    xz
    dtc
    zlib
    gcc
    glibc
    gcc-libs
    dialog
    gtk3
    busybox
    zip
    unzip
    p7zip
    zstd
    bc
    xmlstarlet
    erofs-utils
    android-tools   # provides: aapt, zipalign, simg2img, adb, fastboot
    brotli          # needed by build.sh for .new.dat.br unpacking
    git
    base-devel      # make, patch, etc. — needed to build AUR packages
)

echo "[setup] Installing pacman packages..."
sudo pacman -S --noconfirm --needed "${PACMAN_PKGS[@]}"

# ── AUR packages ──────────────────────────────────────────────────────────────
# payload-dumper-go  → AUR (used in build.sh for payload.bin extraction)
# java-runtime       → jre-openjdk (needed by tools that call 'java')

AUR_PKGS=(
    payload-dumper-go
    jre-openjdk-headless
)

echo "[setup] Installing AUR packages via $AUR..."
$AUR -S --noconfirm --needed "${AUR_PKGS[@]}"

# ── Python pip packages ───────────────────────────────────────────────────────
# pip3 install → pip install  (Arch uses 'pip' not 'pip3')
# --break-system-packages required on Arch (PEP 668 enforced)
echo "[setup] Installing Python packages..."
pip install --no-cache-dir --break-system-packages \
    ConfigObj \
    pyTelegramBotAPI \
    setuptools

# ── Cache cleanup ─────────────────────────────────────────────────────────────
# Equivalent of: apt clean && rm -rf /var/lib/apt/lists/*
echo "[setup] Cleaning package cache..."
sudo pacman -Sc --noconfirm

echo ""
echo "[setup] ✓ All dependencies installed successfully."
echo "        You can now run: bash build.sh <rom.zip>"
