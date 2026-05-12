#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# fetchINFO.sh — Read device info from extracted ROM and persist to state files

set -euo pipefail

# FIX: dùng BASH_SOURCE để luôn tìm đúng work_dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${work_dir}/functions.sh"

# ─── Read persisted state ────────────────────────────────────────────────────
regionTYPE="$(cat "${work_dir}/bin/ddevice/device_type.txt")"
device_code="$(cat "${work_dir}/bin/ddevice/device_code.txt")"
name="$(cat "${work_dir}/bin/ddevice/name_devices.txt")"
base_rom_code="$(cat "${work_dir}/bin/ddevice/base_rom_code.txt")"
rom_os="$(cat "${work_dir}/bin/ddevice/rom_os.txt")"
starxVER="$(cat "${work_dir}/Version")"
systemtype="$(cat "${work_dir}/bin/ddevice/fstype.txt")"

# FIX: đọc từ build.prop đúng path, guard nếu file không tồn tại
BUILD_PROP="${work_dir}/build/baserom/images/system/system/build.prop"
if [[ ! -f "${BUILD_PROP}" ]]; then
    error "build.prop not found at ${BUILD_PROP}"
    exit 1
fi

AndroidVer="$(grep "ro.system.build.version.release" "${BUILD_PROP}" \
    | awk 'NR==1' | cut -d '=' -f 2 | tr -d '\r')"
sdkLevel="$(grep  "ro.system.build.version.sdk"     "${BUILD_PROP}" \
    | awk 'NR==1' | cut -d '=' -f 2 | tr -d '\r')"

# ─── VAB detection ───────────────────────────────────────────────────────────
VENDOR_PROP="${work_dir}/build/baserom/images/vendor/build.prop"
if [[ -f "${VENDOR_PROP}" ]] && grep -q "ro.build.ab_update=true" "${VENDOR_PROP}"; then
    echo "VAB"     > "${work_dir}/bin/script2flash/META-INF/Data/Structure"
else
    echo "Non-VAB" > "${work_dir}/bin/script2flash/META-INF/Data/Structure"
fi

# ─── Chip detection ──────────────────────────────────────────────────────────
QCOM_RC="${work_dir}/build/baserom/images/vendor/etc/init/hw/init.qcom.rc"
if [[ -f "${QCOM_RC}" ]]; then
    echo "Snapdragon" > "${work_dir}/bin/script2flash/META-INF/Data/Chip"
else
    echo "Mediatek"   > "${work_dir}/bin/script2flash/META-INF/Data/Chip"
fi

# ─── Persist all metadata ────────────────────────────────────────────────────
echo "${rom_os}"       > "${work_dir}/bin/ddevice/os_type.txt"
echo "${AndroidVer}"   > "${work_dir}/bin/ddevice/androidver.txt"
echo "${sdkLevel}"     > "${work_dir}/bin/ddevice/sdkLevel.txt"

echo "${AndroidVer}"   > "${work_dir}/bin/script2flash/META-INF/Data/AndroidVer"
echo "${base_rom_code}"  > "${work_dir}/bin/script2flash/META-INF/Data/RomBased"
echo "${starxVER}"     > "${work_dir}/bin/script2flash/META-INF/Data/Version"
echo "${regionTYPE}"   > "${work_dir}/bin/script2flash/META-INF/Data/Region"
echo "${name}"         > "${work_dir}/bin/script2flash/META-INF/Data/DeviceName"
echo "${systemtype}"   > "${work_dir}/bin/script2flash/META-INF/Data/Types"

# ─── Build summary ───────────────────────────────────────────────────────────
echo "------------------Nothings BuildInfo ---------------------"
echo "- Device Name:    ${name}"
echo "- Codename:       ${device_code}"
echo "- ROM OS:         ${rom_os}"
echo "- Build Region:   ${regionTYPE}"
echo "- Android:        ${AndroidVer}"
echo "- ROM Code:       ${base_rom_code}"
echo "- BuildTool Ver:  ${starxVER}"
echo "- FS Type:        ${systemtype}"
echo "----------------------------------------------------------"
