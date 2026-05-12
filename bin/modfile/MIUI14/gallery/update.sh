work_dir=$(pwd)
source $work_dir/functions.sh
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt)
MAIN_FOLDER="$work_dir/build/baserom/images"

isOriginGallery=$(find "$MAIN_FOLDER" -type d \( \
    -name "MIUIGallery" -o -name "Gallery_T_CN" -o -name "MIUIGalleryT" \
    -o -name "MiuiGallery" -o -name "MIUIGalleryGlobalT" \
    -o -name "MIUIGalleryGlobal" \))
rm -rf $isOriginGallery

mkdir -p $work_dir/build/baserom/images/product/priv-app/MIUIGallery

# BUG FIX: Path sai "OS2/gallery" → đúng là "MIUI14/gallery"
# Thư mục OS2/gallery không tồn tại trong repo → cp crash với exit 1
cp -rf $work_dir/bin/modfile/MIUI14/gallery/MIUIGallery/* \
       $work_dir/build/baserom/images/product/priv-app/MIUIGallery
cp -rf $work_dir/bin/modfile/MIUI14/gallery/permissions/privapp_whitelist_com.miui.gallery.xml \
       $work_dir/build/baserom/images/product/etc/permissions/

mods "Added MIUIGallery Done!"
