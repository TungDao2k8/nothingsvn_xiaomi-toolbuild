WORK_DIR=$(pwd)
source $WORK_DIR/functions.sh
MAIN_FOLDER="$WORK_DIR/build/baserom/images"
androidVER=$(cat $WORK_DIR/bin/ddevice/androidver.txt)
APKEDITOR="java -jar $WORK_DIR/bin/apktool/apke.jar"
regionTYPE=$(cat $WORK_DIR/bin/ddevice/device_type.txt)

if [[ $regionTYPE == *"Global"* ]]; then

mods "Remove System Apps Updater"
mkdir -p $WORK_DIR/apk_temp
isSettingsDIR=$(find "$MAIN_FOLDER" -type d -name "Settings")
isSettings=$(find "$MAIN_FOLDER" -type f -name "Settings.apk")

# FIX: guard empty isSettings
if [[ -z "$isSettings" ]]; then
    echo "[WARN] Settings.apk not found — skipping."
    rm -rf $WORK_DIR/apk_temp
    mods "Skipped"
    exit 0
fi

$APKEDITOR d -t raw -f -no-dex-debug -i "$isSettings" -o $WORK_DIR/apk_temp/isSettings.apk.out >/dev/null 2>&1
isMiuiSettingsXML=$(find "$WORK_DIR/apk_temp/isSettings.apk.out" -type f -name settings_headers.xml)
# FIX: mapfile for multi-file results
mapfile -t xml2_files < <(find "$WORK_DIR/apk_temp/isSettings.apk.out" -type f -name AvailableVirtualKeyboardFragment.smali)

if [[ -n "$isMiuiSettingsXML" ]]; then
    sed -i '/<header android:icon="@drawable\/ic_system_apps_updater"/,/<\/header>/d' "$isMiuiSettingsXML"
else
    echo "[WARN] settings_headers.xml not found — skipping header removal."
fi

if [[ ${#xml2_files[@]} -gt 0 ]]; then
    for isMiuiSettingsXML2 in "${xml2_files[@]}"; do
        sed -i 's/com.baidu.input_mi/com.google.android.inputmethod.latin/g' "$isMiuiSettingsXML2"
    done
else
    echo "[WARN] AvailableVirtualKeyboardFragment.smali not found — skipping IME replacement."
fi

Settings=$(basename "$isSettings")
$APKEDITOR b -f -i $WORK_DIR/apk_temp/isSettings.apk.out -o $WORK_DIR/apk_temp/final/$Settings >/dev/null 2>&1

if [ -f "$WORK_DIR/apk_temp/final/$Settings" ]; then
    rm -rf $isSettingsDIR/*
    cp -rf $WORK_DIR/apk_temp/final/$Settings $isSettingsDIR
fi

rm -rf $WORK_DIR/apk_temp
mods "Done"

fi
