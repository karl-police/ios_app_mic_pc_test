#!/bin/bash

PROJECT_NAME="iOS Mic Test"


PBXPROJ_FILE="$PWD/$PROJECT_NAME.xcodeproj/project.pbxproj"

# List files
# important, no / after end
INCLUDE_SWIFT_FILES=$(find "$PWD/$PROJECT_NAME/AutoInclude" -name '*.swift')


find "$INCLUDE_SWIFT_FILES" -name '*.swift' | while read -r swift_file; do
    file_name=$(basename "$swift_file")

    # we keep the project name
    cutoff_str="$PWD/"

    # Get relative path by removing BASE_PATH
    new_file_path_name="${swift_file#$cutoff_str}"

    #echo $new_file_path_name

    file_ref_id="${file_name%.swift}"
    file_ref_entry="$file_ref_id = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"$new_file_path_name\"; sourceTree = \"<project>\"; };"
    
    # Insert before
    sed -i "" "/\/\* Begin PBXSourcesBuildPhase section \*\//i\\
    $file_ref_entry\
    \
    " "$PBXPROJ_FILE"
    

    build_file_id="${file_ref_id}_BUILD"
    build_file_entry="$build_file_id = {isa = PBXBuildFile; fileRef = $file_ref_id; };"

    # Insert before
    sed -i "" "/\/\* Begin PBXSourcesBuildPhase section \*\//i\\
    $build_file_entry\
    \
    " "$PBXPROJ_FILE"

    # Append to marked section
    sed -i "" "/\/\* AUTOMATION_SCRIPT_ALERT_PUT_CONTENT_UNDER_HERE \*\//a\\
    \
    $build_file_id,\
    " "$PBXPROJ_FILE"
done

echo "Preparation finished!"

cat "$PBXPROJ_FILE"