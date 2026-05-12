#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# packROM.sh — NothingsVN AutoBuild ROM packaging script

set -euo pipefail

work_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# FIX: dynamic arch path
export PATH="${work_dir}/bin/$(uname)/$(uname -m):${PATH}"

source "${work_dir}/functions.sh"
load_version

# ─── Read device state ───────────────────────────────────────────────────────
super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
os_type="$(cat "${work_dir}/bin/ddevice/os_type.txt")"
base_rom_code="$(cat "${work_dir}/bin/ddevice/base_rom_code.txt")"
androidVER="$(cat "${work_dir}/bin/ddevice/androidver.txt")"
rom_os="$(cat "${work_dir}/bin/ddevice/rom_os.txt")"
regionTYPE="$(cat "${work_dir}/bin/ddevice/device_type.txt")"
device_code="$(cat "${work_dir}/bin/ddevice/device_f.txt")"
getvar="${device_code}"
PACK_TYPE="$(cat "${work_dir}/bin/ddevice/fstype.txt")"

[[ "${rom_os}" == "MIUI" ]] && os_type="MIUI" || os_type="HyperOS"

# ─── Partition size map ──────────────────────────────────────────────────────
_part_addsize() {
    local pname="$1"
    if [[ "${androidVER}" == "12" ]]; then
        case "${pname}" in
            system)  echo 114217728 ;;
            odm|vendor|system_ext|product) echo 104217728 ;;
            *) echo 8054432 ;;
        esac
    else
        case "${pname}" in
            mi_ext) echo 4094304 ;;
            product) echo 114217728 ;;
            odm|system|vendor|system_ext) echo 104217728 ;;
            *) echo 8054432 ;;
        esac
    fi
}

# ─── Pack one partition (called in background) ───────────────────────────────
# FIX: dùng BIN_ARCH cho make_ext4fs và mkfs.erofs
_pack_partition() {
    local pname="$1"
    local img_dir="${work_dir}/build/baserom/images"

    [[ -d "${img_dir}/${pname}" ]] || return 0

    local thisSize addSize
    thisSize="$(du -sb "${img_dir}/${pname}" | awk '{print $1}')"
    addSize="$(_part_addsize "${pname}")"
    thisSize=$(( thisSize + addSize ))

    local fs_cfg="${img_dir}/config/${pname}_fs_config"
    local ctx_cfg="${img_dir}/config/${pname}_file_contexts"
    mkdir -p "${img_dir}/config"

    python3 "${work_dir}/bin/fspatch.py"      "${img_dir}/${pname}" "${fs_cfg}"  >/dev/null 2>&1
    python3 "${work_dir}/bin/contextpatch.py" "${img_dir}/${pname}" "${ctx_cfg}" >/dev/null 2>&1

    if [[ "${PACK_TYPE}" == "EXT" ]]; then
        # FIX: full path từ BIN_ARCH
        "${BIN_ARCH}/make_ext4fs" -J -T "$(date +%s)" \
            -S "${ctx_cfg}" -l "${thisSize}" -C "${fs_cfg}" \
            -L "${pname}" -a "${pname}" \
            "${img_dir}/${pname}.img" "${img_dir}/${pname}" >/dev/null 2>&1
    elif [[ "${PACK_TYPE}" == "EROFS" ]]; then
        # FIX: full path từ BIN_ARCH
        "${BIN_ARCH}/mkfs.erofs" --quiet -zlz4hc,9 \
            --mount-point "${pname}" \
            --fs-config-file="${fs_cfg}" \
            --file-contexts="${ctx_cfg}" \
            "${img_dir}/${pname}.img" "${img_dir}/${pname}" >/dev/null 2>&1
    else
        error "Unknown PACK_TYPE '${PACK_TYPE}'"
        exit 1
    fi

    if [[ -f "${img_dir}/${pname}.img" ]]; then
        repack "✓ ${pname}.img packed"
    else
        error "✗ ${pname}.img packing FAILED"
        exit 1
    fi
}

# ─── Super image size ─────────────────────────────────────────────────────────
superSize="$(bash "${work_dir}/bin/getSuperSize.sh" "${getvar}")"
repack "Super image size: ${superSize}"
repack "Packing partitions..."

# FIX: export đầy đủ — bao gồm BIN_ARCH từ functions.sh
export -f _pack_partition _part_addsize repack error
export work_dir PACK_TYPE androidVER BIN_ARCH

pids=()
for pname in ${super_list}; do
    _pack_partition "${pname}" &
    pids+=($!)
done
for pid in "${pids[@]}"; do
    wait "$pid" || { error "A partition pack job failed"; exit 1; }
done

# ─── Detect device type ──────────────────────────────────────────────────────
if grep -q "ro.build.ab_update=true" build/baserom/images/vendor/build.prop 2>/dev/null; then
    is_ab_device=true
else
    is_ab_device=false
fi

# ─── Build lpmake arguments ──────────────────────────────────────────────────
repack "Building super.img..."

# FIX: chọn lpmake phù hợp — lpmake_old cho A-only (metadata-slots 2)
# lpmake (new) cho VAB (metadata-slots 3 + virtual-ab)
LPMAKE="${BIN_ARCH}/lpmake"
[[ -x "${LPMAKE}" ]] || { error "lpmake not found at ${LPMAKE}"; exit 1; }

if [[ "${is_ab_device}" == false ]]; then
    repack "Mode: A-only"
    # FIX: dùng lpmake_old cho non-VAB (tương thích slot 2)
    LPMAKE="${BIN_ARCH}/lpmake_old"
    [[ -x "${LPMAKE}" ]] || LPMAKE="${BIN_ARCH}/lpmake"

    lpargs="-F --output build/baserom/images/super.img \
        --metadata-size 65536 --super-name super \
        --metadata-slots 2 --block-size 4096 \
        --device super:${superSize} \
        --group=qti_dynamic_partitions:${superSize}"

    for pname in odm mi_ext system system_ext product vendor; do
        [[ -f "build/baserom/images/${pname}.img" ]] || continue
        subsize="$(du -sb "build/baserom/images/${pname}.img" | awk '{print $1}')"
        repack "  ${pname}: ${subsize} bytes"
        lpargs="${lpargs} --partition ${pname}:none:${subsize}:qti_dynamic_partitions \
            --image ${pname}=build/baserom/images/${pname}.img"
    done
else
    repack "Mode: Virtual A/B"
    lpargs="-F --virtual-ab \
        --output ${work_dir}/build/baserom/images/super.img \
        --metadata-size 65536 --super-name super \
        --metadata-slots 3 --device super:${superSize} \
        --group=qti_dynamic_partitions_a:${superSize} \
        --group=qti_dynamic_partitions_b:${superSize}"

    for pname in ${super_list}; do
        [[ -f "build/baserom/images/${pname}.img" ]] || continue
        subsize="$(du -sb "build/baserom/images/${pname}.img" | awk '{print $1}')"
        repack "  ${pname}: ${subsize} bytes"
        lpargs="${lpargs} \
            --partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a \
            --image ${pname}_a=build/baserom/images/${pname}.img \
            --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
    done
fi

# shellcheck disable=SC2086
"${LPMAKE}" ${lpargs}

if [[ -f "${work_dir}/build/baserom/images/super.img" ]]; then
    repack "super.img packed successfully."
else
    error "super.img packing failed!"
    exit 1
fi

for pname in ${super_list}; do
    rm -f "${work_dir}/build/baserom/images/${pname}.img"
done
