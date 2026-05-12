#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# uploadROM.sh — upload ROM lên Pixeldrain, export output vars cho workflow
# Telegram notifications được xử lý hoàn toàn bởi build.yml

set -euo pipefail

work_dir="$(pwd)"
source "${work_dir}/functions.sh"

# ─── Validate Pixeldrain key ──────────────────────────────────────────────────
# FIX: chỉ check PD_API_KEY — TG credentials không cần ở đây nữa
: "${PD_API_KEY:?PD_API_KEY is not set — add it as a GitHub Actions Secret}"

# ─── Read device state ───────────────────────────────────────────────────────
load_version

os_type="$(cat "${work_dir}/bin/ddevice/os_type.txt")"
base_rom_code="$(cat "${work_dir}/bin/ddevice/base_rom_code.txt")"
androidVER="$(cat "${work_dir}/bin/ddevice/androidver.txt")"
rom_os="$(cat "${work_dir}/bin/ddevice/rom_os.txt")"
regionTYPE="$(cat "${work_dir}/bin/ddevice/device_type.txt")"
device_code="$(cat "${work_dir}/bin/ddevice/device_code.txt")"
baserom_type="$(cat "${work_dir}/bin/ddevice/romtype.txt")"
device_f="$(cat "${work_dir}/bin/ddevice/device_f.txt")"

[[ "${rom_os}" == "MIUI" ]] && os_type="MIUI" || os_type="HyperOS"

# ─── Compress super.img ──────────────────────────────────────────────────────
repack "Compressing super.img with zstd (-T0 = all threads)..."
zstd --rm -T0 \
    "${work_dir}/build/baserom/images/super.img" \
    -o "${work_dir}/build/baserom/images/super.img.zst" >/dev/null 2>&1

# ─── Assemble output directory ───────────────────────────────────────────────
repack "Assembling flashable package..."
out_dir="${work_dir}/out/${os_type}_${device_code}_${base_rom_code}"
mkdir -p "${out_dir}/images/"

if [[ "${baserom_type}" == "payload" ]]; then
    mv -f "${work_dir}/build/baserom/images/super.img.zst" "${out_dir}/"
    mv -f "${work_dir}/build/baserom/images/"*.img "${out_dir}/images/" 2>/dev/null || true
elif [[ "${baserom_type}" == "br" ]]; then
    mv -f "${work_dir}/build/baserom/firmware-update/"* "${out_dir}/images/" 2>/dev/null || true
    mv -f "${work_dir}/build/baserom/images/super.img.zst" "${out_dir}/"
fi

cp -r "${work_dir}/bin/script2flash/META-INF"   "${out_dir}/"
cp    "${work_dir}/bin/script2flash/"*.bat        "${out_dir}/" 2>/dev/null || true
cp    "${work_dir}/bin/script2flash/cust.img"     "${out_dir}/images/"
echo  "${device_f}" > "${out_dir}/META-INF/Data/DeviceCode"

# ─── Create ZIP ──────────────────────────────────────────────────────────────
find "${out_dir}" | xargs touch
pushd "${out_dir}" >/dev/null
zip -r "${os_type}_${device_code}_${base_rom_code}.zip" ./*
mv "${os_type}_${device_code}_${base_rom_code}.zip" ../
popd >/dev/null

hash="$(md5sum "${work_dir}/out/${os_type}_${device_code}_${base_rom_code}.zip" | head -c 5)"
final_name="${os_type}_${polyxver}_${device_code}_${base_rom_code}_${hash}_${status}.zip"
mv "${work_dir}/out/${os_type}_${device_code}_${base_rom_code}.zip" \
   "${work_dir}/out/${final_name}"

repack "Build complete → ${final_name}"

# ─── Upload to Pixeldrain ─────────────────────────────────────────────────────
upload "Uploading ${final_name}..."

PD_RESPONSE="$(curl -s \
    -u ":${PD_API_KEY}" \
    -F "file=@${work_dir}/out/${final_name};filename=${final_name}" \
    https://pixeldrain.com/api/file)"

PD_ID="$(echo "${PD_RESPONSE}" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || true)"

if [[ -z "${PD_ID}" ]]; then
    error "Upload to Pixeldrain failed! Response: ${PD_RESPONSE}"
    exit 1
fi

PD_LINK="https://pixeldrain.com/u/${PD_ID}"
upload "Upload successful: ${PD_LINK}"

# ─── Export output vars cho workflow ─────────────────────────────────────────
# Workflow sẽ dùng các giá trị này trong thông báo Telegram thành công
{
    echo "ROM_NAME=${final_name}"
    echo "PD_LINK=${PD_LINK}"
} >> "${GITHUB_OUTPUT}"

# ─── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf "${work_dir}/out" "${work_dir}/build"
upload "Done — ${os_type}_${polyxver} for ${device_code} built successfully!"
