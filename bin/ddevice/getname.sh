#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# getname.sh — Look up device display name from JSON data files

set -euo pipefail

# FIX: dùng BASH_SOURCE thay vì pwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${work_dir}/functions.sh"

FILE_JSON1="${work_dir}/bin/ddevice/data/devices.json"
FILE_JSON2="${work_dir}/bin/ddevice/data/names.json"
DATA_TXT="${work_dir}/bin/ddevice/data/devices_data.txt"

# FIX: đọc KEY từ device_f.txt thay vì file arg — nhất quán với phần còn lại
KEY="$(cat "${work_dir}/bin/ddevice/device_f.txt")"

# FIX: guard — kiểm tra jq có mặt
exists() { command -v "$1" >/dev/null 2>&1; }
exists jq || { error "jq not installed"; exit 1; }

if grep -qw "${KEY}" "${DATA_TXT}" 2>/dev/null; then
    VALUE="$(jq -r --arg key "${KEY}" '.[$key] // "Unknown Device"' "${FILE_JSON1}")"
else
    VALUE="$(jq -r --arg key "${KEY}" '.[$key] // "Unknown Device"' "${FILE_JSON2}")"
fi

echo "${VALUE}" > "${work_dir}/bin/ddevice/name_devices.txt"
info "Device name resolved: ${VALUE}"
