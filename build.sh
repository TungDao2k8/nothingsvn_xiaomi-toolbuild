#!/usr/bin/env bash
# build.sh - Converted for Arch Linux
# Original: https://github.com/TungDao2k8/nothingsvn_xiaomi-toolbuild
# Changes: replaced Debian/Ubuntu package logic with pacman/yay equivalents,
#          added Arch-specific dependency installer, added missing tool checks.

baserom="$1"
work_dir=$(pwd)

# ── Arch Linux: dependency map ────────────────────────────────────────────────
# Maps the command name the script checks → pacman/AUR package that provides it.
declare -A ARCH_PKGS=(
    [unzip]="unzip"
    [aria2c]="aria2"
    [7z]="p7zip"
    [zip]="zip"
    [java]="jre-openjdk-headless"
    [zipalign]="android-tools"   # AUR: android-sdk-build-tools (if not found)
    [python3]="python"
    [zstd]="zstd"
    [bc]="bc"
    [xmlstarlet]="xmlstarlet"
    [aapt]="android-tools"       # AUR fallback: android-sdk-build-tools
    [brotli]="brotli"
    [simg2img]="android-tools"
    [payload-dumper-go]="payload-dumper-go"   # AUR
)

# AUR packages that need yay/paru instead of pacman
AUR_ONLY=("payload-dumper-go" "android-sdk-build-tools")

install_pkg_arch() {
    local cmd="$1"
    local pkg="${ARCH_PKGS[$cmd]:-$cmd}"

    # Check if it's an AUR-only package
    local is_aur=false
    for aur in "${AUR_ONLY[@]}"; do
        [[ "$pkg" == "$aur" ]] && is_aur=true && break
    done

    if $is_aur; then
        if command -v yay &>/dev/null; then
            echo "[arch] Installing AUR package: $pkg (via yay)"
            yay -S --noconfirm "$pkg"
        elif command -v paru &>/dev/null; then
            echo "[arch] Installing AUR package: $pkg (via paru)"
            paru -S --noconfirm "$pkg"
        else
            echo "[arch] ERROR: '$cmd' requires the AUR package '$pkg'."
            echo "       Install an AUR helper first (yay or paru), then run:"
            echo "         yay -S $pkg"
            exit 1
        fi
    else
        echo "[arch] Installing package: $pkg (via pacman)"
        sudo pacman -S --noconfirm "$pkg"
    fi
}

# ── Override the check() function before sourcing functions.sh ────────────────
# The original functions.sh likely calls apt-get. We shadow check() here so
# it uses pacman/yay on Arch instead.
check() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "[arch] Missing tool: $cmd — attempting to install..."
            install_pkg_arch "$cmd"
            # Re-verify after install
            if ! command -v "$cmd" &>/dev/null; then
                echo "[arch] ERROR: '$cmd' still not found after install attempt."
                echo "       Please install it manually and re-run."
                exit 1
            fi
        fi
    done
}

# ── PATH / permissions (unchanged) ───────────────────────────────────────────
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$PATH
chmod 777 ${work_dir}/bin/*
chmod 777 ${work_dir}/bin/Linux/x86_64/*

# Source project functions AFTER our check() override so it takes precedence
source "$work_dir/functions.sh"

# ── Version / branch detection (unchanged) ───────────────────────────────────
if [[ $(git branch --show-current) == "beta" ]]; then
    polyxver="$(cat Version)"
    status="Development"
else
    polyxver="$(cat Version)"
    status="Official"
fi

# ── Dependency check (now handled by Arch-aware check() above) ───────────────
check unzip aria2c 7z zip java zipalign python3 zstd bc xmlstarlet aapt brotli simg2img

# ── Clean output dirs (unchanged) ────────────────────────────────────────────
rm -rf "$work_dir/out"
rm -rf "$work_dir/build"

source "$work_dir/bin/ddevice/getROM.sh" "$baserom"

# ── ROM type detection (unchanged) ───────────────────────────────────────────
if unzip -l "${baserom}" | grep -q "payload.bin"; then
    baserom_type="payload"
    echo "$baserom_type" > "$work_dir/bin/ddevice/romtype.txt"
    unpack "Found payload.bin file"
    super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
    unpack "ROM validation passed."

elif unzip -l "${baserom}" | grep -q "br$"; then
    baserom_type="br"
    echo "$baserom_type" > "$work_dir/bin/ddevice/romtype.txt"
    super_list="system vendor product odm system_ext mi_ext"
    unpack "Found brotli file"
    unpack "ROM validation passed."

elif unzip -l "${baserom}" | grep -q "images/super.img*"; then
    unpack "Found super.img.* files"
    is_base_rom_eu=true
    unpack "ROM validation passed."

else
    error "Unpack failed"
    exit 1
fi

# ── Cleanup stale dirs (unchanged) ───────────────────────────────────────────
rm -rf app tmp config build/baserom/
find . -type d -name 'miui_*' | xargs rm -rf

unpack "Files cleaned up."
mkdir -p build/baserom/images/

# ── Extract partitions by ROM type (unchanged) ───────────────────────────────
if [[ "${baserom_type}" == 'payload' ]]; then
    unpack "Extracting payload.bin..."
    unzip "${baserom}" payload.bin -d build/baserom >/dev/null 2>&1 \
        || error "Extracting payload.bin error"
    unpack "File payload.bin extracted."

elif [[ "${baserom_type}" == 'br' ]]; then
    unpack "Extracting *.new.dat.br files"
    unzip "${baserom}" -d build/baserom >/dev/null 2>&1 \
        || error "Extracting new.dat.br error"
    unpack "File new.dat.br extracted."

elif [[ "${is_base_rom_eu}" == true ]]; then
    unpack "Extracting files from BASEROM [super.img]"
    unzip "${baserom}" 'images/*' -d build/baserom >/dev/null 2>&1 \
        || error "Extracting [super.img] error"
    unpack "Merging super.img.* into super.img"
    simg2img build/baserom/images/super.img.* build/baserom/images/super.img
    rm -rf build/baserom/images/super.img.*
    mv build/baserom/images/super.img build/baserom/super.img
    unpack "[super.img] extracted."
    if [[ -f build/baserom/images/cust.img.0 ]]; then
        simg2img build/baserom/images/cust.img.* build/baserom/images/cust.img
        rm -rf build/baserom/images/cust.img.*
    fi
fi

# ── Unpack payload / brotli / super (unchanged) ──────────────────────────────
if [[ "${baserom_type}" == 'payload' ]]; then
    unpack "Unpacking payload.bin"
    payload-dumper-go -o build/baserom/images/ build/baserom/payload.bin >/dev/null 2>&1 \
        || error "Unpacking payload.bin failed"

elif [[ "${baserom_type}" == 'br' ]]; then
    super_list=$(grep "add " build/baserom/dynamic_partitions_op_list | awk '{ print $2 }')
    unpack "Unpacking new.dat.br"
    for brotlipart in ${super_list}; do
        brotli -d "build/baserom/${brotlipart}.new.dat.br" >/dev/null 2>&1
        python3 "$work_dir/bin/Linux/x86_64/sdat2img.py" \
            "build/baserom/${brotlipart}.transfer.list" \
            "build/baserom/${brotlipart}.new.dat" \
            "build/baserom/images/${brotlipart}.img" >/dev/null 2>&1
        rm -rf "build/baserom/${brotlipart}.new.dat"* \
               "build/baserom/${brotlipart}.transfer.list" \
               "build/baserom/${brotlipart}.patch."*
    done

elif [[ "${is_base_rom_eu}" == true ]]; then
    unpack "Unpacking BASEROM [super.img]"
    super_list=$(python3 bin/lpunpack.py --info build/baserom/super.img \
        | grep "super:" | awk '{ print $5 }')
    for i in ${super_list}; do
        if [[ "$i" == *_a ]]; then
            i="${i%_a}"
            python3 bin/lpunpack.py -p "${i}_a" \
                build/baserom/super.img build/baserom/images >/dev/null 2>&1
            mv "build/baserom/images/${i}_a.img" "build/baserom/images/${i}.img"
        else
            python3 bin/lpunpack.py -p "${i}" \
                build/baserom/super.img build/baserom/images >/dev/null 2>&1
        fi
    done
    super_list=$(echo "$super_list" | sed 's/_a//g')
fi

# ── Extract all super partitions (unchanged) ─────────────────────────────────
for part in ${super_list}; do
    extract_partition "$work_dir/build/baserom/images/${part}.img" \
                      "$work_dir/build/baserom/images"
    PACK_TYPE=$(cat "$work_dir/bin/ddevice/fstype.txt")
done

echo "$device_f" > "$work_dir/bin/ddevice/device_f.txt"
getvar=$(cat "$work_dir/bin/ddevice/device_f.txt")

rm -rf config

[[ -f "$work_dir/${baserom}.zip" ]] && rm -rf "${baserom}.zip"

rm -rf build/baserom/payload.bin
rm -rf build/baserom/images/super.img

# ── Device info & mod scripts (unchanged) ────────────────────────────────────
mods "Gathering Device Information"
bash "$work_dir/bin/ddevice/getname.sh"  "$getvar"
bash "$work_dir/bin/ddevice/fetchINFO.sh"
info "Done"

bash "$work_dir/bin/package/patchpackage.sh"
bash "$work_dir/bin/modfile/MIUI13/insmod.sh"
bash "$work_dir/bin/modfile/MIUI14/insmod.sh"
bash "$work_dir/bin/modfile/OS1/insmod.sh"
bash "$work_dir/bin/modfile/OS2/insmod.sh"
bash "$work_dir/bin/modfile/OS3/insmod.sh"
bash "$work_dir/bin/modfile/Universal/insfile.sh"
bash "$work_dir/bin/modfile/UpdateFile/insupdate.sh"
