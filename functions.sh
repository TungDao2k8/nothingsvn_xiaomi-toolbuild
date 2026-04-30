#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# functions.sh - Converted for Arch Linux
# Original: https://github.com/TungDao2k8/nothingsvn_xiaomi-toolbuild
#
# Changes vs original:
#   1. abort()   — replaced 'apt install' with pacman/yay (AUR-aware)
#   2. yellow()  — defined; was called in remove_data_encrypt() & abort()
#                  but never declared anywhere in the original (silent bug)
#   3. extract_partition() — 'sudo python3' kept; on Arch 'python3' resolves
#                  correctly after 'pacman -S python'. Noted extract.erofs
#                  binary location (expected in bin/Linux/x86_64/).
#   4. All unquoted $variables in paths and conditions now properly quoted.
#   5. Stripped trailing whitespace / mixed indentation normalised.

WORK_DIR=$(pwd)

# ── Logging helpers ───────────────────────────────────────────────────────────

mods() {
    if [ "$#" -eq 1 ]; then
        echo -e "[MODS] - $1"
    else
        echo "Usage: mods <string>"
    fi
}

info() {
    if [ "$#" -eq 1 ]; then
        echo -e "[INFO] - $1"
    else
        echo "Usage: info <string>"
    fi
}

warn() {
    if [ "$#" -eq 1 ]; then
        echo -e "[WARN] - $1"
    else
        echo "Usage: warn <string>"
    fi
}

# FIX: 'yellow' was called in remove_data_encrypt() and abort() in the original
# but was never defined anywhere — silent no-op / "command not found" at runtime.
# Defined here as a styled warning alias.
yellow() {
    if [ "$#" -eq 1 ]; then
        echo -e "\e[33m[WARN] - $1\e[0m"
    else
        echo "Usage: yellow <string>"
    fi
}

error() {
    if [ "$#" -eq 1 ]; then
        echo -e "[ERROR] - $1"
    else
        echo "Usage: error <string>"
    fi
}

unpack() {
    if [ "$#" -eq 1 ]; then
        echo -e "[UNPACK] - $1"
    else
        echo "Usage: unpack <string>"
    fi
}

unpack_erofs() {
    if [ "$#" -eq 1 ]; then
        echo -e "[UNPACK - EROFS] - $1"
    else
        echo "Usage: unpack_erofs <string>"
    fi
}

unpack_ext() {
    if [ "$#" -eq 1 ]; then
        echo -e "[UNPACK - EXT4] - $1"
    else
        echo "Usage: unpack_ext <string>"
    fi
}

repack() {
    if [ "$#" -eq 1 ]; then
        echo -e "[REPACK] - $1"
    else
        echo "Usage: repack <string>"
    fi
}

upload() {
    if [ "$#" -eq 1 ]; then
        echo -e "[UPLOADING] - $1"
    else
        echo "Usage: upload <string>"
    fi
}

patch() {
    if [ "$#" -eq 1 ]; then
        echo -e "[PATCH] - $1"
    else
        echo "Usage: patch <string>"
    fi
}

# ── Dependency management ─────────────────────────────────────────────────────

exists() {
    command -v "$1" >/dev/null 2>&1
}

# Arch package name map: command → pacman/AUR package
# Extend this map if more tools are added to check().
declare -A _ARCH_PKG_MAP=(
    [unzip]="unzip"
    [aria2c]="aria2"
    [7z]="p7zip"
    [zip]="zip"
    [java]="jre-openjdk-headless"
    [zipalign]="android-tools"
    [python3]="python"
    [zstd]="zstd"
    [bc]="bc"
    [xmlstarlet]="xmlstarlet"
    [aapt]="android-tools"
    [brotli]="brotli"
    [simg2img]="android-tools"
    [lz4]="lz4"
    [jq]="jq"
    [wget]="wget"
    [dialog]="dialog"
    [rclone]="rclone"
    [sshpass]="sshpass"
    [mkfs.erofs]="erofs-utils"
    # AUR-only packages (need yay/paru):
    [payload-dumper-go]="payload-dumper-go"
    [make_ext4fs]="make_ext4fs"
    [lpmake]="lpmake-bin"
)

# AUR-only set: packages that are NOT in the official pacman repos
_AUR_ONLY_PKGS=("payload-dumper-go" "make_ext4fs" "lpmake-bin" "jre-openjdk-headless")

_is_aur_pkg() {
    local pkg="$1"
    for p in "${_AUR_ONLY_PKGS[@]}"; do
        [[ "$p" == "$pkg" ]] && return 0
    done
    return 1
}

_get_aur_helper() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    else
        echo ""
    fi
}

# FIX: Original abort() called 'apt install $1 -y' — replaced with
# pacman/yay so the function works correctly on Arch Linux.
abort() {
    local cmd="$1"
    local pkg="${_ARCH_PKG_MAP[$cmd]:-$cmd}"   # fall back to command name if not mapped
    yellow "Missing '$cmd' — attempting to install package '$pkg'..."

    if _is_aur_pkg "$pkg"; then
        local aur
        aur=$(_get_aur_helper)
        if [[ -z "$aur" ]]; then
            error "AUR helper (yay/paru) not found. Cannot install '$pkg'."
            error "Install yay first:  sudo pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
            exit 1
        fi
        yellow "Installing AUR package '$pkg' via $aur..."
        "$aur" -S --noconfirm "$pkg" || { error "Failed to install '$pkg' from AUR."; exit 1; }
    else
        yellow "Installing '$pkg' via pacman..."
        sudo pacman -S --noconfirm "$pkg" || { error "Failed to install '$pkg' via pacman."; exit 1; }
    fi

    # Re-verify the command is now available
    if ! exists "$cmd"; then
        error "'$cmd' still not found after installing '$pkg'. Please install it manually."
        exit 1
    fi
}

check() {
    for b in "$@"; do
        exists "$b" || abort "$b"
    done
}

# ── Property / fstab utilities ────────────────────────────────────────────────

is_property_exists() {
    if [ "$(grep -c "$1" "$2")" -ne 0 ]; then
        return 0
    else
        return 1
    fi
}

disable_avb_verify() {
    local fstab_files
    fstab_files=$(find "$1" -type f -name "*fstab*")
    info "Disabling avb_verify in files: $fstab_files"
    if [[ -z "$fstab_files" ]]; then
        warn "No fstab files found in $1"
        return
    fi
    for fstab in $fstab_files; do
        if [[ -f "$fstab" ]]; then
            info "Processing $fstab"
            sed -i "s/,avb_keys=.*avbpubkey//g"  "$fstab"
            sed -i "s/,avb=vbmeta_system//g"      "$fstab"
            sed -i "s/,avb=vbmeta_vendor//g"      "$fstab"
            sed -i "s/,avb=vbmeta//g"             "$fstab"
            sed -i "s/,avb//g"                    "$fstab"
            sed -i 's/,avb.*system//g'            "$fstab"
            sed -i 's/,avb,/,/g'                  "$fstab"
            sed -i 's/,avb=.*a,/,/g'              "$fstab"
            sed -i 's/,avb_keys.*key//g'           "$fstab"
        else
            warn "$fstab not found, please check it manually"
        fi
    done
}

remove_data_encrypt() {
    local fstab_files
    fstab_files=$(find "$1" -type f -name "*fstab*")
    info "Disabling data encryption in files: $fstab_files"
    if [[ -z "$fstab_files" ]]; then
        yellow "No fstab files found in $1"
        return
    fi
    for fstab in $fstab_files; do
        if [[ -f "$fstab" ]]; then
            sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" "$fstab"
            sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g"        "$fstab"
            sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g"                                     "$fstab"
            sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g"                                 "$fstab"
            sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g"                                      "$fstab"
            sed -i "s/,metadata_encryption=aes-256-xts//g"                                               "$fstab"
            sed -i "s/,fileencryption=aes-256-xts//g"                                                    "$fstab"
            sed -i "s/fileencryption/encryptable/g"                                                       "$fstab"
            sed -i "s/,fileencryption=ice//g"                                                             "$fstab"
        else
            yellow "$fstab not found, please check it manually"
        fi
    done
}

# ── Partition extraction ──────────────────────────────────────────────────────
# NOTE: extract.erofs is expected as a pre-compiled binary at:
#         bin/Linux/x86_64/extract.erofs
#       If it is absent, install erofs-utils (pacman -S erofs-utils) which
#       provides 'fsck.erofs'. Some builds ship extract.erofs as a symlink to
#       fsck.erofs — if yours doesn't, create one:
#         ln -s /usr/bin/fsck.erofs bin/Linux/x86_64/extract.erofs
#
# NOTE: imgextractor.py is run with 'sudo python3'. On Arch, 'python' is
#       python3, but the 'python3' symlink is also present after:
#         pacman -S python

extract_partition() {
    local part_img="$1"
    local part_name
    part_name=$(basename "${part_img}")
    local target_dir="$2"

    if [[ -f "${part_img}" ]]; then
        local fstype
        fstype=$("${WORK_DIR}/bin/Linux/x86_64/gettype" -i "${part_img}")

        if [[ "$fstype" == "ext" ]]; then
            pack_type="EXT"
            echo "$pack_type" > "${WORK_DIR}/bin/ddevice/fstype.txt"
            sudo python3 "${WORK_DIR}/bin/imgextractor/imgextractor.py" \
                "${part_img}" "${target_dir}" >/dev/null 2>&1 \
                || { error "Extracting ${part_name} failed."; exit 1; }
            unpack "File ${part_name} extracted."
            rm -rf "${part_img}"

        elif [[ "$fstype" == "erofs" ]]; then
            pack_type="EROFS"
            echo "$pack_type" > "${WORK_DIR}/bin/ddevice/fstype.txt"
            # extract.erofs is a bundled binary in bin/Linux/x86_64/
            # See note above if it is missing on your system.
            extract.erofs -x -i "${part_img}" -o "${target_dir}" >/dev/null 2>&1 \
                || { error "Extracting ${part_name} failed."; exit 1; }
            unpack "File ${part_name} extracted."
            rm -rf "${part_img}"

        else
            error "Unable to handle img type for ${part_name}, exit."
            exit 1
        fi
    fi
}

# ── RC file prop insertion ────────────────────────────────────────────────────

setprop_rc() {
    local target_section="$1"   # e.g. "on boot"
    local insert_value="$2"     # e.g. "setprop com.exx.c true"
    local file="$3"

    if [[ ! -f "$file" ]]; then
        echo "Error: file '$file' not found"
        return 1
    fi

    local temp_file="${file}.tmp"
    local matched=0

    > "$temp_file"

    while IFS= read -r line; do
        echo "$line" >> "$temp_file"

        if [[ "$matched" -eq 0 && "$line" == "$target_section" ]]; then
            matched=1
            while IFS= read -r next_line; do
                if [[ "$next_line" =~ ^[[:space:]] ]]; then
                    echo "$next_line" >> "$temp_file"
                else
                    while IFS= read -r value_line; do
                        [[ -n "$value_line" ]] && echo "    $value_line" >> "$temp_file"
                    done <<< "$insert_value"
                    echo "$next_line" >> "$temp_file"
                    break
                fi
            done
        fi
    done < "$file"

    mv "$temp_file" "$file"
}

# ── build.prop editor ─────────────────────────────────────────────────────────

change_prop() {
    local key="$1"
    local new_value="$2"
    local base_dir="$work_dir/build/baserom/images"

    if [[ -z "$key" || -z "$new_value" ]]; then
        echo "[INFO] - Usage: change_prop <property_key> <new_value>" >&2
        return 1
    fi

    if [[ ! -d "$base_dir" ]]; then
        echo "[ERROR] - Directory '$base_dir' not found!" >&2
        return 1
    fi

    new_value=$(echo "$new_value" | tr -d '\r\n')
    local escaped_value
    escaped_value=$(printf '%s\n' "$new_value" | sed 's/[\/&#]/\\&/g')

    while IFS= read -r -d '' file; do
        if grep -q -E "^${key}=" "$file"; then
            sed -i -E "s#^(${key})=.*#\1=${escaped_value}#" "$file"
            echo "[SYSTEM] - Updated '$key'"
            return 0
        fi
    done < <(find "$base_dir" -type f -name "build.prop" -print0)

    # Key not found — append to first build.prop
    local first_file
    first_file=$(find "$base_dir" -type f -name "build.prop" | head -n1)

    if [[ -n "$first_file" ]]; then
        echo "${key}=${new_value}" >> "$first_file"
        echo "[INFO] - Appended '${key}=${new_value}' to $first_file"
        return 0
    else
        echo "[INFO] - No build.prop files found to update or append." >&2
        return 1
    fi
}

# ── Smali file movers ─────────────────────────────────────────────────────────

mvsml() {
    local file_name="$1"
    local target_folder="$2"
    local framework_dir="$3"

    local file_path
    file_path=$(find "$framework_dir" -type f -name "$file_name")

    if [ -z "$file_path" ]; then
        echo "File $file_name not found in any dex folder within $framework_dir."
        return 1
    fi

    local parent_dex_folder relative_path target_path
    parent_dex_folder=$(dirname "$file_path" | sed "s|${framework_dir}/||" | cut -d/ -f1)
    relative_path=$(echo "$file_path" | sed "s|${framework_dir}/${parent_dex_folder}/||")
    target_path="${target_folder}/${relative_path}"

    mkdir -p "$(dirname "$target_path")"
    mv "$file_path" "$target_path"
    echo "Moved $file_name to $target_path"
}

mvdir() {
    local folder_name="$1"
    local target_folder="$2"
    local framework_dir="$3"

    local folder_path
    folder_path=$(find "$framework_dir" -type d -name "$folder_name")

    if [ -z "$folder_path" ]; then
        echo "Folder $folder_name not found in any dex folder within $framework_dir."
        return 1
    fi

    find "$folder_path" -type f -name "*.smali" | while read -r file_path; do
        local parent_dex_folder relative_path target_path
        parent_dex_folder=$(dirname "$file_path" | sed "s|${framework_dir}/||" | cut -d/ -f1)
        relative_path=$(echo "$file_path" | sed "s|${framework_dir}/${parent_dex_folder}/||")
        target_path="${target_folder}/${relative_path}"

        mkdir -p "$(dirname "$target_path")"
        mv "$file_path" "$target_path"
    done

    echo "Moved all .smali files from $folder_name to $target_folder"
}
