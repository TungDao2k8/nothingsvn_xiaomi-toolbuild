#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# packROM.sh - Converted for Arch Linux
# Original: https://github.com/TungDao2k8/nothingsvn_xiaomi-toolbuild
#
# Arch-specific tool availability notes:
#   make_ext4fs  → NOT in official repos; install via AUR: yay -S make_ext4fs
#   lpmake       → NOT in official repos; install via AUR: yay -S lpmake-bin
#                  (or build from AOSP source)
#   mkfs.erofs   → available in official repos: pacman -S erofs-utils
#   python3      → available as 'python':        pacman -S python
#   bc           → available as-is:              pacman -S bc

set -e

# ── Arch-specific tool check ──────────────────────────────────────────────────
check_tools() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[packROM] ERROR: Missing required tools: ${missing[*]}"
        echo "          Install hints:"
        for t in "${missing[@]}"; do
            case "$t" in
                make_ext4fs) echo "            yay -S make_ext4fs" ;;
                lpmake)      echo "            yay -S lpmake-bin  (or build from AOSP)" ;;
                mkfs.erofs)  echo "            sudo pacman -S erofs-utils" ;;
                python3)     echo "            sudo pacman -S python" ;;
                bc)          echo "            sudo pacman -S bc" ;;
                *)           echo "            yay -S $t" ;;
            esac
        done
        exit 1
    fi
}

check_tools bc python3 mkfs.erofs lpmake make_ext4fs

# ── Environment setup ─────────────────────────────────────────────────────────
work_dir=$(pwd)
source "$work_dir/functions.sh"

# Fixed: original had a missing newline between tools_dir and export PATH
tools_dir="${work_dir}/bin/$(uname)/$(uname -m)"
export PATH="${work_dir}/bin/$(uname)/$(uname -m)/:$PATH"

# ── Read device/build metadata ────────────────────────────────────────────────
super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
os_type=$(cat "$work_dir/bin/ddevice/os_type.txt")
base_rom_code=$(cat "$work_dir/bin/ddevice/base_rom_code.txt")
androidVER=$(cat "$work_dir/bin/ddevice/androidver.txt")
rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt")
regionTYPE=$(cat "$work_dir/bin/ddevice/device_type.txt")
device_code=$(cat "$work_dir/bin/ddevice/device_f.txt")
getvar=$(cat "$work_dir/bin/ddevice/device_f.txt")
PACK_TYPE=$(cat "$work_dir/bin/ddevice/fstype.txt")

# ── Version / branch ──────────────────────────────────────────────────────────
if [[ $(git branch --show-current) == "beta" ]]; then
    polyxver="$(cat Version)"
    status="Development"
else
    polyxver="$(cat Version)"
    status="Official"
fi

# ── OS type normalisation ─────────────────────────────────────────────────────
if [[ "$rom_os" == "MIUI" ]]; then
    os_type="MIUI"
else
    os_type="HyperOS"
fi

# ── Generate partition images → super.img ────────────────────────────────────
superSize=$(bash "$work_dir/bin/getSuperSize.sh" "$getvar")
repack "$superSize"
repack "Super image size: ${superSize}"
repack "Packing super.img"

for pname in ${super_list}; do
    if [ -d "$work_dir/build/baserom/images/$pname" ]; then

        thisSize=$(du -sb "$work_dir/build/baserom/images/${pname}" | awk '{print $1}')

        # Padding sizes per partition (vary by Android version)
        if [[ "$androidVER" == "12" ]]; then
            case "$pname" in
                odm)        addSize=104217728 ;;
                system)     addSize=114217728 ;;
                vendor)     addSize=104217728 ;;
                system_ext) addSize=104217728 ;;
                product)    addSize=104217728 ;;
                *)          addSize=8054432   ;;
            esac
        else
            case "$pname" in
                mi_ext)     addSize=4094304   ;;
                odm)        addSize=104217728 ;;
                system)     addSize=104217728 ;;
                vendor)     addSize=104217728 ;;
                system_ext) addSize=104217728 ;;
                product)    addSize=114217728 ;;
                *)          addSize=8054432   ;;
            esac
        fi

        thisSize=$(echo "$thisSize + $addSize" | bc)

        if [[ "$PACK_TYPE" == "EXT" ]]; then
            # ── EXT4 packing ──────────────────────────────────────────────
            # make_ext4fs: AUR package 'make_ext4fs' (not in official repos)
            python3 "$work_dir/bin/fspatch.py" \
                "$work_dir/build/baserom/images/${pname}" \
                "$work_dir/build/baserom/images/config/${pname}_fs_config" \
                >/dev/null 2>&1

            python3 "$work_dir/bin/contextpatch.py" \
                "$work_dir/build/baserom/images/${pname}" \
                "$work_dir/build/baserom/images/config/${pname}_file_contexts" \
                >/dev/null 2>&1

            make_ext4fs \
                -J -T "$(date +%s)" \
                -S "$work_dir/build/baserom/images/config/${pname}_file_contexts" \
                -l "$thisSize" \
                -C "$work_dir/build/baserom/images/config/${pname}_fs_config" \
                -L "${pname}" \
                -a "${pname}" \
                "$work_dir/build/baserom/images/${pname}.img" \
                "$work_dir/build/baserom/images/${pname}" \
                >/dev/null 2>&1

        elif [[ "$PACK_TYPE" == "EROFS" ]]; then
            # ── EROFS packing ─────────────────────────────────────────────
            # mkfs.erofs: pacman -S erofs-utils  (same package name on Arch)
            python3 "$work_dir/bin/fspatch.py" \
                "$work_dir/build/baserom/images/${pname}" \
                "$work_dir/build/baserom/images/config/${pname}_fs_config" \
                >/dev/null 2>&1

            python3 "$work_dir/bin/contextpatch.py" \
                "$work_dir/build/baserom/images/${pname}" \
                "$work_dir/build/baserom/images/config/${pname}_file_contexts" \
                >/dev/null 2>&1

            mkfs.erofs \
                --quiet \
                -zlz4hc,9 \
                --mount-point "${pname}" \
                --fs-config-file="$work_dir/build/baserom/images/config/${pname}_fs_config" \
                --file-contexts="$work_dir/build/baserom/images/config/${pname}_file_contexts" \
                "$work_dir/build/baserom/images/${pname}.img" \
                "$work_dir/build/baserom/images/${pname}" \
                >/dev/null 2>&1

        else
            error "Unable to handle img type '${PACK_TYPE}', exit."
            exit 1
        fi

        if [ -f "$work_dir/build/baserom/images/${pname}.img" ]; then
            repack "Packing [${pname}.img] success"
        else
            repack "Packing [${pname}] failed!"
        fi
    fi
done

# ── A/B detection ─────────────────────────────────────────────────────────────
if grep -q "ro.build.ab_update=true" build/baserom/images/vendor/build.prop; then
    is_ab_device=true
else
    is_ab_device=false
fi

# ── lpmake: build logical partition image ─────────────────────────────────────
# lpmake: AUR package 'lpmake-bin' (not in official Arch repos)
# The darwin stat branch is preserved for cross-platform awareness,
# but du -sb is standard on Linux/Arch and works correctly here.

if [[ "$is_ab_device" == false ]]; then
    repack "Packing super.img for A-only device"
    lpargs="-F --output build/baserom/images/super.img \
--metadata-size 65536 \
--super-name super \
--metadata-slots 2 \
--block-size 4096 \
--device super:${superSize} \
--group=qti_dynamic_partitions:${superSize}"

    for pname in odm mi_ext system system_ext product vendor; do
        if [ -f "build/baserom/images/${pname}.img" ]; then
            # Arch/Linux: du -sb gives bytes directly (no darwin workaround needed)
            subsize=$(du -sb "build/baserom/images/${pname}.img" | awk '{print $1}')
            repack "Super sub-partition [$pname] size: [$subsize]"
            lpargs="$lpargs \
--partition ${pname}:none:${subsize}:qti_dynamic_partitions \
--image ${pname}=build/baserom/images/${pname}.img"
            unset subsize
        fi
    done

else
    repack "Packing super.img for V-AB device"
    lpargs="-F --virtual-ab \
--output $work_dir/build/baserom/images/super.img \
--metadata-size 65536 \
--super-name super \
--metadata-slots 3 \
--device super:${superSize} \
--group=qti_dynamic_partitions_a:${superSize} \
--group=qti_dynamic_partitions_b:${superSize}"

    for pname in ${super_list}; do
        if [ -f "build/baserom/images/${pname}.img" ]; then
            subsize=$(du -sb "build/baserom/images/${pname}.img" | awk '{print $1}')
            repack "Super sub-partition [$pname] size: [$subsize]"
            lpargs="$lpargs \
--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a \
--image ${pname}_a=build/baserom/images/${pname}.img \
--partition ${pname}_b:none:0:qti_dynamic_partitions_b"
            unset subsize
        fi
    done
fi

# ── Run lpmake ────────────────────────────────────────────────────────────────
# shellcheck disable=SC2086
lpmake $lpargs

if [ -f "$work_dir/build/baserom/images/super.img" ]; then
    repack "Successfully packed super.img."
else
    repack "Unable to pack super.img."
    exit 1
fi

# ── Cleanup individual partition images ───────────────────────────────────────
for pname in ${super_list}; do
    rm -rf "$work_dir/build/baserom/images/${pname}.img"
done
