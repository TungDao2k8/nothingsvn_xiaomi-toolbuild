#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# getROM.sh — Download or validate ROM file, extract device info

set -euo pipefail

baserom="$1"
# FIX: dùng BASH_SOURCE để xác định đúng work_dir bất kể gọi từ đâu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${work_dir}/functions.sh"

# ─── Download nếu là URL ──────────────────────────────────────────────────────
if [[ ! -f "${baserom}" ]] && echo "${baserom}" | grep -q "http"; then
    info "Download link detected, starting download..."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 "${baserom}"
    # FIX: dùng basename chung, bỏ query string
    baserom="$(basename "${baserom}" | sed 's/\?t.*//')"
    if [[ ! -f "${baserom}" ]]; then
        error "Download error! File not found after download: ${baserom}"
        exit 1
    fi
    info "BASEROM: ${baserom}"
elif [[ -f "${baserom}" ]]; then
    info "BASEROM: ${baserom}"
else
    error "BASEROM: Invalid parameter — file not found and not a URL"
    exit 1
fi

# ─── Parse device/version info from filename ─────────────────────────────────
if echo "${baserom}" | grep -q "miui_"; then
    device_code="$(basename "${baserom}" | cut -d '_' -f 2)"
    base_rom_code="$(basename "${baserom}" | awk -F'_' '{print $3}')"
elif echo "${baserom}" | grep -q "xiaomi.eu_"; then
    device_code="$(basename "${baserom}" | cut -d '_' -f 3)"
    base_rom_code="$(basename "${baserom}" | awk -F'_' '{print $3}')"
elif echo "${baserom}" | grep -qE '.*-ota_full-.*'; then
    device_code="$(basename "${baserom}" | cut -d '-' -f 1)"
    base_rom_code="$(basename "${baserom}" | cut -d '-' -f 3)"

    # Transform device_code: foo → FOO, foo_global → FOOGlobal, etc.
    device_code="$(echo "${device_code}" | awk -F '_' '{
        if (NF == 1) {
            print toupper($1)
        } else if (NF == 2) {
            print toupper($1) toupper(substr($2,1,1)) substr($2,2)
        } else if (NF == 3) {
            printf toupper($1) toupper($2) toupper(substr($3,1,1)) substr($3,2)
        }
    }')"
elif echo "${baserom}" | grep -q "_images_"; then
    # Format: {device}_{region}_images_{version}_{date}_{...}
    # Example: mondrian_tw_global_images_OS3.0.2.0.VMNTWXM_20260319.0000.00_15.0_tw_...tgz
    fname="$(basename "${baserom}")"
    # Split on first occurrence of _images_ to separate device+region from version
    left_part="${fname%%_images_*}"
    right_part="${fname#*_images_}"
    # Device name is the first underscore-delimited field
    device_name="$(echo "${left_part}" | cut -d '_' -f 1)"
    # Region is everything after the device name
    region_raw="${left_part#${device_name}_}"
    # Version code is the first field after _images_
    base_rom_code="$(echo "${right_part}" | cut -d '_' -f 1)"

    # Map region string to standard suffix used by DEVICE_TYPE detection below
    case "${region_raw}" in
        tw_global|tw)   region_suffix="TWGlobal"  ;;
        eea_global|eea) region_suffix="EEAGlobal" ;;
        in_global|in)   region_suffix="INGlobal"  ;;
        id_global|id)   region_suffix="IDGlobal"  ;;
        ru_global|ru)   region_suffix="RUGlobal"  ;;
        jp_global|jp)   region_suffix="JPGlobal"  ;;
        tr_global|tr)   region_suffix="TRGlobal"  ;;
        global)         region_suffix="Global"     ;;
        *)              region_suffix=""           ;;
    esac

    # Build device_code: capitalise first letter of codename then append region suffix
    device_code="$(echo "${device_name}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')${region_suffix}"
else
    device_code="YourDevice"
    base_rom_code="Unknown"
fi

# ─── Strip region suffix to get base codename ────────────────────────────────
device_f="$(echo "${device_code}" \
    | sed 's/\(Global\|EEAGlobal\|INGlobal\|IDGlobal\|RUGlobal\|TWGlobal\|TRGlobal\|JPGlobal\)$//' \
    | tr '[:upper:]' '[:lower:]')"

# ─── Determine region type ───────────────────────────────────────────────────
info "Detecting device type..."
if   echo "${device_code}" | grep -q 'EEAGlobal'; then DEVICE_TYPE="EEAGlobal"
elif echo "${device_code}" | grep -q 'INGlobal';  then DEVICE_TYPE="INGlobal"
elif echo "${device_code}" | grep -q 'IDGlobal';  then DEVICE_TYPE="IDGlobal"
elif echo "${device_code}" | grep -q 'RUGlobal';  then DEVICE_TYPE="RUGlobal"
elif echo "${device_code}" | grep -q 'JPGlobal';  then DEVICE_TYPE="JPGlobal"
elif echo "${device_code}" | grep -q 'TWGlobal';  then DEVICE_TYPE="TWGlobal"
elif echo "${device_code}" | grep -q 'TRGlobal';  then DEVICE_TYPE="TRGlobal"
elif echo "${device_code}" | grep -q 'Global';    then DEVICE_TYPE="Global"
else                                                    DEVICE_TYPE="China"
fi

# ─── Determine OS version ────────────────────────────────────────────────────
# Supported: MIUI13 (V13.x), MIUI14 (V14.x), HyperOS 1 (OS1), HyperOS 2 (OS2), HyperOS 3 (OS3)
if   echo "${base_rom_code}" | grep -q "OS3"; then ROM_OS="OS3"
elif echo "${base_rom_code}" | grep -q "OS2"; then ROM_OS="OS2"
elif echo "${base_rom_code}" | grep -q "OS1"; then ROM_OS="OS1"
elif echo "${base_rom_code}" | grep -q "V14"; then ROM_OS="MIUI14"
elif echo "${base_rom_code}" | grep -q "V13"; then ROM_OS="MIUI13"
else
    error "Unsupported ROM version in: ${base_rom_code}. Supported: V13.x, V14.x, OS1.x, OS2.x, OS3.x."
    exit 1
fi

# ─── Persist state files ─────────────────────────────────────────────────────
echo "${base_rom_code}" > "${work_dir}/bin/ddevice/base_rom_code.txt"
echo "${base_rom_code}" > "${work_dir}/bin/ddevice/os_code.txt"
echo "${device_code}"   > "${work_dir}/bin/ddevice/device_code.txt"
echo "${DEVICE_TYPE}"   > "${work_dir}/bin/ddevice/device_type.txt"
echo "${ROM_OS}"        > "${work_dir}/bin/ddevice/rom_os.txt"

# Export for caller (build.sh sources this file)
export baserom device_code device_f base_rom_code DEVICE_TYPE ROM_OS
