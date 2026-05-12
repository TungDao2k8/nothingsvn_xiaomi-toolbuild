#!/bin/bash
# ── SKIP: Remove Region Check for HyperOS — disabled ─────────────────────────
echo "[MODS] - Remove Region Check for HyperOS — SKIPPED"
exit 0
# ─────────────────────────────────────────────────────────────────────────────

# FIXED: Provisions_RegionPatch/update.sh
#
# ROOT CAUSE của crash:
#   apke.jar rebuild toàn bộ APK thất bại vì:
#   - Provision.apk trên HyperOS có thể dùng multi-dex
#   - apke.jar cần framework để rebuild resources
#   - -no-dex-debug có thể làm smali reassembly lỗi
#   Dẫn đến exit 1 → crash toàn bộ pipeline
#
# FIX ĐÚNG: Không dùng apke.jar rebuild toàn bộ APK.
#   Thay bằng pipeline chỉ patch dex:
#   1. unzip lấy classes*.dex từ Provision.apk
#   2. baksmali decompile từng dex → smali
#   3. Patch Utils.smali bằng Python regex (chính xác hơn strRep.py)
#   4. smali recompile → dex mới
#   5. Python zipfile update dex trong APK gốc (không đụng resources)
#
# Lợi ích:
#   - Không cần framework, không rebuild resources
#   - Multi-dex được xử lý đúng
#   - Baksmali/smali 3.0.5 đã có sẵn trong repo

work_dir=$(pwd)
source "$work_dir/functions.sh"
MAIN_FOLDER="$work_dir/build/baserom/images"
rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt")

BAKSMALI="java -jar $work_dir/bin/apktool/baksmali-3.0.5.jar"
SMALI="java -jar $work_dir/bin/apktool/smali-3.0.5.jar"

if [[ $rom_os == "OS3" || $rom_os == "OS2" || $rom_os == "OS1" ]]; then
    mods "Remove Region Check for HyperOS"

    TMPDIR="$work_dir/apk_temp/provision_patch"
    rm -rf "$TMPDIR"
    mkdir -p "$TMPDIR/dex_out" "$TMPDIR/smali_out"

    # ── Tìm Provision.apk ────────────────────────────────────────────────────
    isProvision=$(find "$MAIN_FOLDER" -type f -name "Provision.apk" | head -n1)
    isProvisionDIR=$(find "$MAIN_FOLDER" -type d -name "Provision" | head -n1)

    if [[ -z "$isProvision" ]]; then
        echo "[WARN] Provision.apk not found — skipping region check patch."
        rm -rf "$TMPDIR"
        mods "Skipped"
        exit 0
    fi

    # ── Copy APK ra ngoài để thao tác (không sửa trực tiếp file gốc) ─────────
    cp "$isProvision" "$TMPDIR/Provision.apk"

    # ── Lấy danh sách các file dex trong APK ─────────────────────────────────
    dex_list=$(unzip -l "$TMPDIR/Provision.apk" | grep -oP 'classes[0-9]*\.dex' | sort -u)
    if [[ -z "$dex_list" ]]; then
        echo "[WARN] No dex files found in Provision.apk — skipping."
        rm -rf "$TMPDIR"
        mods "Skipped"
        exit 0
    fi

    patched=false

    for dex_file in $dex_list; do
        dex_smali_dir="$TMPDIR/smali_out/$dex_file"
        mkdir -p "$dex_smali_dir"

        # Extract dex
        unzip -p "$TMPDIR/Provision.apk" "$dex_file" > "$TMPDIR/dex_out/$dex_file" 2>/dev/null
        [[ -s "$TMPDIR/dex_out/$dex_file" ]] || continue

        # Decompile dex → smali
        $BAKSMALI d "$TMPDIR/dex_out/$dex_file" -o "$dex_smali_dir" 2>/dev/null || {
            echo "[WARN] baksmali failed on $dex_file — skipping this dex."
            continue
        }

        # Tìm smali chứa checkVersionConsistent
        utils_smali=$(grep -rl "checkVersionConsistent" "$dex_smali_dir" 2>/dev/null | head -n1)

        if [[ -z "$utils_smali" ]]; then
            continue  # method không nằm trong dex này, thử dex tiếp theo
        fi

        echo "[INFO] Found checkVersionConsistent in: $utils_smali"

        # ── Patch smali bằng Python regex ─────────────────────────────────────
        python3 << PYEOF
import sys, re

filepath = "$utils_smali"
with open(filepath, 'r') as f:
    content = f.read()

pattern = re.compile(
    r'(\.method\s+public\s+static\s+checkVersionConsistent\(\)Z\s*\n)'
    r'(.*?)'
    r'(\.end method)',
    re.DOTALL
)

replacement = (
    r'\g<1>'
    '    .registers 1\n'
    '\n'
    '    const/4 v0, 0x1\n'
    '\n'
    '    return v0\n'
    r'\g<3>'
)

new_content, count = re.subn(pattern, replacement, content)
if count == 0:
    print(f"[WARN] Pattern not found in {filepath}")
    sys.exit(1)

with open(filepath, 'w') as f:
    f.write(new_content)

print(f"[INFO] Patched {count} occurrence(s) of checkVersionConsistent")
PYEOF

        patch_rc=$?
        if [[ $patch_rc -ne 0 ]]; then
            echo "[WARN] Python patch failed — skipping."
            continue
        fi

        # ── Recompile smali → dex ─────────────────────────────────────────────
        $SMALI a "$dex_smali_dir" -o "$TMPDIR/dex_out/${dex_file}.patched" 2>/dev/null || {
            echo "[ERROR] smali recompile failed for $dex_file"
            rm -rf "$TMPDIR"
            exit 1
        }

        # ── Update dex trong APK bằng Python zipfile ──────────────────────────
        # (zip -u sẽ thêm entry mới với tên khác, không rename được)
        python3 << PYEOF
import zipfile, os, sys

apk_path   = "$TMPDIR/Provision.apk"
entry_name = "$dex_file"
new_dex    = "$TMPDIR/dex_out/${dex_file}.patched"
tmp_path   = apk_path + ".tmp"

with zipfile.ZipFile(apk_path, 'r') as zin, \
     zipfile.ZipFile(tmp_path, 'w', compression=zipfile.ZIP_STORED) as zout:
    for item in zin.infolist():
        if item.filename == entry_name:
            with open(new_dex, 'rb') as f:
                zout.writestr(item, f.read())
            print(f"[INFO] Replaced {entry_name} in APK")
        else:
            zout.writestr(item, zin.read(item.filename))

os.replace(tmp_path, apk_path)
print("[INFO] APK updated successfully")
PYEOF

        patched=true
        echo "[INFO] $dex_file patched."
        break
    done

    if [[ "$patched" != true ]]; then
        echo "[WARN] checkVersionConsistent not found in any dex — skipping."
        rm -rf "$TMPDIR"
        mods "Skipped"
        exit 0
    fi

    # ── Copy APK đã patch về đúng vị trí ─────────────────────────────────────
    Provision=$(basename "$isProvision")
    if [[ -n "$isProvisionDIR" && -d "$isProvisionDIR" ]]; then
        cp "$TMPDIR/Provision.apk" "$isProvisionDIR/$Provision"
    else
        cp "$TMPDIR/Provision.apk" "$isProvision"
    fi

    rm -rf "$TMPDIR"
    mods "Done"
fi
