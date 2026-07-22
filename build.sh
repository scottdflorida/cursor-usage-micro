#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app_name="Cursor Usage Micro"
app_dir="$project_dir/build/$app_name.app"
temporary_root=${TMPDIR:-/private/tmp}
staging_root=$(mktemp -d "${temporary_root%/}/cursor-usage-micro-build.XXXXXX")
staging_app="$staging_root/$app_name.app"
contents_dir="$staging_app/Contents"
binary_dir="$contents_dir/MacOS"
source_files=("$project_dir"/Sources/*.swift)
preserve_staging=0

cleanup_staging() {
  if (( preserve_staging == 0 )); then
    rm -rf "$staging_root"
  fi
}

remove_output_bundle() {
  if [[ -L "$app_dir" || -f "$app_dir" ]]; then
    rm -f "$app_dir"
  elif [[ -d "$app_dir" ]]; then
    rm -rf "$app_dir"
  fi
}

# iCloud File Provider can rewrite a bundle copied into a synced ~/Documents checkout and break its
# signature, so the copy is verified again after a settling pause, with the staging copy as fallback.
install_in_place() {
  remove_output_bundle
  ditto --noextattr --noqtn "$staging_app" "$app_dir" || return 1
  xattr -cr "$app_dir" || return 1
  codesign --verify --deep --strict "$app_dir" >/dev/null 2>&1 || return 1
  sleep 2
  codesign --verify --deep --strict "$app_dir" >/dev/null 2>&1
}

chmod 700 "$staging_root"
trap cleanup_staging EXIT

mkdir -p "$binary_dir" "$project_dir/build/ModuleCache"

swiftc \
  -O \
  -whole-module-optimization \
  -parse-as-library \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$project_dir/build/ModuleCache" \
  -framework AppKit \
  -framework Foundation \
  -lsqlite3 \
  "${source_files[@]}" \
  -o "$binary_dir/CursorUsageMicro"

plutil -lint "$project_dir/Info.plist" >/dev/null
cp "$project_dir/Info.plist" "$contents_dir/Info.plist"

xattr -cr "$staging_app"
codesign --force --sign - "$staging_app"
codesign --verify --deep --strict "$staging_app"

if ! install_in_place; then
  remove_output_bundle
  preserve_staging=1
  if ! ln -s "$staging_app" "$app_dir"; then
    preserve_staging=0
    exit 1
  fi
  if ! codesign --verify --deep --strict "$app_dir"; then
    rm -f "$app_dir"
    preserve_staging=0
    exit 1
  fi
  print -u2 -- "File Provider modified the copied bundle; using the signed external build."
fi

echo "$app_dir"
