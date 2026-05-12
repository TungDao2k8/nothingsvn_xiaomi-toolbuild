WORK_DIR=$(pwd)
source $WORK_DIR/functions.sh
MAIN_FOLDER="$WORK_DIR/build/baserom/images"
rom_os=$(cat $WORK_DIR/bin/ddevice/rom_os.txt)
AndroidVER=$(cat $WORK_DIR/bin/ddevice/androidver.txt)
APKEDITOR="java -jar $WORK_DIR/bin/apktool/apke.jar"
base_rom_code=$(cat $WORK_DIR/bin/ddevice/base_rom_code.txt)
myversion="$(cat $WORK_DIR/Version)"
repS="python3 $WORK_DIR/bin/strRep.py"

#patching
if [[ $rom_os == "MIUI" ]]; then

mods "Add ROM Information To MIUI"
  mkdir -p $WORK_DIR/apk_temp
  isSettingsDIR=$(find "$MAIN_FOLDER" -type d -name "Settings")
  isSettings=$(find "$MAIN_FOLDER" -type f -name "Settings.apk")

  if [[ -z "$isSettings" ]]; then
    echo "[WARN] Settings.apk not found — skipping."
    mods "Skipped"
    exit 0
  fi

  $APKEDITOR d -i "$isSettings" -o $WORK_DIR/apk_temp/isSettings.apk.out >/dev/null 2>&1

  mapfile -t p1_files < <(find "$WORK_DIR/apk_temp/isSettings.apk.out" -type f -name MiuiAboutPhoneUtils.smali)
  if [[ ${#p1_files[@]} -eq 0 ]]; then
      echo "[WARN] MiuiAboutPhoneUtils.smali not found — skipping."
      rm -rf $WORK_DIR/apk_temp
      mods "Skipped"
      exit 0
  fi

  # ─── BUG FIX ────────────────────────────────────────────────────────────────
  # mapfile điền vào MẢNG p1_files, nhưng code bên dưới lại dùng biến $p1 (chưa bao giờ được gán).
  # Với set -u trong functions.sh, tham chiếu $p1 → "unbound variable" → crash.
  # FIX: Gán p1 từ phần tử đầu tiên của mảng.
  # ────────────────────────────────────────────────────────────────────────────
  p1="${p1_files[0]}"

  sed -i "s/MIUI /MiuiK $myversion | /g" "$p1"
  sed -i "s/MIUI Pad /MiuiK $myversion | /g" "$p1"
  sed -i "s/MIUI Fold /MiuiK $myversion | /g" "$p1"

  mods "Rebuild..."
  Settings=$(basename $isSettings)
  $APKEDITOR b -f -i $WORK_DIR/apk_temp/isSettings.apk.out -o $WORK_DIR/apk_temp/final/$Settings >/dev/null 2>&1

  if [ -f "$WORK_DIR/apk_temp/final/$Settings" ]; then
    mods "Cleaning WorkSpace"
    rm -rf $isSettingsDIR/*
    mods "Finish Modding"
    cp -rf $WORK_DIR/apk_temp/final/$Settings $isSettingsDIR
    mods "Cleaned!"
  fi

  rm -rf $WORK_DIR/apk_temp
  mods "Adding MIUI Information Done!"
else

mods "Add ROM Information To HyperOS"
  mkdir -p $WORK_DIR/apk_temp
  isSettingsDIR=$(find "$MAIN_FOLDER" -type d -name "Settings")
  isSettings=$(find "$MAIN_FOLDER" -type f -name "Settings.apk")

  if [[ -z "$isSettings" ]]; then
    echo "[WARN] Settings.apk not found — skipping."
    mods "Skipped"
    exit 0
  fi

  $APKEDITOR d -i "$isSettings" -o $WORK_DIR/apk_temp/isSettings.apk.out >/dev/null 2>&1

  mapfile -t p1_files < <(find "$WORK_DIR/apk_temp/isSettings.apk.out" -type f -name MiuiAboutPhoneUtils.smali)
  if [[ ${#p1_files[@]} -eq 0 ]]; then
      echo "[WARN] MiuiAboutPhoneUtils.smali not found — skipping."
      rm -rf $WORK_DIR/apk_temp
      mods "Skipped"
      exit 0
  fi

  # ─── BUG FIX (giống nhánh MIUI phía trên) ──────────────────────────────────
  p1="${p1_files[0]}"
  # ────────────────────────────────────────────────────────────────────────────

  tar2="$WORK_DIR/bin/modfile/UpdateFile/Settings_ROMInformation/information.ini"
  my="$WORK_DIR/build/baserom/images/system/system/build.prop"

  $repS $tar2 "$p1"
  
  echo "ro.kioremy.version=HyperK $myversion | $base_rom_code" >> $my

  mods "Rebuild..."
  Settings=$(basename $isSettings)
  $APKEDITOR b -f -i $WORK_DIR/apk_temp/isSettings.apk.out -o $WORK_DIR/apk_temp/final/$Settings >/dev/null 2>&1

  if [ -f "$WORK_DIR/apk_temp/final/$Settings" ]; then
    mods "Cleaning WorkSpace"
    rm -rf $isSettingsDIR/*
    mods "Finish Modding"
    cp -rf $WORK_DIR/apk_temp/final/$Settings $isSettingsDIR
    mods "Cleaned!"
  fi

  rm -rf $WORK_DIR/apk_temp
  mods "Adding OS1/OS2 Information Done!"

fi
