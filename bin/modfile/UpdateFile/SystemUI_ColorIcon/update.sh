work_dir=$(pwd)
source $work_dir/functions.sh
MAIN_FOLDER="$work_dir/build/baserom/images"
repS="python3 $work_dir/bin/strRep.py"
deviceTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
APKEDITOR="java -jar $work_dir/bin/apktool/apke.jar"

if [[ $rom_os == "OS1" || $rom_os == "OS2" || $androidVER == "13" || $androidVER == "14" || $androidVER == "15" ]]; then
mods "Patching ColorIcon SystemUI"
mkdir -p $work_dir/apk_temp
isMiuiSystemUIDIR=$(find "$MAIN_FOLDER" -type d -name "MiuiSystemUI")
isMiuiSystemUI=$(find "$MAIN_FOLDER" -type f -name "MiuiSystemUI.apk")

# FIX: guard empty isMiuiSystemUI
if [[ -z "$isMiuiSystemUI" ]]; then
    echo "[WARN] MiuiSystemUI.apk not found — skipping."
    rm -rf $work_dir/apk_temp
    mods "Skipped"
    exit 0
fi

$APKEDITOR d -t raw -f -no-dex-debug -i "$isMiuiSystemUI" -o $work_dir/apk_temp/isMiuiSystemUI.apk.out >/dev/null 2>&1
    # FIX: mapfile for multi-file results
    mapfile -t smali1_files < <(find "$work_dir/apk_temp/isMiuiSystemUI.apk.out" -type f -name MiuiConfigs.smali)

    if [[ ${#smali1_files[@]} -eq 0 ]]; then
        echo "[WARN] MiuiConfigs.smali not found — skipping."
        rm -rf $work_dir/apk_temp
        mods "Skipped"
        exit 0
    fi

    for Smali1 in "${smali1_files[@]}"; do
        sed -i 's/"_global"/""/g' "$Smali1"
    done

MiuiSystemUI=$(basename "$isMiuiSystemUI")
$APKEDITOR b -f -i $work_dir/apk_temp/isMiuiSystemUI.apk.out -o $work_dir/apk_temp/final/$MiuiSystemUI >/dev/null 2>&1

if [ -f "$work_dir/apk_temp/final/$MiuiSystemUI" ]; then
    rm -rf $isMiuiSystemUIDIR/oat
    rm -rf $isMiuiSystemUIDIR/$MiuiSystemUI
    cp -rf $work_dir/apk_temp/final/$MiuiSystemUI $isMiuiSystemUIDIR
fi

rm -rf $work_dir/apk_temp
mods "Done"

fi
