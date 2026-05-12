#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# build.sh — NothingsVN AutoBuild main script

set -euo pipefail

baserom="$1"
work_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Environment setup ───────────────────────────────────────────────────────
# FIX: dùng uname/uname -m dynamic thay vì hardcode
export PATH="${work_dir}/bin/$(uname)/$(uname -m):${PATH}"

# FIX: chmod +x chỉ binary executables, không 777 tất cả
find "${work_dir}/bin" -maxdepth 3 -type f \
    ! -name "*.py" ! -name "*.sh" ! -name "*.txt" \
    ! -name "*.conf" ! -name "*.json" ! -name "*.jar" \
    -exec chmod +x {} +
find "${work_dir}/bin" -name "*.sh" -exec chmod +x {} +

source "${work_dir}/functions.sh"

# ─── Resolve simg2img: bundled binary links against libc++ (LLVM); fall back  ─
# to the system binary from android-sdk-libsparse-utils if the shared lib is   ─
# missing (common on stock GitHub Actions runners without libc++1 installed).   ─
# NOTE: BIN_ARCH is already prepended to PATH above, so we must exclude it     ─
# when searching for the system binary to avoid resolving the same file again.  ─
_bundled_simg2img="${BIN_ARCH}/simg2img"
if ldd "${_bundled_simg2img}" 2>&1 | grep -q "not found"; then
    # Search for simg2img on PATH with BIN_ARCH stripped out
    _sys_simg2img="$(PATH="${PATH//${BIN_ARCH}:/}" command -v simg2img 2>/dev/null || true)"
    if [[ -n "${_sys_simg2img}" ]] && [[ ! "${_sys_simg2img}" -ef "${_bundled_simg2img}" ]]; then
        info "Bundled simg2img missing libc++.so — symlinking to system: ${_sys_simg2img}"
        ln -sf "${_sys_simg2img}" "${_bundled_simg2img}"
    else
        error "simg2img unavailable: bundled binary is missing libc++.so and no system fallback was found. Add 'libc++1' to setup.sh."
        exit 1
    fi
fi
unset _bundled_simg2img _sys_simg2img

load_version
check unzip aria2c 7z zip java zipalign python3 zstd bc xmlstarlet aapt
validate_config

# ─── Clean previous build ────────────────────────────────────────────────────
rm -rf "${work_dir}/out" "${work_dir}/build" \
       "${work_dir}/app" "${work_dir}/tmp"   "${work_dir}/config"
find . -type d -name 'miui_*' -exec rm -rf {} + 2>/dev/null || true

unpack "Files cleaned up."
mkdir -p build/baserom/images/

# ─── Download ROM (if URL) & gather device info ──────────────────────────────
# FIX: getROM.sh phải chạy TRƯỚC khi detect ROM type
source "${work_dir}/bin/ddevice/getROM.sh" "${baserom}"
baserom="${baserom}"

# ─── ROM type detection ───────────────────────────────────────────────────────
baserom_type=""
is_base_rom_eu=false
is_tgz=false

if [[ "${baserom}" == *.tgz || "${baserom}" == *.tar.gz ]]; then
    # Official HyperOS/MIUI fastboot ROM — tar.gz archive with partition images
    is_tgz=true
    tgz_listing="$(tar -tf "${baserom}" 2>/dev/null)"
    if echo "${tgz_listing}" | grep -qE "(^|/)images/[^/]+\.img$"; then
        baserom_type="tgz_images"
        unpack "Found partition images in tgz — ROM validation passed."
    elif echo "${tgz_listing}" | grep -q "payload\.bin"; then
        baserom_type="tgz_payload"
        super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
        unpack "Found payload.bin in tgz — ROM validation passed."
    else
        error "Unrecognised TGZ ROM format — cannot unpack."
        exit 1
    fi
else
    # Standard ZIP-based ROM
    zip_listing="$(unzip -l "${baserom}" 2>/dev/null)" || {
        error "Cannot read ROM archive (not a valid ZIP): ${baserom}"
        exit 1
    }
    if echo "${zip_listing}" | grep -q "payload\.bin"; then
        baserom_type="payload"
        super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
        unpack "Found payload.bin — ROM validation passed."
    elif echo "${zip_listing}" | grep -qE "\.br$"; then
        baserom_type="br"
        super_list="system vendor product odm system_ext mi_ext"
        unpack "Found brotli files — ROM validation passed."
    elif echo "${zip_listing}" | grep -q "images/super\.img"; then
        is_base_rom_eu=true
        unpack "Found super.img.* files — ROM validation passed."
    else
        error "Unrecognised ROM format — cannot unpack."
        exit 1
    fi
fi

echo "${baserom_type}" > "${work_dir}/bin/ddevice/romtype.txt"

# ─── Step 1: extract archive ─────────────────────────────────────────────────
if [[ "${is_tgz}" == true ]]; then
    unpack "Extracting tgz archive..."
    tar -xf "${baserom}" -C build/baserom/ \
        || { error "Extracting tgz failed"; exit 1; }

    # Flatten: tgz may have a top-level dir (e.g. mondrian_tw_global_.../images/*.img).
    # Move every *.img found outside build/baserom/images/ into that directory.
    while IFS= read -r img_path; do
        mv "${img_path}" "${work_dir}/build/baserom/images/" 2>/dev/null || true
    done < <(find "${work_dir}/build/baserom" -name "*.img" \
                  -not -path "${work_dir}/build/baserom/images/*" 2>/dev/null)

    unpack "tgz extracted."

elif [[ "${baserom_type}" == "payload" ]]; then
    unpack "Extracting payload.bin..."
    unzip -q "${baserom}" payload.bin -d build/baserom \
        || { error "Extracting payload.bin failed"; exit 1; }
    unpack "payload.bin extracted."

elif [[ "${baserom_type}" == "br" ]]; then
    unpack "Extracting *.new.dat.br files..."
    unzip -q "${baserom}" -d build/baserom \
        || { error "Extracting new.dat.br failed"; exit 1; }
    unpack "new.dat.br files extracted."

elif [[ "${is_base_rom_eu}" == true ]]; then
    unpack "Extracting super.img.*..."
    unzip -q "${baserom}" 'images/*' -d build/baserom \
        || { error "Extracting super.img failed"; exit 1; }

    unpack "Merging super.img.* → super.img"
    # FIX: dùng binary từ BIN_ARCH
    "${BIN_ARCH}/simg2img" build/baserom/images/super.img.* build/baserom/images/super.img
    rm -f build/baserom/images/super.img.*
    mv build/baserom/images/super.img build/baserom/super.img

    if ls build/baserom/images/cust.img.* >/dev/null 2>&1; then
        "${BIN_ARCH}/simg2img" build/baserom/images/cust.img.* build/baserom/images/cust.img
        rm -f build/baserom/images/cust.img.*
    fi
    unpack "super.img extracted."
fi

# ─── Step 2: unpack payload / dat.br / super.img ─────────────────────────────
if [[ "${baserom_type}" == "tgz_images" ]]; then
    images_dir="${work_dir}/build/baserom/images"

    if [[ -f "${images_dir}/super.img" ]]; then
        # super.img from fastboot ROM is a sparse image — convert to raw first
        unpack "Converting super.img (sparse → raw)..."
        "${BIN_ARCH}/simg2img" "${images_dir}/super.img" "${images_dir}/super.img.raw" \
            || { error "simg2img on super.img failed"; exit 1; }
        mv "${images_dir}/super.img.raw" "${images_dir}/super.img"

        unpack "Unpacking super.img logical partitions in parallel..."
        # Match any block device name (not just "super") — some ROMs use different names.
        # lpunpack.py --info layout format: "<device>: <start> .. <end>: <partition> (<sectors> sectors)"
        super_list="$(python3 "${work_dir}/bin/lpunpack.py" --info "${images_dir}/super.img" 2>/dev/null \
                      | awk '$3 == ".." && $5 != "" {print $5}')"

        _lpunpack_binary_used=false
        if [[ -z "${super_list}" ]]; then
            # lpunpack.py produced no output — likely a newer LP metadata format (HyperOS 3+).
            # Fall back to the compiled binary which handles format differences better.
            warn "lpunpack.py returned empty list — falling back to ${BIN_ARCH}/lpunpack binary"
            _lp_tmp="${images_dir}/_lp_extract"
            mkdir -p "${_lp_tmp}"
            "${BIN_ARCH}/lpunpack" "${images_dir}/super.img" "${_lp_tmp}" 2>/dev/null || true
            for _img in "${_lp_tmp}"/*.img; do
                [[ -f "${_img}" ]] || continue
                _pname="$(basename "${_img}" .img)"
                if [[ "${_pname}" == *_a ]]; then
                    mv "${_img}" "${images_dir}/${_pname%_a}.img"
                    super_list="${super_list} ${_pname%_a}"
                else
                    mv "${_img}" "${images_dir}/${_pname}.img"
                    super_list="${super_list} ${_pname}"
                fi
            done
            rm -rf "${_lp_tmp}"
            super_list="${super_list# }"
            _lpunpack_binary_used=true
        fi

        if [[ "${_lpunpack_binary_used}" == false ]]; then
            pids=()
            for i in ${super_list}; do
                (
                    if [[ "$i" == *_a ]]; then
                        base="${i%_a}"
                        python3 "${work_dir}/bin/lpunpack.py" -p "${i}" \
                            "${images_dir}/super.img" "${images_dir}" >/dev/null 2>&1
                        mv "${images_dir}/${i}.img" "${images_dir}/${base}.img"
                    else
                        python3 "${work_dir}/bin/lpunpack.py" -p "${i}" \
                            "${images_dir}/super.img" "${images_dir}" >/dev/null 2>&1
                    fi
                    echo "  ✓ ${i}"
                ) &
                pids+=($!)
            done
            for pid in "${pids[@]}"; do wait "$pid" || { error "lpunpack on super.img failed"; exit 1; }; done
            super_list="$(echo "${super_list}" | sed 's/_a//g')"
        fi
        unset _lpunpack_binary_used _lp_tmp _img _pname
    else
        # No super.img — collect only ext/erofs filesystem images, skip raw partitions
        super_list=""
        for img_path in "${images_dir}/"*.img; do
            [[ -f "${img_path}" ]] || continue
            fs_type="$("${BIN_ARCH}/gettype" -i "${img_path}" 2>/dev/null || echo unknown)"
            [[ "${fs_type}" == "ext" || "${fs_type}" == "erofs" ]] || continue
            part_name="$(basename "${img_path}" .img)"
            super_list="${super_list} ${part_name}"
        done
        super_list="${super_list# }"
    fi

    [[ -n "${super_list}" ]] || { error "No extractable partitions found in tgz ROM"; exit 1; }
    unpack "tgz_images: logical partitions to extract: ${super_list}"

elif [[ "${baserom_type}" == "tgz_payload" || "${baserom_type}" == "payload" ]]; then
    unpack "Dumping payload.bin..."
    # FIX: payload-dumper-go từ BIN_ARCH
    "${BIN_ARCH}/payload-dumper-go" -o build/baserom/images/ build/baserom/payload.bin >/dev/null 2>&1 \
        || { error "Dumping payload.bin failed"; exit 1; }

elif [[ "${baserom_type}" == "br" ]]; then
    super_list="$(awk '/^add / {print $2}' build/baserom/dynamic_partitions_op_list)"
    unpack "Unpacking brotli partitions in parallel..."

    # FIX: parallelise brotli decompress + sdat2img
    _unpack_br_part() {
        local p="$1"
        brotli -d "build/baserom/${p}.new.dat.br" >/dev/null 2>&1
        python3 "${work_dir}/bin/Linux/x86_64/sdat2img.py" \
            "build/baserom/${p}.transfer.list" \
            "build/baserom/${p}.new.dat" \
            "build/baserom/images/${p}.img" >/dev/null 2>&1
        rm -f "build/baserom/${p}.new.dat" \
              "build/baserom/${p}.new.dat.br" \
              "build/baserom/${p}.transfer.list" \
              build/baserom/${p}.patch.* 2>/dev/null || true
        echo "  ✓ ${p}"
    }
    export -f _unpack_br_part
    export work_dir

    pids=()
    for brotlipart in ${super_list}; do
        _unpack_br_part "${brotlipart}" &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || { error "brotli unpack failed"; exit 1; }; done

elif [[ "${is_base_rom_eu}" == true ]]; then
    unpack "Unpacking super.img partitions in parallel..."
    super_list="$(python3 "${work_dir}/bin/lpunpack.py" --info build/baserom/super.img 2>/dev/null \
                  | awk '$3 == ".." && $5 != "" {print $5}')"

    pids=()
    for i in ${super_list}; do
        (
            if [[ "$i" == *_a ]]; then
                base="${i%_a}"
                python3 "${work_dir}/bin/lpunpack.py" -p "${i}" build/baserom/super.img build/baserom/images >/dev/null 2>&1
                mv "build/baserom/images/${i}.img" "build/baserom/images/${base}.img"
            else
                python3 "${work_dir}/bin/lpunpack.py" -p "${i}" build/baserom/super.img build/baserom/images >/dev/null 2>&1
            fi
            echo "  ✓ ${i}"
        ) &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || { error "lpunpack failed"; exit 1; }; done
    super_list="$(echo "${super_list}" | sed 's/_a//g')"
fi

# ─── Step 3: extract partitions in parallel ───────────────────────────────────
unpack "Extracting partitions in parallel..."
pids=()
for part in ${super_list}; do
    img="${work_dir}/build/baserom/images/${part}.img"
    [[ -f "${img}" ]] || continue
    extract_partition "${img}" "${work_dir}/build/baserom/images" &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" || { error "Partition extraction failed"; exit 1; }; done

PACK_TYPE="$(cat "${work_dir}/bin/ddevice/fstype.txt")"
echo "${device_f}" > "${work_dir}/bin/ddevice/device_f.txt"
getvar="$(cat "${work_dir}/bin/ddevice/device_f.txt")"

rm -rf build/baserom/payload.bin build/baserom/images/super.img config

# ─── Step 4: gather device info ──────────────────────────────────────────────
mods "Gathering device information..."
bash "${work_dir}/bin/ddevice/getname.sh" "${getvar}"
bash "${work_dir}/bin/ddevice/fetchINFO.sh"
info "Device info done."

# ─── Step 5: apply patches & mods ────────────────────────────────────────────
# FIX: guard mỗi script — chỉ chạy nếu file tồn tại
bash "${work_dir}/bin/package/patchpackage.sh"

_run_if_exists() {
    local script="$1"
    if [[ -f "$script" ]]; then
        bash "$script"
    else
        warn "Optional script not found, skipping: $script"
    fi
}

# Supported: MIUI13, MIUI14, HyperOS 1 (OS1), HyperOS 2 (OS2), HyperOS 3 (OS3)
# Each insmod.sh guards itself with rom_os check — only the matching one executes.
_run_if_exists "${work_dir}/bin/modfile/MIUI13/insmod.sh"
_run_if_exists "${work_dir}/bin/modfile/MIUI14/insmod.sh"
_run_if_exists "${work_dir}/bin/modfile/OS1/insmod.sh"
_run_if_exists "${work_dir}/bin/modfile/OS2/insmod.sh"
_run_if_exists "${work_dir}/bin/modfile/OS3/insmod.sh"
_run_if_exists "${work_dir}/bin/modfile/Universal/insfile.sh"
_run_if_exists "${work_dir}/bin/modfile/UpdateFile/insupdate.sh"

info "Build pipeline complete."
