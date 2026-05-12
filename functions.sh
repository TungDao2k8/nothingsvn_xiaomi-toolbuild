#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# functions.sh — NothingsVN AutoBuild shared library

set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Bin dir (dynamic OS + arch, no hardcode) ────────────────────────────────
BIN_ARCH="${WORK_DIR}/bin/$(uname)/$(uname -m)"

# ─── Logging ─────────────────────────────────────────────────────────────────
_log() { echo -e "[${1}] - ${2}"; }

mods()        { [[ $# -eq 1 ]] && _log "MODS"          "$1" || echo "Usage: mods <string>"; }
info()        { [[ $# -eq 1 ]] && _log "INFO"          "$1" || echo "Usage: info <string>"; }
warn()        { [[ $# -eq 1 ]] && _log "WARN"          "$1" || echo "Usage: warn <string>"; }
error()       { [[ $# -eq 1 ]] && _log "ERROR"         "$1" || echo "Usage: error <string>"; }
unpack()      { [[ $# -eq 1 ]] && _log "UNPACK"        "$1" || echo "Usage: unpack <string>"; }
unpack_erofs(){ [[ $# -eq 1 ]] && _log "UNPACK-EROFS"  "$1" || echo "Usage: unpack_erofs <string>"; }
unpack_ext()  { [[ $# -eq 1 ]] && _log "UNPACK-EXT4"   "$1" || echo "Usage: unpack_ext <string>"; }
repack()      { [[ $# -eq 1 ]] && _log "REPACK"        "$1" || echo "Usage: repack <string>"; }
upload()      { [[ $# -eq 1 ]] && _log "UPLOADING"     "$1" || echo "Usage: upload <string>"; }
patch()       { [[ $# -eq 1 ]] && _log "PATCH"         "$1" || echo "Usage: patch <string>"; }

# ─── Version / branch detection ──────────────────────────────────────────────
load_version() {
    polyxver="$(cat "${WORK_DIR}/Version")"
    local branch
    branch="$(git -C "${WORK_DIR}" branch --show-current 2>/dev/null || echo 'main')"
    [[ "$branch" == "beta" ]] && status="Development" || status="Official"
    export polyxver status
}

# ─── Dependency check ────────────────────────────────────────────────────────
exists() { command -v "$1" >/dev/null 2>&1; }

abort() {
    warn "Missing '$1', installing..."
    sudo apt-get install -y "$1" || { error "Failed to install '$1'"; exit 1; }
}

check() {
    for b in "$@"; do
        exists "$b" || abort "$b"
    done
}

# ─── Property helpers ────────────────────────────────────────────────────────
is_property_exists() {
    grep -q "$1" "$2"
}

# ─── AVB / encryption removal ────────────────────────────────────────────────
disable_avb_verify() {
    local dir="$1"
    local fstab_files
    mapfile -t fstab_files < <(find "$dir" -type f -name "*fstab*")

    if [[ ${#fstab_files[@]} -eq 0 ]]; then
        warn "No fstab files found in $dir"; return
    fi

    info "Disabling avb_verify in ${#fstab_files[@]} fstab file(s)"
    for fstab in "${fstab_files[@]}"; do
        [[ -f "$fstab" ]] || { warn "$fstab not found"; continue; }
        sed -i \
            -e 's/,avb_keys=[^,]*avbpubkey//g' \
            -e 's/,avb=vbmeta_system//g'        \
            -e 's/,avb=vbmeta_vendor//g'        \
            -e 's/,avb=vbmeta//g'               \
            -e 's/,avb\b//g'                    \
            -e 's/,avb.*system//g'              \
            -e 's/,avb,/,/g'                    \
            -e 's/,avb=.*a,/,/g'               \
            -e 's/,avb_keys[^,]*key//g'         \
            "$fstab"
    done
}

remove_data_encrypt() {
    local dir="$1"
    local fstab_files
    mapfile -t fstab_files < <(find "$dir" -type f -name "*fstab*")

    if [[ ${#fstab_files[@]} -eq 0 ]]; then
        warn "No fstab files found in $dir"; return
    fi

    info "Disabling data encryption in ${#fstab_files[@]} fstab file(s)"
    for fstab in "${fstab_files[@]}"; do
        [[ -f "$fstab" ]] || { warn "$fstab not found"; continue; }
        sed -i \
            -e 's/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g' \
            -e 's/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g'       \
            -e 's/,fileencryption=aes-256-xts:aes-256-cts:v2//g'                                    \
            -e 's/,metadata_encryption=aes-256-xts:wrappedkey_v0//g'                                \
            -e 's/,fileencryption=aes-256-xts:wrappedkey_v0//g'                                     \
            -e 's/,metadata_encryption=aes-256-xts//g'                                              \
            -e 's/,fileencryption=aes-256-xts//g'                                                   \
            -e 's/fileencryption/encryptable/g'                                                      \
            -e 's/,fileencryption=ice//g'                                                            \
            "$fstab"
    done
}

# ─── Partition extraction ─────────────────────────────────────────────────────
# FIX: dùng ${BIN_ARCH} thay vì hardcode Linux/x86_64
extract_partition() {
    local part_img="$1"
    local target_dir="$2"
    local part_name
    part_name="$(basename "${part_img}")"

    [[ -f "${part_img}" ]] || return 0

    # Validate binary exists before calling
    [[ -x "${BIN_ARCH}/gettype" ]] || { error "gettype not found at ${BIN_ARCH}/gettype"; exit 1; }

    local fs_type
    fs_type="$("${BIN_ARCH}/gettype" -i "${part_img}")"

    case "${fs_type}" in
        ext)
            echo "EXT" > "${WORK_DIR}/bin/ddevice/fstype.txt"
            python3 "${WORK_DIR}/bin/imgextractor/imgextractor.py" \
                "${part_img}" "${target_dir}" >/dev/null 2>&1 \
                || { error "Extracting ${part_name} failed."; exit 1; }
            unpack "File ${part_name} extracted. [EXT4]"
            ;;
        erofs)
            echo "EROFS" > "${WORK_DIR}/bin/ddevice/fstype.txt"
            # FIX: dùng BIN_ARCH dynamic, không hardcode
            [[ -x "${BIN_ARCH}/extract.erofs" ]] || { error "extract.erofs not found at ${BIN_ARCH}"; exit 1; }
            "${BIN_ARCH}/extract.erofs" -x -i "${part_img}" -o "${target_dir}" >/dev/null 2>&1 \
                || { error "Extracting ${part_name} failed."; exit 1; }
            unpack "File ${part_name} extracted. [EROFS]"
            ;;
        *)
            error "Unknown filesystem type '${fs_type}' for ${part_name}, cannot handle."
            exit 1
            ;;
    esac

    rm -f "${part_img}"
}

# ─── build.prop helpers ──────────────────────────────────────────────────────
change_prop() {
    local key="$1"
    local new_value="$2"
    local base_dir="${work_dir}/build/baserom/images"

    [[ -z "$key" || -z "$new_value" ]] && { error "Usage: change_prop <key> <value>"; return 1; }
    [[ -d "$base_dir" ]] || { error "Directory '$base_dir' not found!"; return 1; }

    new_value="$(echo "$new_value" | tr -d '\r\n')"
    local escaped_value
    escaped_value="$(printf '%s\n' "$new_value" | sed 's/[\/&#]/\\&/g')"

    local target_file
    target_file="$(grep -rl --include="build.prop" -m1 "^${key}=" "$base_dir" 2>/dev/null | head -n1)"

    if [[ -n "$target_file" ]]; then
        sed -i -E "s#^(${key})=.*#\1=${escaped_value}#" "$target_file"
        info "Updated '${key}' in $(basename "$(dirname "$target_file")")/build.prop"
        return 0
    fi

    local first_file
    first_file="$(find "$base_dir" -name "build.prop" | head -n1)"
    if [[ -n "$first_file" ]]; then
        echo "${key}=${new_value}" >> "$first_file"
        info "Appended '${key}' to $(basename "$(dirname "$first_file")")/build.prop"
        return 0
    fi

    error "No build.prop files found in $base_dir"
    return 1
}

# ─── init.rc helpers ─────────────────────────────────────────────────────────
setprop_rc() {
    local target_section="$1"
    local insert_value="$2"
    local file="$3"

    [[ -f "$file" ]] || { error "File '$file' not found"; return 1; }

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

# ─── Smali file movers ───────────────────────────────────────────────────────
mvsml() {
    local file_name="$1"
    local target_folder="$2"
    local framework_dir="$3"

    local file_path
    file_path="$(find "$framework_dir" -type f -name "$file_name" | head -n1)"
    [[ -z "$file_path" ]] && { echo "File $file_name not found in $framework_dir."; return 1; }

    local parent_dex_folder relative_path target_path
    parent_dex_folder="$(dirname "$file_path" | sed "s|${framework_dir}/||" | cut -d/ -f1)"
    relative_path="$(echo "$file_path" | sed "s|${framework_dir}/${parent_dex_folder}/||")"
    target_path="${target_folder}/${relative_path}"

    mkdir -p "$(dirname "$target_path")"
    mv "$file_path" "$target_path"
    echo "Moved $file_name → $target_path"
}

mvdir() {
    local folder_name="$1"
    local target_folder="$2"
    local framework_dir="$3"

    local folder_path
    folder_path="$(find "$framework_dir" -type d -name "$folder_name" | head -n1)"
    [[ -z "$folder_path" ]] && { echo "Folder $folder_name not found in $framework_dir."; return 1; }

    while IFS= read -r file_path; do
        local parent_dex_folder relative_path target_path
        parent_dex_folder="$(dirname "$file_path" | sed "s|${framework_dir}/||" | cut -d/ -f1)"
        relative_path="$(echo "$file_path" | sed "s|${framework_dir}/${parent_dex_folder}/||")"
        target_path="${target_folder}/${relative_path}"
        mkdir -p "$(dirname "$target_path")"
        mv "$file_path" "$target_path"
    done < <(find "$folder_path" -type f -name "*.smali")

    echo "Moved all .smali files from $folder_name → $target_folder"
}

# ─── config.env validation ───────────────────────────────────────────────────
validate_config() {
    local cfg="${WORK_DIR}/config.env"

    [[ -f "$cfg" ]] || { error "config.env not found at $cfg"; exit 1; }

    local bool_keys=( "install_toolbox" "install_mods" )
    local errors=0

    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip blank lines and comments
        [[ -z "$key" || "$key" == \#* ]] && continue
        # Strip whitespace
        key="${key// /}"
        value="${value// /}"

        if [[ -z "$value" ]]; then
            warn "config.env: '$key' has no value — defaulting to 'false'"
            sed -i "s|^${key}=.*|${key}=false|" "$cfg"
            continue
        fi

        # Validate boolean keys
        for bk in "${bool_keys[@]}"; do
            if [[ "$key" == "$bk" ]]; then
                if [[ "$value" != "true" && "$value" != "false" ]]; then
                    error "config.env: '$key' must be 'true' or 'false', got '${value}'"
                    (( errors++ )) || true
                fi
                break
            fi
        done
    done < "$cfg"

    (( errors == 0 )) || { error "config.env validation failed with ${errors} error(s)."; exit 1; }
    info "config.env validated OK."
}

# ─── Read a single boolean config key safely ─────────────────────────────────
# Usage: read_config <key>   →  echoes "true" or "false"
read_config() {
    local key="$1"
    local cfg="${WORK_DIR}/config.env"
    local val
    val="$(grep -E "^${key}=" "$cfg" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')"
    echo "${val:-false}"
}

# ─── Export for subshells & exported functions ───────────────────────────────
export BIN_ARCH WORK_DIR
