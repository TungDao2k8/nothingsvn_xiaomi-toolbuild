#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# setup.sh — NothingsVN AutoBuild environment setup

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[SETUP] Updating package lists..."
# Ubuntu 24.04 (noble) đã có gcc-13/14 trong repo chính
# → không cần PPA ubuntu-toolchain-r nữa
sudo apt-get update -y -qq

echo "[SETUP] Installing required packages..."
# FIX: bỏ java-common default-jre-headless — đã cài qua actions/setup-java
# FIX: bỏ python3 python-is-python3 — có sẵn trên ubuntu-latest
sudo apt-get install -y --no-install-recommends \
    aria2 jq rclone sshpass \
    python3-pip \
    wget lz4 xz-utils device-tree-compiler \
    zlib1g-dev gcc g++ libc6 libstdc++6 libc++1 \
    aapt busybox zip erofs-utils unzip p7zip-full \
    zipalign zstd bc android-sdk-libsparse-utils \
    xmlstarlet

echo "[SETUP] Installing Python packages..."
pip3 install --no-cache-dir --break-system-packages \
    ConfigObj telebot setuptools

echo "[SETUP] Cleaning up..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "[SETUP] Environment ready."
