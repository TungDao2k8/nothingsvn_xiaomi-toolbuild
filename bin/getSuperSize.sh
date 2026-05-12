#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# getSuperSize.sh — Return super partition size in bytes for a given device codename

set -euo pipefail

device_code="${1:-}"

if [[ -z "${device_code}" ]]; then
    echo "Error: Please provide a device codename" >&2
    exit 1
fi

# Convert to lowercase for matching
code_lower="$(echo "${device_code}" | tr '[:upper:]' '[:lower:]')"

case "${code_lower}" in
    # Xiaomi 13 series, K60 Pro, Mix Fold 3
    fuxi|nuwa|ishtar|socrates|babylon|marble|aurora|dew|garnet|vermeer)
        size=9663676416 ;;
    # Xiaomi 15 Pro/Ultra, Redmi Turbo 4 Pro
    haotian|xuanyuan|onyx|miro|klimt|dada|yudi|rodin|zorn)
        size=11811160064 ;;
    # Xiaomi Mix Fold 4
    myron)
        size=14495514624 ;;
    # Xiaomi 17 Series
    annibale|pudding|popsicle|pandora)
        size=13421772800 ;;
    # Redmi Note 12 5G
    sunstone)
        size=9122611200 ;;
    # Xiaomi 14 / 14 Pro
    houji|shennong)
        size=8321499136 ;;
    # Redmi 12R
    sky)
        size=6979321856 ;;
    # Redmi Note 12/13, 13C
    tapas|topaz|sapphire|sapphiren|gale)
        size=7516192768 ;;
    # Redmi 12C
    earth)
        size=7514095616 ;;
    # Redmi Note 14 4G
    tanzanite)
        size=8042577920 ;;
    # Redmi Note 14 Pro 4G
    obsidian)
        size=8053063680 ;;
    # Redmi Note 13 Pro 4G
    emerald)
        size=7505707008 ;;
    # Default fallback
    *)
        size=9126805504 ;;
esac

# FIX: echo ra stdout (cho command substitution trong packROM.sh)
# Ghi thêm vào file state nếu cần
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
echo "${size}" > "${work_dir}/bin/ddevice/superSize.txt"

echo "${size}"
