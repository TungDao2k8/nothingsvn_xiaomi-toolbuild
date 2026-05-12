work_dir=$(pwd)
source $work_dir/functions.sh
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)

if [[ $rom_os == "MIUI14" ]]; then
mods "Starting Apply MIUI 14 Custom Mods File..."
TARGET_DIR="$work_dir/bin/modfile/MIUI14"
noexecute=( "insmod" )

find "$TARGET_DIR" -type f -name "*.sh" | while read -r script; do
    base="$(basename "$script" .sh)"

    skip=false
    for ex in "${noexecute[@]}"; do
        if [[ "$base" == "$ex" ]]; then
            skip=true
            break
        fi
    done

    if [[ $skip == false ]]; then
        bash "$script"
    fi
done
fi