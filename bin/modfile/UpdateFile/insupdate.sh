#!/bin/bash
# FIXED: insupdate.sh
# Bug 1: while read loop runs in a SUBSHELL (piped from find), so
#         the noexecute array set in the parent is NOT visible inside it.
#         Using process substitution < <(find ...) fixes the scoping.
# Bug 2: A failed subscript exits 0 silently because the while/pipe
#         swallows the exit code. Now errors propagate properly.
# Bug 3: Missing quotes around variables (word splitting / glob risks).

work_dir=$(pwd)
source "$work_dir/functions.sh"

mods "Starting Update File..."
TARGET_DIR="$work_dir/bin/modfile/UpdateFile"
noexecute=( "insupdate" )

# FIX: use process substitution so noexecute array is visible and exit
#      codes from bash "$script" propagate to the outer shell.
while IFS= read -r script; do
    base="$(basename "$script" .sh)"

    skip=false
    for ex in "${noexecute[@]}"; do
        if [[ "$base" == "$ex" ]]; then
            skip=true
            break
        fi
    done

    if [[ "$skip" == false ]]; then
        bash "$script"
    fi
done < <(find "$TARGET_DIR" -type f -name "*.sh")
