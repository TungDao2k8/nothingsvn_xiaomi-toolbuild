#!/bin/bash
# Settings_GlobalFixTheme/update.sh
# FIX: Bỏ điều kiện Global-only — áp dụng cho cả China ROM (Android 13-16).

WORK_DIR=$(pwd)
source "$WORK_DIR/functions.sh"
MAIN_FOLDER="$WORK_DIR/build/baserom/images"
androidVER=$(cat "$WORK_DIR/bin/ddevice/androidver.txt")
APKEDITOR="java -jar $WORK_DIR/bin/apktool/apke.jar"
regionTYPE=$(cat "$WORK_DIR/bin/ddevice/device_type.txt")

# FIX: Bỏ `&& $regionTYPE == *"Global"*` — patch áp dụng cho cả China ROM.
if [[ $androidVER == "16" || $androidVER == "15" || $androidVER == "14" || $androidVER == "13" ]]; then

    mods "Fixing Theme Issues"
    mkdir -p "$WORK_DIR/apk_temp/final"

    isSettingsDIR=$(find "$MAIN_FOLDER" -type d -name "Settings")
    isSettings=$(find "$MAIN_FOLDER" -type f -name "Settings.apk")

    if [ -z "$isSettings" ]; then
        echo "[WARN] Settings.apk not found, skipping theme fix."
        rm -rf "$WORK_DIR/apk_temp"
        mods "Skipped"
        exit 0
    fi

    $APKEDITOR d -t raw -f -no-dex-debug -i "$isSettings" \
        -o "$WORK_DIR/apk_temp/isSettings.apk.out" >/dev/null 2>&1

    mapfile -t smali_files < <(find "$WORK_DIR/apk_temp/isSettings.apk.out" \
        -type f -name "MiuiSettings.smali")

    if [[ ${#smali_files[@]} -eq 0 ]]; then
        echo "[WARN] MiuiSettings.smali not found, skipping theme fix."
        rm -rf "$WORK_DIR/apk_temp"
        mods "Skipped"
        exit 0
    fi

    for isMiuiSettingsSmali in "${smali_files[@]}"; do
        sed -i '
    /sget v10, Lcom\/android\/settings\/R$id;->personalize_title:I/,/sget-boolean v10, Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/ {
        /sget-boolean v10, Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/c\    const/4 v10, 0
    }
        ' "$isMiuiSettingsSmali"

        sed -i '
    /sget v10, Lcom\/android\/settings\/R$id;->theme_settings:I/,/sget-boolean v10, Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/ {
        /sget-boolean v10, Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/c\    const/4 v10, 0
    }
        ' "$isMiuiSettingsSmali"

        sed -i '
    /sget v10, Lcom\/android\/settings\/R$id;->wallpaper_settings:I/,/sget-boolean v10, Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/ {
        /sget-boolean v10, Lmiui\/os\/Build;->IS_INTERNATIONAL_BUILD:Z/c\    const/4 v10, 0
    }
        ' "$isMiuiSettingsSmali"
    done

    Settings=$(basename "$isSettings")
    $APKEDITOR b -f -i "$WORK_DIR/apk_temp/isSettings.apk.out" \
        -o "$WORK_DIR/apk_temp/final/$Settings" >/dev/null 2>&1

    if [ -f "$WORK_DIR/apk_temp/final/$Settings" ]; then
        if [ -n "$isSettingsDIR" ] && [ -d "$isSettingsDIR" ]; then
            rm -rf "${isSettingsDIR:?}"/*
            cp -rf "$WORK_DIR/apk_temp/final/$Settings" "$isSettingsDIR/"
        fi
    else
        echo "[WARN] APK rebuild failed for Settings theme fix — skipping."
        mods "Skipped (rebuild failed)"
    fi

    rm -rf "$WORK_DIR/apk_temp"
    mods "Done"
else
    mods "Skipped — Android ${androidVER} không được hỗ trợ (cần A13-A16)"
fi
